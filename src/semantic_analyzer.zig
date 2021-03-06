const std = @import("std");
const eql = std.meta.eql;
const Allocator = std.mem.Allocator;
const Arena = std.heap.ArenaAllocator;
const assert = std.debug.assert;
const panic = std.debug.panic;

const init_codebase = @import("init_codebase.zig");
const initCodebase = init_codebase.initCodebase;
const initBuiltins = init_codebase.initBuiltins;
const List = @import("list.zig").List;
const ecs = @import("ecs.zig");
const Entity = ecs.Entity;
const ECS = ecs.ECS;
const strings = @import("strings.zig");
const Strings = strings.Strings;
const InternedString = strings.InternedString;
const tokenize = @import("tokenizer.zig").tokenize;
const parse = @import("parser.zig").parse;
const MockFileSystem = @import("file_system.zig").FileSystem;
const components = @import("components.zig");
const query = @import("query.zig");
const literalOf = query.literalOf;
const typeOf = query.typeOf;
const parentType = query.parentType;
const valueType = query.valueType;
const colors = @import("colors.zig");

fn Context(comptime FileSystem: type) type {
    return struct {
        allocator: Allocator,
        codebase: *ECS,
        file_system: FileSystem,
        module: Entity,
        function: Entity,
        active_scopes: []const u64,
        builtins: *const components.Builtins,

        const Self = @This();

        const Match = enum {
            no,
            implicit_conversion,
            exact,
        };

        fn convertibleTo(self: *Self, to: Entity, from: Entity) Match {
            if (eql(to, from)) return .exact;
            const b = self.builtins;
            const builtins = [_]Entity{ b.I64, b.I32, b.I16, b.I8, b.U64, b.U32, b.U16, b.U8, b.F64, b.F32 };
            const float_builtins = [_]Entity{ b.F64, b.F32 };
            if (eql(from, b.IntLiteral)) {
                for (builtins) |builtin| {
                    if (eql(to, builtin)) return .implicit_conversion;
                }
                if (eql(to, b.FloatLiteral)) return .implicit_conversion;
                return .no;
            }
            if (eql(from, b.FloatLiteral)) {
                for (float_builtins) |builtin| {
                    if (eql(to, builtin)) return .implicit_conversion;
                }
                return .no;
            }
            if (from.has(components.ParentType)) |parent_type| {
                assert(eql(parent_type.entity, b.Array));
                const from_value_type = from.get(components.ValueType).entity;
                const to_value_type = to.get(components.ValueType).entity;
                return self.convertibleTo(to_value_type, from_value_type);
            }
            return .no;
        }

        fn implicitTypeConversion(self: *Self, value: Entity, expected_type: Entity) error{OutOfMemory}!void {
            const actual_type = typeOf(value);
            const b = self.builtins;
            assert(self.convertibleTo(expected_type, actual_type) != .no);
            _ = try value.set(.{components.Type.init(expected_type)});
            if (value.has(components.DependentEntities)) |dependent_entities| {
                for (dependent_entities.slice()) |entity| {
                    const t = typeOf(entity);
                    if (!eql(t, b.IntLiteral) and !eql(t, b.FloatLiteral)) continue;
                    try self.implicitTypeConversion(entity, expected_type);
                }
            }
        }

        fn unifyTypes(self: *Self, lhs: Entity, rhs: Entity) !Entity {
            const lhs_type = typeOf(lhs);
            const rhs_type = typeOf(rhs);
            switch (self.convertibleTo(lhs_type, rhs_type)) {
                .exact => return lhs_type,
                .implicit_conversion => {
                    _ = try rhs.set(.{components.Type.init(lhs_type)});
                    if (rhs.has(components.DependentEntities)) |dependent_entities| {
                        for (dependent_entities.slice()) |entity| {
                            try self.implicitTypeConversion(entity, lhs_type);
                        }
                    }
                    return lhs_type;
                },
                .no => {
                    switch (self.convertibleTo(rhs_type, lhs_type)) {
                        .exact => return rhs_type,
                        .implicit_conversion => {
                            _ = try lhs.set(.{components.Type.init(rhs_type)});
                            if (lhs.has(components.DependentEntities)) |dependent_entities| {
                                for (dependent_entities.slice()) |entity| {
                                    try self.implicitTypeConversion(entity, rhs_type);
                                }
                            }
                            return rhs_type;
                        },
                        .no => {
                            panic("\ncannot unify {s} and {s}\n", .{
                                literalOf(lhs_type),
                                literalOf(rhs_type),
                            });
                        },
                    }
                },
            }
        }

        fn analyzeSymbol(self: *Self, entity: Entity) !Entity {
            const literal = entity.get(components.Literal);
            const scopes = self.function.get(components.Scopes);
            if (scopes.hasLiteral(literal)) |local| {
                return local;
            }
            const global_scope = self.codebase.get(components.Scope);
            if (global_scope.hasLiteral(literal)) |global| {
                return global;
            }
            const top_level_scope = self.module.get(components.TopLevel);
            if (top_level_scope.hasLiteral(literal)) |top_level| {
                assert(top_level.get(components.AstKind) == .overload_set);
                const overloads = top_level.get(components.Overloads).slice();
                assert(overloads.len == 1);
                const overload = overloads[0];
                assert(overload.get(components.AstKind) == .struct_);
                return overload;
            }
            panic("\nanalyzeSymbol failed for symbol {s}\n", .{literalOf(entity)});
        }

        const Candidate = struct {
            overload: Entity,
            match: Match,
            named_arguments: components.OrderedNamedArguments,
            literal: components.Literal,
            module: Entity,
        };

        const CalleeContext = struct {
            module: Entity,
            call: Entity,
            callable: Entity,
            arguments: []const Entity,
            named_arguments: components.NamedArguments,
            literal: components.Literal,
        };

        fn checkCandidatesForModule(self: *Self, callee_context: CalleeContext, candidate: *Candidate, ordered_named_arguments: []Entity) !void {
            const top_level = self.module.get(components.TopLevel);
            if (top_level.hasLiteral(candidate.literal)) |function| {
                const overloads = function.get(components.Overloads).slice();
                for (overloads) |overload| {
                    const kind = overload.get(components.AstKind);
                    if (kind == .struct_) {
                        const fields = overload.get(components.Fields).slice();
                        if (!overload.contains(components.AnalyzedFields)) {
                            for (fields) |field| {
                                const field_type = try self.analyzeExpression(field.get(components.TypeAst).entity);
                                _ = try field.set(.{
                                    components.Type.init(field_type),
                                    components.Name.init(field),
                                });
                            }
                            _ = try overload.set(.{components.AnalyzedFields{ .value = true }});
                        }
                        if (fields.len < callee_context.arguments.len) continue;
                        var match = Match.exact;
                        var i: usize = 0;
                        while (i < callee_context.arguments.len) : (i += 1) {
                            const field_type = typeOf(fields[i]);
                            const argument_type = typeOf(callee_context.arguments[i]);
                            switch (self.convertibleTo(field_type, argument_type)) {
                                .exact => continue,
                                .implicit_conversion => if (match == .exact) {
                                    match = .implicit_conversion;
                                },
                                .no => {
                                    match = .no;
                                    break;
                                },
                            }
                        }
                        while (i < fields.len) : (i += 1) {
                            const field = fields[i];
                            const field_type = typeOf(field);
                            if (callee_context.named_arguments.hasLiteral(field.get(components.Literal))) |argument| {
                                ordered_named_arguments[i - callee_context.arguments.len] = argument;
                                const argument_type = typeOf(argument);
                                switch (self.convertibleTo(field_type, argument_type)) {
                                    .exact => continue,
                                    .implicit_conversion => if (match == .exact) {
                                        match = .implicit_conversion;
                                    },
                                    .no => {
                                        match = .no;
                                        break;
                                    },
                                }
                            } else {
                                match = .no;
                                break;
                            }
                        }
                        if (@enumToInt(match) < @enumToInt(candidate.match)) continue;
                        if (match != .no and match == candidate.match) {
                            panic("ambiguous overload set overload match {} best match {}", .{ match, candidate.match });
                        }
                        candidate.match = match;
                        candidate.overload = overload;
                        candidate.module = self.module;
                        std.mem.copy(Entity, candidate.named_arguments.mutSlice(), ordered_named_arguments);
                        continue;
                    }
                    assert(kind == .function);
                    if (!overload.contains(components.AnalyzedParameters)) {
                        var scopes = components.Scopes.init(self.allocator, self.codebase.getPtr(Strings));
                        const scope = try scopes.pushScope();
                        _ = try overload.set(.{scopes});
                        const active_scopes = [_]u64{scope};
                        var context = Self{
                            .allocator = self.allocator,
                            .codebase = self.codebase,
                            .file_system = self.file_system,
                            .module = self.module,
                            .function = overload,
                            .active_scopes = &active_scopes,
                            .builtins = self.builtins,
                        };
                        try context.analyzeFunctionParameters();
                    }
                    const parameters = overload.get(components.Parameters).slice();
                    if (parameters.len < callee_context.arguments.len) continue;
                    var match = Match.exact;
                    var i: usize = 0;
                    while (i < callee_context.arguments.len) : (i += 1) {
                        const parameter_type = typeOf(parameters[i]);
                        const argument_type = typeOf(callee_context.arguments[i]);
                        switch (self.convertibleTo(parameter_type, argument_type)) {
                            .exact => continue,
                            .implicit_conversion => if (match == .exact) {
                                match = .implicit_conversion;
                            },
                            .no => {
                                match = .no;
                                break;
                            },
                        }
                    }
                    while (i < parameters.len) : (i += 1) {
                        const parameter = parameters[i];
                        const parameter_type = typeOf(parameter);
                        if (callee_context.named_arguments.hasLiteral(parameter.get(components.Literal))) |argument| {
                            ordered_named_arguments[i - callee_context.arguments.len] = argument;
                            const argument_type = typeOf(argument);
                            switch (self.convertibleTo(parameter_type, argument_type)) {
                                .exact => continue,
                                .implicit_conversion => if (match == .exact) {
                                    match = .implicit_conversion;
                                },
                                .no => {
                                    match = .no;
                                    break;
                                },
                            }
                        } else {
                            match = .no;
                            break;
                        }
                    }
                    if (@enumToInt(match) < @enumToInt(candidate.match)) continue;
                    if (match != .no and match == candidate.match) {
                        panic("ambiguous overload set overload match {} best match {}", .{ match, candidate.match });
                    }
                    candidate.match = match;
                    candidate.overload = overload;
                    candidate.module = self.module;
                    std.mem.copy(Entity, candidate.named_arguments.mutSlice(), ordered_named_arguments);
                }
            } else {}
        }

        fn bestOverloadCandidate(self: *Self, callee_context: CalleeContext) !Candidate {
            const count = callee_context.named_arguments.count();
            var candidate = Candidate{
                .overload = undefined,
                .match = .no,
                .named_arguments = try components.OrderedNamedArguments.withCapacity(self.allocator, count),
                .literal = callee_context.callable.get(components.Literal),
                .module = undefined,
            };
            candidate.named_arguments.values.len = count;
            var ordered_named_arguments = try self.allocator.alloc(Entity, count);
            try checkCandidatesForModule(self, callee_context, &candidate, ordered_named_arguments);
            const imports = self.module.get(components.Imports).slice();
            for (imports) |import| {
                const module = blk: {
                    if (import.has(components.Module)) |m| {
                        break :blk m.entity;
                    } else {
                        const module_name = literalOf(import.get(components.Path).entity);
                        const contents = try self.file_system.read(module_name);
                        const interned = try self.codebase.getPtr(Strings).intern(module_name[0 .. module_name.len - 5]);
                        const module = try self.codebase.createEntity(.{components.Literal.init(interned)});
                        var tokens = try tokenize(module, contents);
                        try parse(module, &tokens);
                        const source = components.ModuleSource{ .string = contents };
                        const path = components.ModulePath{ .string = module_name };
                        _ = try module.set(.{
                            source,
                            path,
                        });
                        _ = try import.set(.{components.Module.init(module)});
                        break :blk module;
                    }
                };
                var context = Self{
                    .allocator = self.allocator,
                    .codebase = self.codebase,
                    .file_system = self.file_system,
                    .module = module,
                    .function = self.function,
                    .active_scopes = self.active_scopes,
                    .builtins = self.builtins,
                };
                try checkCandidatesForModule(&context, callee_context, &candidate, ordered_named_arguments);
            }
            if (candidate.match == .no) {
                var body = List(u8, .{ .initial_capacity = 1000 }).init(self.allocator);
                try body.appendSlice("No matching function overload found for argument types (");
                for (callee_context.arguments) |argument, i| {
                    const argument_type = typeOf(argument);
                    try body.appendSlice(literalOf(argument_type));
                    if (i < callee_context.arguments.len - 1) {
                        try body.appendSlice(", ");
                    }
                }
                try body.append(')');
                var hint = List(u8, .{ .initial_capacity = 1000 }).init(self.allocator);
                try hint.appendSlice("Here are the possible candidates:\n");
                var candidates = List(List(u8, .{}), .{ .initial_capacity = 8 }).init(self.allocator);
                var file_and_lines = List(List(u8, .{}), .{ .initial_capacity = 8 }).init(self.allocator);
                var candidate_width: usize = 0;
                const top_level = self.module.get(components.TopLevel);

                if (top_level.hasLiteral(candidate.literal)) |function| {
                    const overloads = function.get(components.Overloads).slice();
                    for (overloads) |overload| {
                        var candidate_error = List(u8, .{}).init(self.allocator);
                        try candidate_error.append('\n');
                        try candidate_error.appendSlice(literalOf(overload.get(components.Name).entity));
                        try candidate_error.append('(');
                        const parameters = overload.get(components.Parameters).slice();
                        for (parameters) |parameter, i| {
                            const parameter_type = typeOf(parameter);
                            var mismatch = false;
                            if (i < callee_context.arguments.len) {
                                mismatch = self.convertibleTo(parameter_type, typeOf(callee_context.arguments[i])) == .no;
                            } else {
                                mismatch = true;
                            }
                            if (mismatch) {
                                try candidate_error.appendSlice(colors.RED);
                            }
                            try candidate_error.appendSlice(literalOf(parameter));
                            try candidate_error.appendSlice(": ");
                            try candidate_error.appendSlice(literalOf(parameter_type));
                            if (mismatch) {
                                try candidate_error.appendSlice(colors.RESET);
                            }
                            if (i < parameters.len - 1) {
                                try candidate_error.appendSlice(", ");
                            }
                        }
                        try candidate_error.append(')');
                        try candidates.append(candidate_error);
                        candidate_width = std.math.max(candidate_width, candidate_error.len);
                        var file_and_line = List(u8, .{}).init(self.allocator);
                        try file_and_line.appendSlice(self.module.get(components.ModulePath).string);
                        try file_and_line.append(':');
                        const result = try std.fmt.allocPrint(self.allocator, "{}", .{overload.get(components.Span).begin.row + 1});
                        try file_and_line.appendSlice(result);
                        try file_and_lines.append(file_and_line);
                    }
                }

                const file_and_lines_slice = file_and_lines.slice();
                for (candidates.slice()) |candidate_error, i| {
                    const candidate_slice = candidate_error.slice();
                    try hint.appendSlice(candidate_slice);
                    const delta = candidate_width - candidate_slice.len;
                    var spaces: usize = 0;
                    while (spaces < delta) : (spaces += 1) {
                        try hint.append(' ');
                    }
                    try hint.appendSlice(" ----- ");
                    try hint.appendSlice(file_and_lines_slice[i].slice());
                }
                try hint.append('\n');
                const error_component = components.Error{
                    .header = "FUNCTION CALL ERROR",
                    .body = body.mutSlice(),
                    .span = callee_context.call.get(components.Span),
                    .hint = hint.mutSlice(),
                    .module = self.module,
                };
                _ = try callee_context.call.set(.{error_component});
                return error.CompileError;
            }
            _ = try callee_context.call.set(.{candidate.named_arguments});
            return candidate;
        }

        fn analyzePointer(self: *Self, entity: Entity) !Entity {
            const value = try self.analyzeExpression(entity.get(components.Value).entity);
            const b = self.builtins;
            const type_of = typeOf(value);
            if (eql(type_of, b.Type)) {
                const memoized = b.Ptr.getPtr(components.Memoized);
                const result = try memoized.getOrPut(value);
                if (result.found_existing) {
                    return result.value_ptr.*;
                }
                const string = try std.fmt.allocPrint(self.allocator, "*{s}", .{literalOf(value)});
                const interned = try self.codebase.getPtr(Strings).intern(string);
                const pointer_type = try self.codebase.createEntity(.{
                    components.Literal.init(interned),
                    components.Type.init(b.Type),
                    components.ParentType.init(b.Ptr),
                    components.ValueType.init(value),
                });
                result.value_ptr.* = pointer_type;
                return pointer_type;
            }
            assert(eql(parentType(type_of), b.Ptr));
            const value_type = valueType(type_of);
            const scalars = [_]Entity{ b.I64, b.I32, b.I16, b.I8, b.U64, b.U32, b.U16, b.U8, b.F64, b.F32 };
            for (scalars) |scalar| {
                if (eql(value_type, scalar)) {
                    return try self.codebase.createEntity(.{
                        components.AstKind.intrinsic,
                        components.Intrinsic.load,
                        try components.Arguments.fromSlice(self.allocator, &.{value}),
                        components.Type.init(valueType(type_of)),
                    });
                }
            }
            const vectors = [_]Entity{ b.I64X2, b.I32X4, b.I16X8, b.I8X16, b.U64X2, b.U32X4, b.U16X8, b.U8X16, b.F64X2, b.F32X4 };
            for (vectors) |vector| {
                if (eql(value_type, vector)) {
                    return try self.codebase.createEntity(.{
                        components.AstKind.intrinsic,
                        components.Intrinsic.v128_load,
                        try components.Arguments.fromSlice(self.allocator, &.{value}),
                        components.Type.init(valueType(type_of)),
                    });
                }
            }
            panic("\npointer of type {s} not supported yet\n", .{literalOf(value_type)});
        }

        fn arrayType(self: *Self, T: Entity) !Entity {
            const literal = literalOf(T);
            const b = self.builtins;
            assert(eql(typeOf(T), b.Type));
            const memoized = b.Array.getPtr(components.Memoized);
            const result = try memoized.getOrPut(T);
            if (result.found_existing) {
                return result.value_ptr.*;
            }
            var fields = components.Fields.init(self.allocator);
            {
                const interned = try self.codebase.getPtr(Strings).intern("ptr");
                const pointer_memoized = b.Ptr.getPtr(components.Memoized);
                const pointer_result = try pointer_memoized.getOrPut(T);
                const pointer_type = blk: {
                    if (pointer_result.found_existing) {
                        break :blk pointer_result.value_ptr.*;
                    } else {
                        const pointer_string = try std.fmt.allocPrint(self.allocator, "*{s}", .{literal});
                        const pointer_interned = try self.codebase.getPtr(Strings).intern(pointer_string);
                        const pointer_type = try self.codebase.createEntity(.{
                            components.Literal.init(pointer_interned),
                            components.Type.init(b.Type),
                            components.ParentType.init(b.Ptr),
                            components.ValueType.init(T),
                        });
                        pointer_result.value_ptr.* = pointer_type;
                        break :blk pointer_type;
                    }
                };
                const ptr = try self.codebase.createEntity(.{
                    components.Literal.init(interned),
                    components.Type.init(pointer_type),
                });
                _ = try ptr.set(.{components.Name.init(ptr)});
                try fields.append(ptr);
            }
            {
                const interned = try self.codebase.getPtr(Strings).intern("len");
                const len = try self.codebase.createEntity(.{
                    components.Literal.init(interned),
                    components.Type.init(b.I32),
                });
                _ = try len.set(.{components.Name.init(len)});
                try fields.append(len);
            }
            const string = try std.fmt.allocPrint(self.allocator, "[]{s}", .{literal});
            const interned = try self.codebase.getPtr(Strings).intern(string);
            const array_type = try self.codebase.createEntity(.{
                components.AstKind.struct_,
                components.Literal.init(interned),
                components.Type.init(b.Type),
                components.ParentType.init(b.Array),
                components.ValueType.init(T),
                fields,
            });
            result.value_ptr.* = array_type;
            return array_type;
        }

        fn analyzeArray(self: *Self, entity: Entity) !Entity {
            const value = try self.analyzeExpression(entity.get(components.Value).entity);
            return try self.arrayType(value);
        }

        fn analyzeCast(self: *Self, arguments: []const Entity) !Entity {
            assert(arguments.len == 2);
            const b = self.builtins;
            const to = arguments[0];
            assert(eql(parentType(to), b.Ptr));
            const value = arguments[1];
            try self.implicitTypeConversion(value, b.I32);
            return try self.codebase.createEntity(.{
                components.AstKind.cast,
                components.Type.init(to),
                components.Value.init(value),
            });
        }

        fn analyzeCall(self: *Self, call: Entity, callingContext: *Self) !Entity {
            const callable = call.get(components.Callable).entity;
            const call_arguments = call.get(components.Arguments).slice();
            var analyzed_arguments = try components.Arguments.withCapacity(self.allocator, call_arguments.len);
            for (call_arguments) |argument| {
                const analyzed_argument = try callingContext.analyzeExpression(argument);
                analyzed_arguments.appendAssumeCapacity(analyzed_argument);
            }
            var analyzed_named_arguments = components.NamedArguments.init(self.allocator, call.ecs.getPtr(Strings));
            var iterator = call.get(components.NamedArguments).iterator();
            while (iterator.next()) |pair| {
                const argument = pair.value_ptr.*;
                const analyzed_argument = try callingContext.analyzeExpression(argument);
                try analyzed_named_arguments.putInterned(pair.key_ptr.*, analyzed_argument);
            }
            const callable_literal = callable.get(components.Literal);
            if (eql(callable_literal, self.builtins.Cast.get(components.Literal))) {
                return try self.analyzeCast(analyzed_arguments.slice());
            }
            const analyzed_arguments_slice = analyzed_arguments.slice();

            const candidate = try self.bestOverloadCandidate(.{
                .module = self.module,
                .call = call,
                .callable = callable,
                .arguments = analyzed_arguments_slice,
                .named_arguments = analyzed_named_arguments,
                .literal = callable.get(components.Literal),
            });

            const kind = candidate.overload.get(components.AstKind);
            if (kind == .function) {
                if (!candidate.overload.contains(components.AnalyzedBody)) {
                    _ = try candidate.overload.set(.{components.AnalyzedBody{ .value = true }});
                    const scopes = candidate.overload.getPtr(components.Scopes).slice();
                    assert(scopes.len == 1);
                    const active_scopes = [_]u64{0};
                    var context = Self{
                        .allocator = self.allocator,
                        .codebase = self.codebase,
                        .file_system = self.file_system,
                        .module = candidate.module,
                        .function = candidate.overload,
                        .active_scopes = &active_scopes,
                        .builtins = self.builtins,
                    };
                    try context.analyzeFunction();
                }
                const parameters = candidate.overload.get(components.Parameters).slice();
                var i: usize = 0;
                while (i < analyzed_arguments_slice.len) : (i += 1) {
                    try self.implicitTypeConversion(analyzed_arguments_slice[i], typeOf(parameters[i]));
                }
                const ordered_named_arguments = call.get(components.OrderedNamedArguments);
                const ordered_named_arguments_slice = ordered_named_arguments.slice();
                while (i < parameters.len) : (i += 1) {
                    try self.implicitTypeConversion(ordered_named_arguments_slice[i - analyzed_arguments_slice.len], typeOf(parameters[i]));
                }
                const return_type = candidate.overload.get(components.ReturnType).entity;
                return try self.codebase.createEntity(.{
                    components.Type.init(return_type),
                    components.Callable.init(candidate.overload),
                    components.AstKind.call,
                    analyzed_arguments,
                    analyzed_named_arguments,
                    call.get(components.Span),
                    ordered_named_arguments,
                });
            }
            assert(kind == .struct_);
            const fields = candidate.overload.get(components.Fields).slice();
            var i: usize = 0;
            while (i < analyzed_arguments_slice.len) : (i += 1) {
                try self.implicitTypeConversion(analyzed_arguments_slice[i], typeOf(fields[i]));
            }
            const ordered_named_arguments = call.get(components.OrderedNamedArguments);
            const ordered_named_arguments_slice = ordered_named_arguments.slice();
            while (i < fields.len) : (i += 1) {
                try self.implicitTypeConversion(ordered_named_arguments_slice[i - analyzed_arguments_slice.len], typeOf(fields[i]));
            }
            return try self.codebase.createEntity(.{
                components.Type.init(candidate.overload),
                components.AstKind.construct,
                analyzed_arguments,
                analyzed_named_arguments,
                call.get(components.Span),
                ordered_named_arguments,
            });
        }

        fn uniformFunctionCall(self: *Self, lhs: Entity, rhs: Entity) !Entity {
            const span = components.Span.init(
                lhs.get(components.Span).begin,
                rhs.get(components.Span).end,
            );
            switch (rhs.get(components.AstKind)) {
                .call => {
                    const call = try self.codebase.createEntity(.{
                        components.AstKind.call,
                        rhs.get(components.Callable),
                        span,
                        rhs.get(components.NamedArguments),
                    });
                    try self.uniformFunctionCallArguments(call, lhs, rhs);
                    return try self.analyzeCall(call, self);
                },
                .symbol => {
                    const call_arguments = try components.Arguments.fromSlice(self.allocator, &.{lhs});
                    const named_arguments = components.NamedArguments.init(self.allocator, self.codebase.getPtr(Strings));
                    const call = try self.codebase.createEntity(.{
                        components.AstKind.call,
                        components.Callable.init(rhs),
                        call_arguments,
                        named_arguments,
                        span,
                    });
                    return try self.analyzeCall(call, self);
                },
                else => |k| panic("\nanalyze dot invalid rhs kind {}\n", .{k}),
            }
        }

        fn analyzeDot(self: *Self, entity: Entity) !Entity {
            const dot_arguments = entity.get(components.Arguments).slice();
            const lhs = try self.analyzeExpression(dot_arguments[0]);
            const rhs = dot_arguments[1];
            const lhs_type = typeOf(lhs);
            if (lhs.get(components.AstKind) == .local) {
                if (lhs_type.has(components.AstKind)) |lhs_type_kind| {
                    assert(lhs_type_kind == .struct_);
                    switch (rhs.get(components.AstKind)) {
                        .symbol => {
                            const rhs_literal = rhs.get(components.Literal);
                            for (lhs_type.get(components.Fields).slice()) |field| {
                                if (!eql(field.get(components.Literal), rhs_literal)) continue;
                                return try self.codebase.createEntity(.{
                                    components.AstKind.field,
                                    components.Type.init(typeOf(field)),
                                    components.Local.init(lhs),
                                    components.Field.init(field),
                                });
                            }
                        },
                        .call => return try self.uniformFunctionCall(lhs, rhs),
                        else => |k| panic("\nanalyzed ot invalid rhs kind {}\n", .{k}),
                    }
                } else return try self.uniformFunctionCall(lhs, rhs);
            }
            return try self.uniformFunctionCall(lhs, rhs);
        }

        fn uniformFunctionCallArguments(self: Self, analyzed_call: Entity, lhs: Entity, call: Entity) !void {
            const arguments = call.get(components.Arguments).slice();
            var underscore_index: ?u64 = null;
            for (arguments) |argument, i| {
                if (argument.get(components.AstKind) == .underscore) {
                    assert(underscore_index == null);
                    underscore_index = i;
                }
            }
            if (underscore_index == null) {
                var call_arguments = try components.Arguments.withCapacity(self.allocator, arguments.len + 1);
                call_arguments.appendAssumeCapacity(lhs);
                for (arguments) |argument| {
                    call_arguments.appendAssumeCapacity(argument);
                }
                _ = try analyzed_call.set(.{call_arguments});
                return;
            }
            const call_arguments = try components.Arguments.fromSlice(self.allocator, arguments);
            call_arguments.mutSlice()[underscore_index.?] = lhs;
            _ = try analyzed_call.set(.{call_arguments});
        }

        fn analyzePointerArithmetic(self: *Self, lhs: Entity, rhs: Entity, intrinsic: components.Intrinsic) !Entity {
            const rhs_type = typeOf(rhs);
            const b = self.builtins;
            if (eql(rhs_type, b.IntLiteral) or eql(rhs_type, b.I32)) {
                try self.implicitTypeConversion(rhs, b.I32);
                const new_intrinsic: components.Intrinsic = switch (intrinsic) {
                    .add => .add_ptr_i32,
                    .subtract => .subtract_ptr_i32,
                    else => panic("\nanalyze pointer arithmetic unsupported intrinsic {}\n", .{intrinsic}),
                };
                return try self.codebase.createEntity(.{
                    components.AstKind.intrinsic,
                    new_intrinsic,
                    try components.Arguments.fromSlice(self.allocator, &.{ lhs, rhs }),
                    lhs.get(components.Type),
                });
            }
            assert(eql(valueType(typeOf(lhs)), valueType(rhs_type)));
            switch (intrinsic) {
                .equal, .not_equal, .greater_equal, .greater_than, .less_equal, .less_than => {
                    return try self.codebase.createEntity(.{
                        components.AstKind.intrinsic,
                        intrinsic,
                        try components.Arguments.fromSlice(self.allocator, &.{ lhs, rhs }),
                        components.Type.init(b.I32),
                    });
                },
                .subtract => {
                    return try self.codebase.createEntity(.{
                        components.AstKind.intrinsic,
                        components.Intrinsic.subtract_ptr_ptr,
                        try components.Arguments.fromSlice(self.allocator, &.{ lhs, rhs }),
                        components.Type.init(b.I32),
                    });
                },
                else => panic("\nanalyze pointer arithmetic unsupported intrinsic {}\n", .{intrinsic}),
            }
        }

        fn analyzeIntrinsic(self: *Self, entity: Entity, intrinsic: components.Intrinsic, result_is_i32: bool) !Entity {
            const arguments = entity.get(components.Arguments).slice();
            const lhs = try self.analyzeExpression(arguments[0]);
            const rhs = try self.analyzeExpression(arguments[1]);
            const lhs_type = typeOf(lhs);
            const b = self.builtins;
            if (lhs_type.has(components.ParentType)) |parent_type| {
                assert(eql(parent_type.entity, b.Ptr));
                return try self.analyzePointerArithmetic(lhs, rhs, intrinsic);
            }
            const builtins = &[_]Entity{ b.I64, b.I32, b.I16, b.I8, b.U64, b.U32, b.U16, b.U8, b.F64, b.F32, b.IntLiteral, b.FloatLiteral };
            for (builtins) |builtin| {
                if (!eql(lhs_type, builtin)) continue;
                const result_type = try self.unifyTypes(lhs, rhs);
                const result = try self.codebase.createEntity(.{
                    components.AstKind.intrinsic,
                    try components.Arguments.fromSlice(self.allocator, &.{ lhs, rhs }),
                    intrinsic,
                });
                if (result_is_i32) {
                    _ = try result.set(.{components.Type.init(b.I32)});
                    if (eql(result_type, b.IntLiteral) or eql(result_type, b.FloatLiteral)) {
                        try addDependentEntities(lhs, &.{rhs});
                        try addDependentEntities(rhs, &.{lhs});
                    }
                } else {
                    _ = try result.set(.{components.Type.init(result_type)});
                    if (eql(result_type, b.IntLiteral) or eql(result_type, b.FloatLiteral)) {
                        try addDependentEntities(result, &.{ lhs, rhs });
                    }
                }
                return result;
            }
            const vectors = &[_]Entity{ b.I64X2, b.I32X4, b.I16X8, b.I8X16, b.U64X2, b.U32X4, b.U16X8, b.U8X16 };
            for (vectors) |vector| {
                if (!eql(lhs_type, vector)) continue;
                assert(intrinsic != .divide);
                const result_type = try self.unifyTypes(lhs, rhs);
                const type_of = components.Type.init(result_type);
                return try self.codebase.createEntity(.{
                    components.AstKind.intrinsic,
                    intrinsic,
                    try components.Arguments.fromSlice(self.allocator, &.{ lhs, rhs }),
                    type_of,
                });
            }
            const float_vectors = &[_]Entity{ b.F64X2, b.F32X4 };
            for (float_vectors) |vector| {
                if (!eql(lhs_type, vector)) continue;
                const result_type = try self.unifyTypes(lhs, rhs);
                const type_of = components.Type.init(result_type);
                return try self.codebase.createEntity(.{
                    components.AstKind.intrinsic,
                    intrinsic,
                    try components.Arguments.fromSlice(self.allocator, &.{ lhs, rhs }),
                    type_of,
                });
            }
            panic("\noperator overloading not yet implemented\n", .{});
        }

        fn analyzeBinaryOp(self: *Self, entity: Entity) !Entity {
            const binary_op = entity.get(components.BinaryOp);
            return try switch (binary_op) {
                .dot => self.analyzeDot(entity),
                .add => self.analyzeIntrinsic(entity, .add, false),
                .subtract => self.analyzeIntrinsic(entity, .subtract, false),
                .multiply => self.analyzeIntrinsic(entity, .multiply, false),
                .divide => self.analyzeIntrinsic(entity, .divide, false),
                .remainder => self.analyzeIntrinsic(entity, .remainder, false),
                .bit_and => self.analyzeIntrinsic(entity, .bit_and, false),
                .bit_or => self.analyzeIntrinsic(entity, .bit_or, false),
                .bit_xor => self.analyzeIntrinsic(entity, .bit_xor, false),
                .left_shift => self.analyzeIntrinsic(entity, .left_shift, false),
                .right_shift => self.analyzeIntrinsic(entity, .right_shift, false),
                .equal => self.analyzeIntrinsic(entity, .equal, true),
                .not_equal => self.analyzeIntrinsic(entity, .not_equal, true),
                .less_than => self.analyzeIntrinsic(entity, .less_than, true),
                .less_equal => self.analyzeIntrinsic(entity, .less_equal, true),
                .greater_than => self.analyzeIntrinsic(entity, .greater_than, true),
                .greater_equal => self.analyzeIntrinsic(entity, .greater_equal, true),
            };
        }

        fn analyzeDefine(self: *Self, define: Entity) !Entity {
            const name = define.get(components.Name);
            const value = try self.analyzeExpression(define.get(components.Value).entity);
            const kind = name.entity.get(components.AstKind);
            switch (kind) {
                .symbol => {
                    const scopes = self.function.getPtr(components.Scopes);
                    if (scopes.hasName(name)) |local| {
                        assert(!define.contains(components.TypeAst));
                        _ = try local.set(.{components.Mutable{ .value = true }});
                        const type_of = try self.unifyTypes(value, local);
                        const b = self.builtins;
                        const assign = try self.codebase.createEntity(.{
                            components.AstKind.assign,
                            components.Value.init(value),
                            components.Local.init(local),
                            components.Type.init(b.Void),
                        });
                        if (eql(type_of, b.IntLiteral) or eql(type_of, b.FloatLiteral)) {
                            try addDependentEntities(local, &.{value});
                        }
                        return assign;
                    }
                    if (define.has(components.TypeAst)) |type_ast| {
                        const explicit_type = try analyzeExpression(self, type_ast.entity);
                        try self.implicitTypeConversion(value, explicit_type);
                    }
                    const b = self.builtins;
                    const type_of = typeOf(value);
                    const local = try self.codebase.createEntity(.{
                        components.AstKind.local,
                        name,
                        components.Type.init(type_of),
                        components.Value.init(value),
                        define.get(components.Span),
                    });
                    const analyzed_define = try self.codebase.createEntity(.{
                        components.AstKind.define,
                        components.Local.init(local),
                        components.Type.init(b.Void),
                        components.Value.init(value),
                    });
                    if (eql(type_of, b.IntLiteral)) {
                        try addDependentEntities(local, &.{value});
                        try self.function.getPtr(components.IntLiterals).append(local);
                    }
                    if (eql(type_of, b.FloatLiteral)) {
                        try addDependentEntities(local, &.{value});
                    }
                    try scopes.putName(name, local);
                    return analyzed_define;
                },
                .pointer => {
                    const pointer = try self.analyzeExpression(name.entity.get(components.Value).entity);
                    const pointer_type = typeOf(pointer);
                    const b = self.builtins;
                    assert(eql(parentType(pointer_type), b.Ptr));
                    const value_type = valueType(pointer_type);
                    try self.implicitTypeConversion(value, value_type);
                    const scalars = [_]Entity{ b.I64, b.I32, b.U64, b.U32, b.F64, b.F32 };
                    for (scalars) |scalar| {
                        if (eql(value_type, scalar)) {
                            return try self.codebase.createEntity(.{
                                components.AstKind.intrinsic,
                                components.Intrinsic.store,
                                try components.Arguments.fromSlice(self.allocator, &.{ pointer, value }),
                                components.Type.init(b.Void),
                            });
                        }
                    }
                    const vectors = [_]Entity{ b.I64X2, b.I32X4, b.I16X8, b.I8X16 };
                    for (vectors) |vector| {
                        if (eql(value_type, vector)) {
                            return try self.codebase.createEntity(.{
                                components.AstKind.intrinsic,
                                components.Intrinsic.v128_store,
                                try components.Arguments.fromSlice(self.allocator, &.{ pointer, value }),
                                components.Type.init(b.Void),
                            });
                        }
                    }
                    if (value_type.has(components.ParentType)) |value_type_parent_type| {
                        assert(eql(value_type_parent_type.entity, b.Ptr));
                        return try self.codebase.createEntity(.{
                            components.AstKind.intrinsic,
                            components.Intrinsic.store,
                            try components.Arguments.fromSlice(self.allocator, &.{ pointer, value }),
                            components.Type.init(b.Void),
                        });
                    }
                    panic("\nunsupported store for value type {s}\n", .{literalOf(value_type)});
                },
                .binary_op => {
                    const arguments = name.entity.get(components.Arguments).slice();
                    const lhs = try self.analyzeExpression(arguments[0]);
                    const type_of = typeOf(lhs);
                    assert(type_of.get(components.AstKind) == .struct_);
                    const fields = type_of.get(components.Fields).slice();
                    const rhs = arguments[1];
                    assert(rhs.get(components.AstKind) == .symbol);
                    const literal = rhs.get(components.Literal);
                    for (fields) |field| {
                        if (!eql(field.get(components.Literal), literal)) continue;
                        try self.implicitTypeConversion(value, typeOf(field));
                        return try self.codebase.createEntity(.{
                            components.AstKind.assign_field,
                            components.Type.init(self.builtins.Void),
                            components.Local.init(lhs),
                            components.Field.init(field),
                            components.Value.init(value),
                        });
                    }
                    panic("\nassigning to invalid field {s}\n", .{literalOf(rhs)});
                },
                else => panic("\nassigning to unsupported kind {}\n", .{kind}),
            }
        }

        fn analyzePlusEqual(self: *Self, plus_equal: Entity) !Entity {
            const arguments = plus_equal.get(components.Arguments).slice();
            const left = arguments[0];
            const right = arguments[1];
            assert(left.get(components.AstKind) == .symbol);
            const span = plus_equal.get(components.Span);
            const binary_op_arguments = try components.Arguments.fromSlice(self.codebase.arena.allocator(), &.{ left, right });
            const binary_op = try self.codebase.createEntity(.{
                components.AstKind.binary_op,
                components.BinaryOp.add,
                span,
                binary_op_arguments,
            });
            const define = try self.codebase.createEntity(.{
                components.AstKind.define,
                components.Name.init(arguments[0]),
                components.Value.init(binary_op),
                span,
            });
            return self.analyzeDefine(define);
        }

        fn analyzeTimesEqual(self: *Self, times_equal: Entity) !Entity {
            const arguments = times_equal.get(components.Arguments).slice();
            const left = arguments[0];
            const right = arguments[1];
            assert(left.get(components.AstKind) == .symbol);
            const span = times_equal.get(components.Span);
            const binary_op_arguments = try components.Arguments.fromSlice(self.codebase.arena.allocator(), &.{ left, right });
            const binary_op = try self.codebase.createEntity(.{
                components.AstKind.binary_op,
                components.BinaryOp.multiply,
                span,
                binary_op_arguments,
            });
            const define = try self.codebase.createEntity(.{
                components.AstKind.define,
                components.Name.init(arguments[0]),
                components.Value.init(binary_op),
                span,
            });
            return self.analyzeDefine(define);
        }

        fn analyzeIf(self: *Self, if_: Entity) !Entity {
            const scopes = self.function.getPtr(components.Scopes);
            const conditional = try self.analyzeExpression(if_.get(components.Conditional).entity);
            try self.implicitTypeConversion(conditional, self.builtins.I32);
            const active_scopes = self.active_scopes;
            const then = if_.get(components.Then).slice();
            assert(then.len > 0);
            const then_scopes = try self.allocator.alloc(u64, active_scopes.len + 1);
            std.mem.copy(u64, then_scopes, active_scopes);
            then_scopes[active_scopes.len] = try scopes.pushScope();
            self.active_scopes = then_scopes;
            var analyzed_then = try components.Then.withCapacity(self.allocator, then.len);
            for (then) |entity| {
                analyzed_then.appendAssumeCapacity(try self.analyzeExpression(entity));
            }
            const then_entity = analyzed_then.last();
            const else_ = if_.get(components.Else).slice();
            assert(else_.len > 0);
            const else_scopes = try self.allocator.alloc(u64, active_scopes.len + 1);
            std.mem.copy(u64, else_scopes, active_scopes);
            else_scopes[active_scopes.len] = try scopes.pushScope();
            self.active_scopes = else_scopes;
            var analyzed_else = try components.Else.withCapacity(self.allocator, else_.len);
            for (else_) |entity| {
                analyzed_else.appendAssumeCapacity(try self.analyzeExpression(entity));
            }
            const else_entity = analyzed_else.last();
            const type_of = try self.unifyTypes(then_entity, else_entity);
            const result = try self.codebase.createEntity(.{
                components.AstKind.if_,
                components.Type.init(type_of),
                components.Conditional.init(conditional),
                analyzed_then,
                analyzed_else,
            });
            if (eql(type_of, self.builtins.IntLiteral) or eql(type_of, self.builtins.FloatLiteral)) {
                try addDependentEntities(result, &.{ then_entity, else_entity });
            }
            const finally_scopes = try self.allocator.alloc(u64, active_scopes.len + 1);
            std.mem.copy(u64, finally_scopes, active_scopes);
            finally_scopes[active_scopes.len] = try scopes.pushScope();
            self.active_scopes = finally_scopes;
            return result;
        }

        fn analyzeWhile(self: *Self, while_: Entity) !Entity {
            const scopes = self.function.getPtr(components.Scopes);
            const conditional = try self.analyzeExpression(while_.get(components.Conditional).entity);
            try self.implicitTypeConversion(conditional, self.builtins.I32);
            const active_scopes = self.active_scopes;
            const body = while_.get(components.Body).slice();
            assert(body.len > 0);
            const body_scopes = try self.allocator.alloc(u64, active_scopes.len + 1);
            std.mem.copy(u64, body_scopes, active_scopes);
            body_scopes[active_scopes.len] = try scopes.pushScope();
            self.active_scopes = body_scopes;
            var analyzed_body = try components.Body.withCapacity(self.allocator, body.len);
            for (body) |entity| {
                analyzed_body.appendAssumeCapacity(try self.analyzeExpression(entity));
            }
            const result = try self.codebase.createEntity(.{
                components.AstKind.while_,
                components.Type.init(self.builtins.Void),
                components.Conditional.init(conditional),
                analyzed_body,
            });
            const finally_scopes = try self.allocator.alloc(u64, active_scopes.len + 1);
            std.mem.copy(u64, finally_scopes, active_scopes);
            finally_scopes[active_scopes.len] = try scopes.pushScope();
            self.active_scopes = finally_scopes;
            return result;
        }

        fn analyzeFor(self: *Self, for_: Entity) !Entity {
            const scopes = self.function.getPtr(components.Scopes);
            const iterator = try self.analyzeExpression(for_.get(components.Iterator).entity);
            const loop_variable = blk: {
                if (for_.has(components.LoopVariable)) |loop_variable| {
                    break :blk loop_variable.entity;
                } else {
                    const interned = try self.codebase.getPtr(Strings).intern("it");
                    break :blk try self.codebase.createEntity(.{
                        components.TokenKind.symbol,
                        components.Literal.init(interned),
                    });
                }
            };
            const name = components.Name.init(loop_variable);
            const first = iterator.get(components.First).entity;
            const last = iterator.get(components.Last).entity;
            const type_of = typeOf(first);
            const local = try self.codebase.createEntity(.{
                components.AstKind.local,
                name,
                components.Type.init(type_of),
            });
            if (eql(type_of, self.builtins.IntLiteral)) {
                try addDependentEntities(local, &.{ first, last });
            }
            const define = try self.codebase.createEntity(.{
                components.AstKind.define,
                components.Local.init(local),
                components.Type.init(self.builtins.Void),
                components.Value.init(first),
            });
            try scopes.putName(name, local);
            const active_scopes = self.active_scopes;
            const body = for_.get(components.Body).slice();
            assert(body.len > 0);
            const body_scopes = try self.allocator.alloc(u64, active_scopes.len + 1);
            std.mem.copy(u64, body_scopes, active_scopes);
            body_scopes[active_scopes.len] = try scopes.pushScope();
            self.active_scopes = body_scopes;
            var analyzed_body = try components.Body.withCapacity(self.allocator, body.len);
            for (body) |entity| {
                analyzed_body.appendAssumeCapacity(try self.analyzeExpression(entity));
            }
            const result = try self.codebase.createEntity(.{
                components.AstKind.for_,
                components.Type.init(self.builtins.Void),
                components.LoopVariable.init(define),
                components.Iterator.init(iterator),
                analyzed_body,
            });
            const finally_scopes = try self.allocator.alloc(u64, active_scopes.len + 1);
            std.mem.copy(u64, finally_scopes, active_scopes);
            finally_scopes[active_scopes.len] = try scopes.pushScope();
            self.active_scopes = finally_scopes;
            if (eql(typeOf(local), self.builtins.IntLiteral)) {
                try self.function.getPtr(components.IntLiterals).append(local);
            }
            return result;
        }

        fn analyzeRange(self: *Self, entity: Entity) !Entity {
            const b = self.builtins;
            const first = blk: {
                if (entity.has(components.First)) |first| {
                    break :blk try self.analyzeExpression(first.entity);
                } else {
                    const interned = try self.codebase.getPtr(Strings).intern("0");
                    break :blk try self.codebase.createEntity(.{
                        components.AstKind.int,
                        components.Literal.init(interned),
                        components.Type.init(b.IntLiteral),
                    });
                }
            };
            const last = try self.analyzeExpression(entity.get(components.Last).entity);
            const type_of = try self.unifyTypes(first, last);
            const range_type = blk: {
                const memoized = b.Range.getPtr(components.Memoized);
                const result = try memoized.getOrPut(type_of);
                if (result.found_existing) {
                    break :blk result.value_ptr.*;
                }
                const string = try std.fmt.allocPrint(self.allocator, "Range({s})", .{literalOf(type_of)});
                const interned = try self.codebase.getPtr(Strings).intern(string);
                break :blk try self.codebase.createEntity(.{
                    components.Literal.init(interned),
                    components.Type.init(b.Type),
                    components.ParentType.init(b.Range),
                    components.ValueType.init(type_of),
                });
            };
            return try self.codebase.createEntity(.{
                components.Type.init(range_type),
                components.AstKind.range,
                entity.get(components.Span),
                components.First.init(first),
                components.Last.init(last),
            });
        }

        fn analyzeString(self: *Self, entity: Entity) !Entity {
            const b = self.builtins;
            const array_type = try self.arrayType(b.U8);
            return entity.set(.{components.Type.init(array_type)});
        }

        fn analyzeArrayLiteral(self: *Self, entity: Entity) !Entity {
            const values = entity.get(components.Values).slice();
            assert(values.len > 1);
            var analyzed_values = try components.Values.withCapacity(self.allocator, values.len);
            const first = try self.analyzeExpression(values[0]);
            try analyzed_values.append(first);
            for (values[1..]) |value| {
                const analyzed_value = try self.analyzeExpression(value);
                try analyzed_values.append(analyzed_value);
            }
            const array_type = try self.arrayType(typeOf(first));
            return try self.codebase.createEntity(.{
                components.AstKind.array_literal,
                components.Type.init(array_type),
                analyzed_values,
            });
        }

        fn analyzeChar(self: *Self, entity: Entity) !Entity {
            const char = literalOf(entity)[0];
            const string = try std.fmt.allocPrint(self.allocator, "{}", .{char});
            const interned = try self.codebase.getPtr(Strings).intern(string);
            return try self.codebase.createEntity(.{
                components.Type.init(self.builtins.U8),
                components.Literal.init(interned),
                components.AstKind.int,
                entity.get(components.Span),
            });
        }

        fn analyzeIndex(self: *Self, entity: Entity) !Entity {
            const arguments = entity.get(components.Arguments).slice();
            const array = try self.analyzeExpression(arguments[0]);
            const array_type = typeOf(array);
            const parent_type = parentType(array_type);
            const value_type = valueType(array_type);
            assert(eql(parent_type, self.builtins.Array));
            const index = try self.analyzeExpression(arguments[1]);
            try self.implicitTypeConversion(index, self.builtins.I32);
            return try self.codebase.createEntity(.{
                components.AstKind.index,
                try components.Arguments.fromSlice(self.allocator, &.{ array, index }),
                entity.get(components.Span),
                components.Type.init(value_type),
            });
        }

        const Error = error{ Overflow, InvalidCharacter, OutOfMemory, CantOpenFile, CannotUnifyTypes, CompileError };

        fn analyzeExpression(self: *Self, entity: Entity) Error!Entity {
            if (entity.contains(components.AnalyzedExpression)) return entity;
            const kind = entity.get(components.AstKind);
            const analyzed_entity = switch (kind) {
                .symbol => try self.analyzeSymbol(entity),
                .int, .float => entity,
                .call => try self.analyzeCall(entity, self),
                .binary_op => try self.analyzeBinaryOp(entity),
                .define => try self.analyzeDefine(entity),
                .if_ => try self.analyzeIf(entity),
                .while_ => try self.analyzeWhile(entity),
                .for_ => try self.analyzeFor(entity),
                .pointer => try self.analyzePointer(entity),
                .array => try self.analyzeArray(entity),
                .range => try self.analyzeRange(entity),
                .string => try self.analyzeString(entity),
                .array_literal => try self.analyzeArrayLiteral(entity),
                .char => try self.analyzeChar(entity),
                .plus_equal => try self.analyzePlusEqual(entity),
                .times_equal => try self.analyzeTimesEqual(entity),
                .index => try self.analyzeIndex(entity),
                else => panic("\nanalyzeExpression unsupported kind {}\n", .{kind}),
            };
            _ = try analyzed_entity.set(.{components.AnalyzedExpression{ .value = true }});
            return analyzed_entity;
        }

        fn analyzeFunctionParameters(self: *Self) !void {
            const scopes = self.function.getPtr(components.Scopes);
            const parameters = self.function.get(components.Parameters).slice();
            for (parameters) |parameter| {
                const parameter_type = try self.analyzeExpression(parameter.get(components.TypeAst).entity);
                _ = try parameter.set(.{
                    components.Type.init(parameter_type),
                    components.Name.init(parameter),
                    components.AstKind.local,
                });
                try scopes.putLiteral(parameter.get(components.Literal), parameter);
            }
            _ = try self.function.set(.{components.AnalyzedParameters{ .value = true }});
        }

        fn analyzeFunctionBody(self: *Self, body: []const Entity) !Entity {
            var analyzed_body = try components.Body.withCapacity(self.allocator, body.len);
            for (body) |expression| {
                try analyzed_body.append(try self.analyzeExpression(expression));
            }
            _ = try self.function.set(.{analyzed_body});
            const sliced = analyzed_body.slice();
            assert(sliced.len > 0);
            return sliced[sliced.len - 1];
        }

        fn analyzeFunction(self: *Self) !void {
            _ = try self.function.set(.{
                components.Module.init(self.module),
                components.IntLiterals.init(self.allocator),
            });
            if (!self.function.contains(components.AnalyzedParameters)) {
                try self.analyzeFunctionParameters();
            }
            const return_type = blk: {
                if (self.function.has(components.ReturnTypeAst)) |return_type_ast| {
                    const analyzed = try self.analyzeExpression(return_type_ast.entity);
                    _ = try self.function.set(.{components.ReturnType.init(analyzed)});
                    break :blk analyzed;
                } else {
                    break :blk null;
                }
            };
            if (self.function.has(components.Body)) |body| {
                _ = try self.codebase.getPtr(components.Functions).append(self.function);
                const return_entity = try self.analyzeFunctionBody(body.slice());
                if (return_type) |entity| {
                    try self.implicitTypeConversion(return_entity, entity);
                }
                for (self.function.get(components.IntLiterals).slice()) |int_literal| {
                    if (eql(typeOf(int_literal), self.builtins.IntLiteral)) {
                        try self.implicitTypeConversion(int_literal, self.builtins.I32);
                    }
                }
                if (return_type == null) {
                    const return_entity_type = typeOf(return_entity);
                    if (eql(return_entity_type, self.builtins.IntLiteral)) {
                        try self.implicitTypeConversion(return_entity, self.builtins.I32);
                        _ = try self.function.set(.{components.ReturnType.init(self.builtins.I32)});
                    } else if (eql(return_entity_type, self.builtins.FloatLiteral)) {
                        try self.implicitTypeConversion(return_entity, self.builtins.F32);
                        _ = try self.function.set(.{components.ReturnType.init(self.builtins.F32)});
                    } else {
                        _ = try self.function.set(.{components.ReturnType.init(return_entity_type)});
                    }
                }
            } else {
                _ = try self.codebase.getPtr(components.ForeignImports).append(self.function);
            }
        }
    };
}

fn addDependentEntities(entity: Entity, entities: []const Entity) !void {
    if (entity.contains(components.DependentEntities)) {
        const dependent_entities = entity.getPtr(components.DependentEntities);
        for (entities) |e| {
            try dependent_entities.append(e);
        }
    } else {
        _ = try entity.set(.{
            try components.DependentEntities.fromSlice(entity.ecs.arena.allocator(), entities),
        });
    }
}

fn analyzeOverload(file_system: anytype, module: Entity, overload: Entity) !void {
    if (overload.contains(components.AnalyzedBody)) return;
    _ = try overload.set(.{components.AnalyzedBody{ .value = true }});
    const codebase = overload.ecs;
    const allocator = codebase.arena.allocator();
    var scopes = components.Scopes.init(allocator, codebase.getPtr(Strings));
    const scope = try scopes.pushScope();
    _ = try overload.set(.{scopes});
    const active_scopes = [_]u64{scope};
    var context = Context(@TypeOf(file_system)){
        .allocator = allocator,
        .codebase = codebase,
        .file_system = file_system,
        .module = module,
        .function = overload,
        .active_scopes = &active_scopes,
        .builtins = codebase.getPtr(components.Builtins),
    };
    try context.analyzeFunction();
}

pub fn analyzeSemantics(codebase: *ECS, file_system: anytype, module_name: []const u8) !Entity {
    const allocator = codebase.arena.allocator();
    _ = try codebase.set(.{components.Functions.init(allocator)});
    _ = try codebase.set(.{components.ForeignImports.init(allocator)});
    const contents = try file_system.read(module_name);
    const interned = try codebase.getPtr(Strings).intern(module_name[0 .. module_name.len - 5]);
    const source = components.ModuleSource{ .string = contents };
    const path = components.ModulePath{ .string = module_name };
    const module = try codebase.createEntity(.{
        source,
        path,
        components.Literal.init(interned),
    });
    var tokens = try tokenize(module, contents);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const foreign_exports = module.get(components.ForeignExports).slice();
    if (foreign_exports.len > 0) {
        for (foreign_exports) |foreign_export| {
            const literal = foreign_export.get(components.Literal);
            const overloads = top_level.findLiteral(literal).get(components.Overloads).slice();
            assert(overloads.len == 1);
            try analyzeOverload(file_system, module, overloads[0]);
        }
    } else {
        const overloads = top_level.findString("start").get(components.Overloads).slice();
        assert(overloads.len == 1);
        try analyzeOverload(file_system, module, overloads[0]);
    }
    return module;
}
