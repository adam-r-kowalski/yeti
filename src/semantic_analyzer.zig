const std = @import("std");
const eql = std.meta.eql;
const Allocator = std.mem.Allocator;
const Arena = std.heap.ArenaAllocator;
const assert = std.debug.assert;
const panic = std.debug.panic;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectEqualSlices = std.testing.expectEqualSlices;

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
const test_utils = @import("test_utils.zig");
const literalOf = test_utils.literalOf;
const typeOf = test_utils.typeOf;
const parentType = test_utils.parentType;
const valueType = test_utils.valueType;
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
                return .no;
            }
            if (eql(from, b.FloatLiteral)) {
                for (float_builtins) |builtin| {
                    if (eql(to, builtin)) return .implicit_conversion;
                }
                return .no;
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
                const b = self.builtins;
                if (local.has(components.Value)) |value| {
                    const type_of = value.entity.get(components.Type);
                    const result = try self.codebase.createEntity(.{
                        components.AstKind.local,
                        components.Local.init(local),
                        type_of,
                    });
                    const T = type_of.entity;
                    if (eql(T, b.IntLiteral) or eql(T, b.FloatLiteral)) {
                        _ = try result.set(.{
                            try components.DependentEntities.fromSlice(self.allocator, &.{value.entity}),
                        });
                    }
                    return result;
                }
                const type_of = local.get(components.Type);
                const result = try self.codebase.createEntity(.{
                    components.AstKind.local,
                    components.Local.init(local),
                    type_of,
                });
                const T = type_of.entity;
                if (eql(T, b.IntLiteral) or eql(T, b.FloatLiteral)) {
                    _ = try result.set(.{
                        try components.DependentEntities.fromSlice(self.allocator, &.{local}),
                    });
                }
                return result;
            }
            const global_scope = self.codebase.get(components.Scope);
            if (global_scope.hasLiteral(literal)) |global| {
                return global;
            }
            const top_level_scope = self.module.get(components.TopLevel);
            if (top_level_scope.hasLiteral(literal)) |top_level| {
                const kind = top_level.get(components.AstKind);
                switch (kind) {
                    .import => {
                        if (top_level.has(components.Module)) |module| {
                            return module.entity;
                        }
                        const module_name = literalOf(top_level.get(components.Path).entity);
                        const contents = try self.file_system.read(module_name);
                        const module = try self.codebase.createEntity(.{});
                        var tokens = try tokenize(module, contents);
                        try parse(module, &tokens);
                        const interned = try self.codebase.getPtr(Strings).intern(module_name[0 .. module_name.len - 5]);
                        _ = try module.set(.{components.Literal.init(interned)});
                        _ = try top_level.set(.{components.Module.init(module)});
                        return module;
                    },
                    .overload_set => {
                        const overloads = top_level.get(components.Overloads).slice();
                        assert(overloads.len == 1);
                        const overload = overloads[0];
                        assert(overload.get(components.AstKind) == .struct_);
                        return overload;
                    },
                    else => panic("\nanalyzeSumbol unspported top level kind {}\n", .{kind}),
                }
            }
            panic("\nanalyzeSymbol failed for symbol {s}\n", .{literalOf(entity)});
        }

        fn bestOverload(self: *Self, call: Entity, callable: Entity, arguments: []const Entity) !Entity {
            const top_level = self.module.get(components.TopLevel);
            const literal = callable.get(components.Literal);
            var best_overload: Entity = undefined;
            var best_match = Match.no;
            const overloads = top_level.findLiteral(literal).get(components.Overloads).slice();
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
                    var match = Match.exact;
                    for (fields) |field, i| {
                        const field_type = typeOf(field);
                        const argument_type = typeOf(arguments[i]);
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
                    if (@enumToInt(match) < @enumToInt(best_match)) continue;
                    if (match != .no and match == best_match) {
                        panic("ambiguous overload set overload match {} best match {}", .{ match, best_match });
                    }
                    best_match = match;
                    best_overload = overload;
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
                if (parameters.len != arguments.len) continue;
                var match = Match.exact;
                for (parameters) |parameter, i| {
                    const parameter_type = typeOf(parameter);
                    const argument_type = typeOf(arguments[i]);
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
                if (@enumToInt(match) < @enumToInt(best_match)) continue;
                if (match != .no and match == best_match) {
                    panic("ambiguous overload set overload match {} best match {}", .{ match, best_match });
                }
                best_match = match;
                best_overload = overload;
            }
            if (best_match == .no) {
                var body = List(u8, .{ .initial_capacity = 1000 }).init(self.allocator);
                try body.appendSlice("No matching function overload found for argument types (");
                for (arguments) |argument, i| {
                    const argument_type = typeOf(argument);
                    try body.appendSlice(literalOf(argument_type));
                    if (i < arguments.len - 1) {
                        try body.appendSlice(", ");
                    }
                }
                try body.append(')');
                var hint = List(u8, .{ .initial_capacity = 1000 }).init(self.allocator);
                try hint.appendSlice("Here are the possible candidates:\n");
                var candidates = List(List(u8, .{}), .{ .initial_capacity = 8 }).init(self.allocator);
                var file_and_lines = List(List(u8, .{}), .{ .initial_capacity = 8 }).init(self.allocator);
                var candidate_width: usize = 0;
                for (overloads) |overload| {
                    var candidate = List(u8, .{}).init(self.allocator);
                    try candidate.append('\n');
                    try candidate.appendSlice(literalOf(overload.get(components.Name).entity));
                    try candidate.appendSlice(" = fn(");
                    const parameters = overload.get(components.Parameters).slice();
                    for (parameters) |parameter, i| {
                        const parameter_type = typeOf(parameter);
                        var mismatch = false;
                        if (i < arguments.len) {
                            mismatch = self.convertibleTo(parameter_type, typeOf(arguments[i])) == .no;
                        } else {
                            mismatch = true;
                        }
                        if (mismatch) {
                            try candidate.appendSlice(colors.RED);
                        }
                        try candidate.appendSlice(literalOf(parameter));
                        try candidate.appendSlice(": ");
                        try candidate.appendSlice(literalOf(parameter_type));
                        if (mismatch) {
                            try candidate.appendSlice(colors.RESET);
                        }
                        if (i < parameters.len - 1) {
                            try candidate.appendSlice(", ");
                        }
                    }
                    try candidate.append(')');
                    try candidates.append(candidate);
                    candidate_width = std.math.max(candidate_width, candidate.len);
                    var file_and_line = List(u8, .{}).init(self.allocator);
                    try file_and_line.appendSlice(self.module.get(components.ModulePath).string);
                    try file_and_line.append(':');
                    const result = try std.fmt.allocPrint(self.allocator, "{}", .{overload.get(components.Span).begin.row + 1});
                    try file_and_line.appendSlice(result);
                    try file_and_lines.append(file_and_line);
                }
                const file_and_lines_slice = file_and_lines.slice();
                for (candidates.slice()) |candidate, i| {
                    const candidate_slice = candidate.slice();
                    try hint.appendSlice(candidate_slice);
                    const delta = candidate_width - candidate_slice.len;
                    var spaces: usize = 0;
                    while (spaces < delta) : (spaces += 1) {
                        try hint.append(' ');
                    }
                    try hint.appendSlice(" ----- ");
                    try hint.appendSlice(file_and_lines_slice[i].slice());
                }
                const error_component = components.Error{
                    .header = "FUNCTION CALL ERROR",
                    .body = body.mutSlice(),
                    .span = call.get(components.Span),
                    .hint = hint.mutSlice(),
                    .module = self.module,
                };
                _ = try call.set(.{error_component});
                return error.CompileError;
            }
            return best_overload;
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
            const scalars = [_]Entity{ b.I64, b.I32, b.U64, b.U32, b.F64, b.F32 };
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
                analyzed_arguments.appendAssumeCapacity(try callingContext.analyzeExpression(argument));
            }
            const callable_literal = callable.get(components.Literal);
            if (eql(callable_literal, self.builtins.Cast.get(components.Literal))) {
                return try self.analyzeCast(analyzed_arguments.slice());
            }
            const overload = try self.bestOverload(call, callable, analyzed_arguments.slice());
            const kind = overload.get(components.AstKind);
            if (kind == .function) {
                if (!overload.contains(components.AnalyzedBody)) {
                    _ = try overload.set(.{components.AnalyzedBody{ .value = true }});
                    const scopes = overload.getPtr(components.Scopes).slice();
                    assert(scopes.len == 1);
                    const active_scopes = [_]u64{0};
                    var context = Self{
                        .allocator = self.allocator,
                        .codebase = self.codebase,
                        .file_system = self.file_system,
                        .module = self.module,
                        .function = overload,
                        .active_scopes = &active_scopes,
                        .builtins = self.builtins,
                    };
                    try context.analyzeFunction();
                }
                const parameters = overload.get(components.Parameters).slice();
                for (analyzed_arguments.slice()) |argument, i| {
                    try self.implicitTypeConversion(argument, typeOf(parameters[i]));
                }
                const return_type = overload.get(components.ReturnType).entity;
                return try self.codebase.createEntity(.{
                    components.Type.init(return_type),
                    components.Callable.init(overload),
                    components.AstKind.call,
                    analyzed_arguments,
                });
            }
            assert(kind == .struct_);
            const fields = overload.get(components.Fields).slice();
            for (analyzed_arguments.slice()) |argument, i| {
                try self.implicitTypeConversion(argument, typeOf(fields[i]));
            }
            return try self.codebase.createEntity(.{
                components.Type.init(overload),
                components.AstKind.construct,
                analyzed_arguments,
            });
        }

        fn analyzeDot(self: *Self, entity: Entity) !Entity {
            const dot_arguments = entity.get(components.Arguments).slice();
            const lhs = try self.analyzeExpression(dot_arguments[0]);
            const b = self.builtins;
            const lhs_type = typeOf(lhs);
            const rhs = dot_arguments[1];
            if (eql(lhs_type, b.Module)) {
                assert(rhs.get(components.AstKind) == .call);
                var context = Self{
                    .allocator = self.allocator,
                    .codebase = self.codebase,
                    .file_system = self.file_system,
                    .module = lhs,
                    .function = self.function,
                    .active_scopes = self.active_scopes,
                    .builtins = self.builtins,
                };
                return try context.analyzeCall(rhs, self);
            }
            assert(lhs.get(components.AstKind) == .local);
            assert(lhs_type.get(components.AstKind) == .struct_);
            assert(rhs.get(components.AstKind) == .symbol);
            const rhs_literal = rhs.get(components.Literal);
            for (lhs_type.get(components.Fields).slice()) |field| {
                if (!eql(field.get(components.Literal), rhs_literal)) continue;
                return try self.codebase.createEntity(.{
                    components.AstKind.field,
                    components.Type.init(typeOf(field)),
                    lhs.get(components.Local),
                    components.Field.init(field),
                });
            }
            panic("\nanalyze dot invalid field {s}\n", .{literalOf(rhs)});
        }

        fn pipelineArguments(self: Self, lhs: Entity, call: Entity) !components.Arguments {
            const arguments = call.get(components.Arguments).slice();
            var underscore: ?u64 = null;
            for (arguments) |argument, i| {
                if (argument.get(components.AstKind) == .underscore) {
                    assert(underscore == null);
                    underscore = i;
                }
            }
            if (underscore == null) {
                var call_arguments = try components.Arguments.withCapacity(self.allocator, arguments.len + 1);
                try call_arguments.append(lhs);
                for (arguments) |argument| {
                    try call_arguments.append(argument);
                }
                return call_arguments;
            }
            const call_arguments = try components.Arguments.fromSlice(self.allocator, arguments);
            call_arguments.mutSlice()[underscore.?] = lhs;
            return call_arguments;
        }

        fn analyzePipeline(self: *Self, entity: Entity) !Entity {
            const arguments = entity.get(components.Arguments).slice();
            const lhs = arguments[0];
            const rhs = arguments[1];
            const span = components.Span.init(
                lhs.get(components.Span).begin,
                rhs.get(components.Span).end,
            );
            switch (rhs.get(components.AstKind)) {
                .call => {
                    const call_arguments = try self.pipelineArguments(lhs, rhs);
                    const call = try self.codebase.createEntity(.{
                        components.AstKind.call,
                        rhs.get(components.Callable),
                        call_arguments,
                        span,
                    });
                    return try self.analyzeCall(call, self);
                },
                .symbol => {
                    const call_arguments = try components.Arguments.fromSlice(self.allocator, &.{lhs});
                    const call = try self.codebase.createEntity(.{
                        components.AstKind.call,
                        components.Callable.init(rhs),
                        call_arguments,
                        span,
                    });
                    return try self.analyzeCall(call, self);
                },
                .binary_op => {
                    assert(rhs.get(components.BinaryOp) == .dot);
                    const dot_arguments = rhs.get(components.Arguments).slice();
                    const call = dot_arguments[1];
                    const new_call = blk: {
                        switch (call.get(components.AstKind)) {
                            .call => {
                                const call_arguments = try self.pipelineArguments(lhs, call);
                                break :blk try self.codebase.createEntity(.{
                                    components.AstKind.call,
                                    call.get(components.Callable),
                                    call_arguments,
                                    span,
                                });
                            },
                            .symbol => {
                                const call_arguments = try components.Arguments.fromSlice(self.allocator, &.{lhs});
                                break :blk try self.codebase.createEntity(.{
                                    components.AstKind.call,
                                    components.Callable.init(call),
                                    call_arguments,
                                    span,
                                });
                            },
                            else => panic("\nshould not have gotten here\n", .{}),
                        }
                    };
                    const new_dot_arguments = try components.Arguments.fromSlice(self.allocator, &.{
                        dot_arguments[0], new_call,
                    });
                    const dot = try self.codebase.createEntity(.{
                        components.AstKind.binary_op,
                        components.BinaryOp.dot,
                        new_dot_arguments,
                        span,
                    });
                    return try self.analyzeDot(dot);
                },
                else => panic("\nshould not have gotten here\n", .{}),
            }
            return entity;
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

        // TODO: comparison binary ops should not implicitly convert arguments to i32
        // for example
        // x = 10
        // y = x < 20
        // type_of(x) != i32 yet, should still be int literal
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
                const type_of = components.Type.init(if (result_is_i32) b.I32 else result_type);
                const result = try self.codebase.createEntity(.{
                    components.AstKind.intrinsic,
                    intrinsic,
                    try components.Arguments.fromSlice(self.allocator, &.{ lhs, rhs }),
                    type_of,
                });
                if (eql(builtin, b.IntLiteral) or eql(builtin, b.FloatLiteral)) {
                    _ = try result.set(.{
                        try components.DependentEntities.fromSlice(self.allocator, &.{ lhs, rhs }),
                    });
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
                .pipeline => self.analyzePipeline(entity),
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
                    if (scopes.hasName(name)) |entity| {
                        assert(!define.contains(components.TypeAst));
                        _ = try entity.set(.{components.Mutable{ .value = true }});
                        const result_type = try self.unifyTypes(value, entity.get(components.Value).entity);
                        const b = self.builtins;
                        const result = try self.codebase.createEntity(.{
                            components.AstKind.assign,
                            components.Value.init(value),
                            name,
                            components.Type.init(b.Void),
                        });
                        if (eql(result_type, b.IntLiteral) or eql(result_type, b.FloatLiteral)) {
                            const dependent_entities = entity.getPtr(components.DependentEntities);
                            try dependent_entities.append(result);
                            try dependent_entities.append(value);
                        }
                        return result;
                    }
                    if (define.has(components.TypeAst)) |type_ast| {
                        const explicit_type = try analyzeExpression(self, type_ast.entity);
                        try self.implicitTypeConversion(value, explicit_type);
                    }
                    const b = self.builtins;
                    const analyzed_define = try self.codebase.createEntity(.{
                        components.AstKind.define,
                        components.Value.init(value),
                        name,
                        components.Type.init(b.Void),
                    });
                    const type_of = typeOf(value);
                    if (eql(type_of, b.IntLiteral) or eql(type_of, b.FloatLiteral)) {
                        _ = try analyzed_define.set(.{
                            try components.DependentEntities.fromSlice(self.allocator, &.{value}),
                        });
                    }
                    try scopes.putName(name, analyzed_define);
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
                            lhs.get(components.Local),
                            components.Field.init(field),
                            components.Value.init(value),
                        });
                    }
                    panic("\nassigning to invalid field {s}\n", .{literalOf(rhs)});
                },
                else => panic("\nassigning to unsupported kind {}\n", .{kind}),
            }
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
                _ = try result.set(.{
                    try components.DependentEntities.fromSlice(self.allocator, &.{ then_entity, else_entity }),
                });
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
            const range = iterator.get(components.Range);
            const loop_variable = for_.get(components.LoopVariable).entity;
            const name = components.Name.init(loop_variable);
            const define = try self.codebase.createEntity(.{
                components.AstKind.define,
                components.Value.init(range.first),
                name,
                components.Type.init(self.builtins.Void),
            });
            try scopes.putName(name, define);
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
            return result;
        }

        fn analyzeRange(self: *Self, entity: Entity) !Entity {
            const b = self.builtins;
            const range = entity.get(components.Range);
            const first = try self.analyzeExpression(range.first);
            const last = try self.analyzeExpression(range.last);
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
            return try entity.set(.{components.Type.init(range_type)});
        }

        const Error = error{ Overflow, InvalidCharacter, OutOfMemory, CantOpenFile, CannotUnifyTypes, CompileError };

        fn analyzeExpression(self: *Self, entity: Entity) Error!Entity {
            const kind = entity.get(components.AstKind);
            return switch (kind) {
                .symbol => try self.analyzeSymbol(entity),
                .int, .float => entity,
                .call => try self.analyzeCall(entity, self),
                .binary_op => try self.analyzeBinaryOp(entity),
                .define => try self.analyzeDefine(entity),
                .if_ => try self.analyzeIf(entity),
                .while_ => try self.analyzeWhile(entity),
                .for_ => try self.analyzeFor(entity),
                .pointer => try self.analyzePointer(entity),
                .range => try self.analyzeRange(entity),
                else => panic("\nanalyzeExpression unsupported kind {}\n", .{kind}),
            };
        }

        fn analyzeFunctionParameters(self: *Self) !void {
            const scopes = self.function.getPtr(components.Scopes);
            const parameters = self.function.get(components.Parameters).slice();
            for (parameters) |parameter| {
                const parameter_type = try self.analyzeExpression(parameter.get(components.TypeAst).entity);
                _ = try parameter.set(.{
                    components.Type.init(parameter_type),
                    components.Name.init(parameter),
                });
                try scopes.putLiteral(parameter.get(components.Literal), parameter);
            }
            _ = try self.function.set(.{components.AnalyzedParameters{ .value = true }});
        }

        fn analyzeFunctionReturnType(self: *Self) !Entity {
            const return_type = try self.analyzeExpression(self.function.get(components.ReturnTypeAst).entity);
            _ = try self.function.set(.{components.ReturnType.init(return_type)});
            return return_type;
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
            _ = try self.function.set(.{components.Module.init(self.module)});
            if (!self.function.contains(components.AnalyzedParameters)) {
                try self.analyzeFunctionParameters();
            }
            const return_type = try self.analyzeFunctionReturnType();
            if (self.function.has(components.Body)) |body| {
                _ = try self.codebase.getPtr(components.Functions).append(self.function);
                const return_entity = try self.analyzeFunctionBody(body.slice());
                try self.implicitTypeConversion(return_entity, return_type);
            } else {
                _ = try self.codebase.getPtr(components.ForeignImports).append(self.function);
            }
        }
    };
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

test "analyze semantics int literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    const types = [_][]const u8{ "i64", "i32", "u64", "u32", "f64", "f32" };
    const builtin_types = [_]Entity{ builtins.I64, builtins.I32, builtins.U64, builtins.U32, builtins.F64, builtins.F32 };
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start = fn(): {s}
            \\  5
            \\end
        , .{type_of}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
        try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
        try expectEqual(start.get(components.Parameters).len(), 0);
        try expectEqual(start.get(components.ReturnType).entity, builtin_types[i]);
        const body = start.get(components.Body).slice();
        try expectEqual(body.len, 1);
        const int_literal = body[0];
        try expectEqual(int_literal.get(components.AstKind), .int);
        try expectEqual(typeOf(int_literal), builtin_types[i]);
        try expectEqualStrings(literalOf(int_literal), "5");
    }
}

test "analyze semantics float literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    const types = [_][]const u8{ "f64", "f32" };
    const builtin_types = [_]Entity{ builtins.F64, builtins.F32 };
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start = fn(): {s}
            \\  5.3
            \\end
        , .{type_of}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
        try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
        try expectEqual(start.get(components.Parameters).len(), 0);
        try expectEqual(start.get(components.ReturnType).entity, builtin_types[i]);
        const body = start.get(components.Body).slice();
        try expectEqual(body.len, 1);
        const float_literal = body[0];
        try expectEqual(float_literal.get(components.AstKind), .float);
        try expectEqual(typeOf(float_literal), builtin_types[i]);
        try expectEqualStrings(literalOf(float_literal), "5.3");
    }
}

test "analyze semantics call local function" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    const types = [_][]const u8{ "i64", "i32", "u64", "u32", "f64", "f32" };
    const builtin_types = [_]Entity{ builtins.I64, builtins.I32, builtins.U64, builtins.U32, builtins.F64, builtins.F32 };
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start = fn(): {s}
            \\  baz()
            \\end
            \\
            \\baz = fn(): {s}
            \\  10
            \\end
        , .{ type_of, type_of }));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
        try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
        try expectEqual(start.get(components.Parameters).len(), 0);
        try expectEqual(start.get(components.ReturnType).entity, builtin_types[i]);
        const baz = blk: {
            const body = start.get(components.Body).slice();
            try expectEqual(body.len, 1);
            const call = body[0];
            try expectEqual(call.get(components.AstKind), .call);
            try expectEqual(call.get(components.Arguments).len(), 0);
            try expectEqual(typeOf(call), builtin_types[i]);
            break :blk call.get(components.Callable).entity;
        };
        try expectEqualStrings(literalOf(baz.get(components.Module).entity), "foo");
        try expectEqualStrings(literalOf(baz.get(components.Name).entity), "baz");
        try expectEqual(baz.get(components.Parameters).len(), 0);
        try expectEqual(baz.get(components.ReturnType).entity, builtin_types[i]);
        const body = baz.get(components.Body).slice();
        try expectEqual(body.len, 1);
        const int_literal = body[0];
        try expectEqual(int_literal.get(components.AstKind), .int);
        try expectEqual(typeOf(int_literal), builtin_types[i]);
        try expectEqualStrings(literalOf(int_literal), "10");
    }
}

test "analyze semantics call function import" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    const types = [_][]const u8{ "i64", "i32", "u64", "u32", "f64", "f32" };
    const builtin_types = [_]Entity{ builtins.I64, builtins.I32, builtins.U64, builtins.U32, builtins.F64, builtins.F32 };
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\bar = import("bar.yeti")
            \\
            \\start = fn(): {s}
            \\  bar.baz()
            \\end
        , .{type_of}));
        _ = try fs.newFile("bar.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\baz = fn(): {s}
            \\  10
            \\end
        , .{type_of}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
        try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
        try expectEqual(start.get(components.Parameters).len(), 0);
        try expectEqual(start.get(components.ReturnType).entity, builtin_types[i]);
        const baz = blk: {
            const body = start.get(components.Body).slice();
            try expectEqual(body.len, 1);
            const call = body[0];
            try expectEqual(call.get(components.AstKind), .call);
            try expectEqual(call.get(components.Arguments).len(), 0);
            try expectEqual(typeOf(call), builtin_types[i]);
            break :blk call.get(components.Callable).entity;
        };
        try expectEqualStrings(literalOf(baz.get(components.Module).entity), "bar");
        try expectEqualStrings(literalOf(baz.get(components.Name).entity), "baz");
        try expectEqual(baz.get(components.Parameters).len(), 0);
        try expectEqual(baz.get(components.ReturnType).entity, builtin_types[i]);
        const body = baz.get(components.Body).slice();
        try expectEqual(body.len, 1);
        const int_literal = body[0];
        try expectEqual(int_literal.get(components.AstKind), .int);
        try expectEqual(typeOf(int_literal), builtin_types[i]);
        try expectEqualStrings(literalOf(int_literal), "10");
    }
}

test "analyze semantics define" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    const types = [_][]const u8{ "i64", "i32", "u64", "u32", "f64", "f32" };
    const builtin_types = [_]Entity{ builtins.I64, builtins.I32, builtins.U64, builtins.U32, builtins.F64, builtins.F32 };
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start = fn(): {s}
            \\  x = 10
            \\  x
            \\end
        , .{type_of}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
        try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
        try expectEqual(start.get(components.Parameters).len(), 0);
        try expectEqual(start.get(components.ReturnType).entity, builtin_types[i]);
        const body = start.get(components.Body).slice();
        try expectEqual(body.len, 2);
        const define = body[0];
        try expectEqual(define.get(components.AstKind), .define);
        try expectEqual(typeOf(define), builtins.Void);
        try expectEqualStrings(literalOf(define.get(components.Name).entity), "x");
        try expectEqualStrings(literalOf(define.get(components.Value).entity), "10");
        const local = body[1];
        try expectEqual(local.get(components.AstKind), .local);
        try expectEqual(local.get(components.Local).entity, define);
        try expectEqual(typeOf(local), builtin_types[i]);
    }
}

test "analyze semantics two defines" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    const types = [_][]const u8{ "f64", "f32" };
    const builtin_types = [_]Entity{ builtins.F64, builtins.F32 };
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start = fn(): {s}
            \\  x = 10
            \\  y = 15
            \\  x
            \\end
        , .{type_of}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
        try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
        try expectEqual(start.get(components.Parameters).len(), 0);
        try expectEqual(start.get(components.ReturnType).entity, builtin_types[i]);
        const body = start.get(components.Body).slice();
        try expectEqual(body.len, 3);
        const x = body[0];
        {
            try expectEqual(x.get(components.AstKind), .define);
            try expectEqual(typeOf(x), builtins.Void);
            try expectEqualStrings(literalOf(x.get(components.Name).entity), "x");
            const value = x.get(components.Value).entity;
            try expectEqual(typeOf(value), builtin_types[i]);
            try expectEqualStrings(literalOf(value), "10");
        }
        const y = body[1];
        try expectEqual(y.get(components.AstKind), .define);
        try expectEqual(typeOf(y), builtins.Void);
        try expectEqualStrings(literalOf(y.get(components.Name).entity), "y");
        try expectEqualStrings(literalOf(y.get(components.Value).entity), "15");
        const local = body[2];
        try expectEqual(local.get(components.AstKind), .local);
        try expectEqual(local.get(components.Local).entity, x);
        try expectEqual(typeOf(local), builtin_types[i]);
    }
}

test "analyze semantics define with explicit float type" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    const types = [_][]const u8{ "f64", "f32" };
    const builtin_types = [_]Entity{ builtins.F64, builtins.F32 };
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start = fn(): {s}
            \\  x: {s} = 10
            \\  x
            \\end
        , .{ type_of, type_of }));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
        try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
        try expectEqual(start.get(components.Parameters).len(), 0);
        try expectEqual(start.get(components.ReturnType).entity, builtin_types[i]);
        const body = start.get(components.Body).slice();
        try expectEqual(body.len, 2);
        const define = body[0];
        try expectEqual(define.get(components.AstKind), .define);
        try expectEqual(typeOf(define), builtins.Void);
        try expectEqualStrings(literalOf(define.get(components.Name).entity), "x");
        try expectEqualStrings(literalOf(define.get(components.Value).entity), "10");
        const local = body[1];
        try expectEqual(local.get(components.AstKind), .local);
        try expectEqual(local.get(components.Local).entity, define);
        try expectEqual(typeOf(local), builtin_types[i]);
    }
}

test "analyze semantics function with argument" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    const types = [_][]const u8{ "i64", "i32", "u64", "u32", "f64", "f32" };
    const builtin_types = [_]Entity{ builtins.I64, builtins.I32, builtins.U64, builtins.U32, builtins.F64, builtins.F32 };
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start = fn(): {s}
            \\  x: {s} = 10
            \\  id(x)
            \\end
            \\
            \\id = fn(x: {s}): {s}
            \\  x
            \\end
        , .{ type_of, type_of, type_of, type_of }));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
        try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
        try expectEqual(start.get(components.Parameters).len(), 0);
        try expectEqual(start.get(components.ReturnType).entity, builtin_types[i]);
        const id = blk: {
            const body = start.get(components.Body).slice();
            try expectEqual(body.len, 2);
            const define = body[0];
            try expectEqual(define.get(components.AstKind), .define);
            try expectEqual(typeOf(define), builtins.Void);
            try expectEqualStrings(literalOf(define.get(components.Name).entity), "x");
            try expectEqualStrings(literalOf(define.get(components.Value).entity), "10");
            const call = body[1];
            try expectEqual(call.get(components.AstKind), .call);
            try expectEqual(typeOf(call), builtin_types[i]);
            const arguments = call.get(components.Arguments).slice();
            try expectEqual(arguments.len, 1);
            const argument = arguments[0];
            try expectEqual(argument.get(components.AstKind), .local);
            try expectEqual(typeOf(argument), builtin_types[i]);
            try expectEqual(argument.get(components.Local).entity, define);

            break :blk call.get(components.Callable).entity;
        };
        try expectEqualStrings(literalOf(id.get(components.Module).entity), "foo");
        try expectEqualStrings(literalOf(id.get(components.Name).entity), "id");
        const parameters = id.get(components.Parameters).slice();
        try expectEqual(parameters.len, 1);
        const x = parameters[0];
        try expectEqual(typeOf(x), builtin_types[i]);
        try expectEqualStrings(literalOf(x.get(components.Name).entity), "x");
        const body = id.get(components.Body).slice();
        try expectEqual(body.len, 1);
        const local = body[0];
        try expectEqual(local.get(components.AstKind), .local);
        try expectEqual(typeOf(local), builtin_types[i]);
        try expectEqual(local.get(components.Local).entity, x);
    }
}

test "analyze semantics function call twice" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    const types = [_][]const u8{ "i64", "i32", "u64", "u32", "f64", "f32" };
    const builtin_types = [_]Entity{ builtins.I64, builtins.I32, builtins.U64, builtins.U32, builtins.F64, builtins.F32 };
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start = fn(): {s}
            \\  x = id(10)
            \\  id(25)
            \\end
            \\
            \\id = fn(x: {s}): {s}
            \\  x
            \\end
        , .{ type_of, type_of, type_of }));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
        try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
        try expectEqual(start.get(components.Parameters).len(), 0);
        try expectEqual(start.get(components.ReturnType).entity, builtin_types[i]);
        const start_body = start.get(components.Body).slice();
        try expectEqual(start_body.len, 2);
        const id = blk: {
            const define = start_body[0];
            try expectEqual(define.get(components.AstKind), .define);
            try expectEqual(typeOf(define), builtins.Void);
            try expectEqualStrings(literalOf(define.get(components.Name).entity), "x");
            const call = define.get(components.Value).entity;
            try expectEqual(typeOf(call), builtin_types[i]);
            try expectEqual(call.get(components.AstKind), .call);
            const arguments = call.get(components.Arguments).slice();
            try expectEqual(arguments.len, 1);
            const argument = arguments[0];
            try expectEqual(argument.get(components.AstKind), .int);
            try expectEqual(typeOf(argument), builtin_types[i]);
            try expectEqualStrings(literalOf(argument), "10");
            break :blk call.get(components.Callable).entity;
        };
        const call = start_body[1];
        try expectEqual(call.get(components.AstKind), .call);
        try expectEqual(typeOf(call), builtin_types[i]);
        const arguments = call.get(components.Arguments).slice();
        try expectEqual(arguments.len, 1);
        const argument = arguments[0];
        try expectEqual(argument.get(components.AstKind), .int);
        try expectEqual(typeOf(argument), builtin_types[i]);
        try expectEqualStrings(literalOf(argument), "25");
        try expectEqual(call.get(components.Callable).entity, id);
        try expectEqualStrings(literalOf(id.get(components.Module).entity), "foo");
        try expectEqualStrings(literalOf(id.get(components.Name).entity), "id");
        const parameters = id.get(components.Parameters).slice();
        try expectEqual(parameters.len, 1);
        const x = parameters[0];
        try expectEqual(typeOf(x), builtin_types[i]);
        try expectEqualStrings(literalOf(x.get(components.Name).entity), "x");
        const body = id.get(components.Body).slice();
        try expectEqual(body.len, 1);
        const local = body[0];
        try expectEqual(local.get(components.AstKind), .local);
        try expectEqual(typeOf(local), builtin_types[i]);
        try expectEqual(local.get(components.Local).entity, x);
    }
}

test "analyze semantics binary op two comptime known" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    const types = [_][]const u8{ "i64", "i32", "i16", "i8", "u64", "u32", "u16", "u8", "f64", "f32" };
    const builtin_types = [_]Entity{ builtins.I64, builtins.I32, builtins.I16, builtins.I8, builtins.U64, builtins.U32, builtins.U16, builtins.U8, builtins.F64, builtins.F32 };
    const op_strings = [_][]const u8{ "+", "-", "*", "/" };
    const intrinsics = [_]components.Intrinsic{ .add, .subtract, .multiply, .divide };
    for (op_strings) |op_string, op_index| {
        for (types) |type_of, i| {
            var fs = try MockFileSystem.init(&arena);
            _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
                \\start = fn(): {s}
                \\  x: {s} = 10
                \\  y: {s} = 32
                \\  x {s} y
                \\end
            , .{ type_of, type_of, type_of, op_string }));
            const module = try analyzeSemantics(codebase, fs, "foo.yeti");
            const top_level = module.get(components.TopLevel);
            const start = top_level.findString("start").get(components.Overloads).slice()[0];
            try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
            try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
            try expectEqual(start.get(components.Parameters).len(), 0);
            try expectEqual(start.get(components.ReturnType).entity, builtin_types[i]);
            const body = start.get(components.Body).slice();
            try expectEqual(body.len, 3);
            const x = body[0];
            {
                try expectEqual(x.get(components.AstKind), .define);
                try expectEqual(typeOf(x), builtins.Void);
                try expectEqualStrings(literalOf(x.get(components.Name).entity), "x");
                const value = x.get(components.Value).entity;
                try expectEqual(typeOf(value), builtin_types[i]);
                try expectEqualStrings(literalOf(value), "10");
            }
            const y = body[1];
            {
                try expectEqual(y.get(components.AstKind), .define);
                try expectEqual(typeOf(y), builtins.Void);
                try expectEqualStrings(literalOf(y.get(components.Name).entity), "y");
                const value = y.get(components.Value).entity;
                try expectEqual(typeOf(value), builtin_types[i]);
                try expectEqualStrings(literalOf(value), "32");
            }
            const intrinsic = body[2];
            try expectEqual(intrinsic.get(components.AstKind), .intrinsic);
            try expectEqual(intrinsic.get(components.Intrinsic), intrinsics[op_index]);
            try expectEqual(typeOf(intrinsic), builtin_types[i]);
            const arguments = intrinsic.get(components.Arguments).slice();
            try expectEqual(arguments.len, 2);
            const lhs = arguments[0];
            try expectEqual(lhs.get(components.AstKind), .local);
            try expectEqual(lhs.get(components.Local).entity, x);
            const rhs = arguments[1];
            try expectEqual(rhs.get(components.AstKind), .local);
            try expectEqual(rhs.get(components.Local).entity, y);
        }
    }
}

test "analyze semantics comparison op two comptime known" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    const types = [_][]const u8{ "i64", "i32", "i16", "i8", "u64", "u32", "u16", "u8", "f64", "f32" };
    const builtin_types = [_]Entity{ builtins.I64, builtins.I32, builtins.I16, builtins.I8, builtins.U64, builtins.U32, builtins.U16, builtins.U8, builtins.F64, builtins.F32 };
    const op_strings = [_][]const u8{ "==", "!=", "<", "<=", ">", ">=" };
    const intrinsics = [_]components.Intrinsic{
        .equal,
        .not_equal,
        .less_than,
        .less_equal,
        .greater_than,
        .greater_equal,
    };
    for (op_strings) |op_string, op_index| {
        for (types) |type_of, i| {
            var fs = try MockFileSystem.init(&arena);
            _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
                \\start = fn(): i32
                \\  x: {s} = 10
                \\  y: {s} = 32
                \\  x {s} y
                \\end
            , .{ type_of, type_of, op_string }));
            const module = try analyzeSemantics(codebase, fs, "foo.yeti");
            const top_level = module.get(components.TopLevel);
            const start = top_level.findString("start").get(components.Overloads).slice()[0];
            try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
            try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
            try expectEqual(start.get(components.Parameters).len(), 0);
            try expectEqual(start.get(components.ReturnType).entity, builtins.I32);
            const body = start.get(components.Body).slice();
            try expectEqual(body.len, 3);
            const x = body[0];
            {
                try expectEqual(x.get(components.AstKind), .define);
                try expectEqual(typeOf(x), builtins.Void);
                try expectEqualStrings(literalOf(x.get(components.Name).entity), "x");
                const value = x.get(components.Value).entity;
                try expectEqual(typeOf(value), builtin_types[i]);
                try expectEqualStrings(literalOf(value), "10");
            }
            const y = body[1];
            {
                try expectEqual(y.get(components.AstKind), .define);
                try expectEqual(typeOf(y), builtins.Void);
                try expectEqualStrings(literalOf(y.get(components.Name).entity), "y");
                const value = y.get(components.Value).entity;
                try expectEqual(typeOf(value), builtin_types[i]);
                try expectEqualStrings(literalOf(value), "32");
            }
            const intrinsic = body[2];
            try expectEqual(intrinsic.get(components.AstKind), .intrinsic);
            try expectEqual(intrinsic.get(components.Intrinsic), intrinsics[op_index]);
            try expectEqual(typeOf(intrinsic), builtins.I32);
            const arguments = intrinsic.get(components.Arguments).slice();
            try expectEqual(arguments.len, 2);
            const lhs = arguments[0];
            try expectEqual(lhs.get(components.AstKind), .local);
            try expectEqual(lhs.get(components.Local).entity, x);
            const rhs = arguments[1];
            try expectEqual(rhs.get(components.AstKind), .local);
            try expectEqual(rhs.get(components.Local).entity, y);
        }
    }
}

test "analyze semantics if then else" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    const types = [_][]const u8{"i64"};
    const builtin_types = [_]Entity{builtins.I64};
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start = fn(): {s}
            \\  if 1 then 20 else 30 end
            \\end
        , .{type_of}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
        try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
        try expectEqual(start.get(components.Parameters).len(), 0);
        try expectEqual(start.get(components.ReturnType).entity, builtin_types[i]);
        const body = start.get(components.Body).slice();
        try expectEqual(body.len, 1);
        const if_ = body[0];
        try expectEqual(if_.get(components.AstKind), .if_);
        try expectEqual(typeOf(if_), builtin_types[i]);
        const conditional = if_.get(components.Conditional).entity;
        try expectEqual(conditional.get(components.AstKind), .int);
        try expectEqualStrings(literalOf(conditional), "1");
        try expectEqual(typeOf(conditional), builtins.I32);
        const then = if_.get(components.Then).slice();
        try expectEqual(then.len, 1);
        const twenty = then[0];
        try expectEqual(twenty.get(components.AstKind), .int);
        try expectEqualStrings(literalOf(twenty), "20");
        try expectEqual(typeOf(twenty), builtin_types[i]);
        const else_ = if_.get(components.Else).slice();
        try expectEqual(else_.len, 1);
        const thirty = else_[0];
        try expectEqual(thirty.get(components.AstKind), .int);
        try expectEqualStrings(literalOf(thirty), "30");
        try expectEqual(typeOf(thirty), builtin_types[i]);
    }
}

test "analyze semantics if then else non constant conditional" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    const types = [_][]const u8{"i64"};
    const builtin_types = [_]Entity{builtins.I64};
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start = fn(): {s}
            \\  if f() then 20 else 30 end
            \\end
            \\
            \\f = fn(): i32
            \\  1
            \\end
        , .{type_of}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
        try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
        try expectEqual(start.get(components.Parameters).len(), 0);
        try expectEqual(start.get(components.ReturnType).entity, builtin_types[i]);
        const f = blk: {
            const body = start.get(components.Body).slice();
            try expectEqual(body.len, 1);
            const if_ = body[0];
            try expectEqual(if_.get(components.AstKind), .if_);
            try expectEqual(typeOf(if_), builtin_types[i]);
            const conditional = if_.get(components.Conditional).entity;
            try expectEqual(conditional.get(components.AstKind), .call);
            try expectEqual(typeOf(conditional), builtins.I32);
            const f = conditional.get(components.Callable).entity;
            const then = if_.get(components.Then).slice();
            try expectEqual(then.len, 1);
            const twenty = then[0];
            try expectEqual(twenty.get(components.AstKind), .int);
            try expectEqualStrings(literalOf(twenty), "20");
            try expectEqual(typeOf(twenty), builtin_types[i]);
            const else_ = if_.get(components.Else).slice();
            try expectEqual(else_.len, 1);
            const thirty = else_[0];
            try expectEqual(thirty.get(components.AstKind), .int);
            try expectEqualStrings(literalOf(thirty), "30");
            try expectEqual(typeOf(thirty), builtin_types[i]);
            break :blk f;
        };
        try expectEqualStrings(literalOf(f.get(components.Module).entity), "foo");
        try expectEqualStrings(literalOf(f.get(components.Name).entity), "f");
        try expectEqual(f.get(components.Parameters).len(), 0);
        try expectEqual(f.get(components.ReturnType).entity, builtins.I32);
        const body = f.get(components.Body).slice();
        try expectEqual(body.len, 1);
    }
}

test "analyze semantics if then else with different type branches" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    const types = [_][]const u8{"i64"};
    const builtin_types = [_]Entity{builtins.I64};
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start = fn(): {s}
            \\  if 1 then 20 else f() end
            \\end
            \\
            \\f = fn(): {s}
            \\  0
            \\end
        , .{ type_of, type_of }));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
        try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
        try expectEqual(start.get(components.Parameters).len(), 0);
        try expectEqual(start.get(components.ReturnType).entity, builtin_types[i]);
        const body = start.get(components.Body).slice();
        try expectEqual(body.len, 1);
        const if_ = body[0];
        try expectEqual(if_.get(components.AstKind), .if_);
        try expectEqual(typeOf(if_), builtin_types[i]);
        const conditional = if_.get(components.Conditional).entity;
        try expectEqual(conditional.get(components.AstKind), .int);
        try expectEqualStrings(literalOf(conditional), "1");
        try expectEqual(typeOf(conditional), builtins.I32);
        const then = if_.get(components.Then).slice();
        try expectEqual(then.len, 1);
        const twenty = then[0];
        try expectEqual(twenty.get(components.AstKind), .int);
        try expectEqualStrings(literalOf(twenty), "20");
        try expectEqual(typeOf(twenty), builtin_types[i]);
        const else_ = if_.get(components.Else).slice();
        try expectEqual(else_.len, 1);
        const call = else_[0];
        try expectEqual(call.get(components.AstKind), .call);
    }
}

test "analyze semantics of assignment" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    const types = [_][]const u8{"i64"};
    const builtin_types = [_]Entity{builtins.I64};
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start = fn(): {s}
            \\  x: {s} = 10
            \\  x = 3
            \\  x
            \\end
        , .{ type_of, type_of }));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
        try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
        try expectEqual(start.get(components.Parameters).len(), 0);
        try expectEqual(start.get(components.ReturnType).entity, builtin_types[i]);
        const body = start.get(components.Body).slice();
        try expectEqual(body.len, 3);
        const define = body[0];
        {
            try expectEqual(define.get(components.AstKind), .define);
            try expectEqual(typeOf(define), builtins.Void);
            try expectEqualStrings(literalOf(define.get(components.Name).entity), "x");
            const value = define.get(components.Value).entity;
            try expectEqual(typeOf(value), builtin_types[i]);
            try expectEqualStrings(literalOf(value), "10");
        }
        const assign = body[1];
        try expectEqual(assign.get(components.AstKind), .assign);
        try expectEqual(typeOf(assign), builtins.Void);
        try expectEqualStrings(literalOf(assign.get(components.Name).entity), "x");
        try expectEqualStrings(literalOf(assign.get(components.Value).entity), "3");
        const local = body[2];
        try expectEqual(local.get(components.AstKind), .local);
        try expectEqual(local.get(components.Local).entity, define);
        try expectEqual(typeOf(local), builtin_types[i]);
    }
}

test "analyze semantics of while loop" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = fn(): i32
        \\  i = 0
        \\  while i < 10 do
        \\      i = i + 1
        \\  end
        \\  i
        \\end
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.I32);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 3);
    const define = body[0];
    {
        try expectEqual(define.get(components.AstKind), .define);
        try expectEqual(typeOf(define), builtins.Void);
        try expectEqualStrings(literalOf(define.get(components.Name).entity), "i");
        const value = define.get(components.Value).entity;
        try expectEqual(typeOf(value), builtins.I32);
        try expectEqualStrings(literalOf(value), "0");
    }
    const while_ = body[1];
    try expectEqual(while_.get(components.AstKind), .while_);
    try expectEqual(typeOf(while_), builtins.Void);
    const conditional = while_.get(components.Conditional).entity;
    try expectEqual(conditional.get(components.AstKind), .intrinsic);
    try expectEqual(typeOf(conditional), builtins.I32);
    const while_body = while_.get(components.Body).slice();
    try expectEqual(while_body.len, 1);
    const assign = while_body[0];
    try expectEqual(assign.get(components.AstKind), .assign);
    try expectEqual(typeOf(assign), builtins.Void);
    try expectEqualStrings(literalOf(assign.get(components.Name).entity), "i");
    const value = assign.get(components.Value).entity;
    try expectEqual(value.get(components.AstKind), .intrinsic);
    const local = body[2];
    try expectEqual(local.get(components.AstKind), .local);
    try expectEqual(local.get(components.Local).entity, define);
    try expectEqual(typeOf(local), builtins.I32);
}

test "analyze semantics of for loop" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = fn(): i32
        \\  sum = 0
        \\  for i in 0:10 do
        \\      sum = sum + i
        \\  end
        \\  sum
        \\end
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.I32);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 3);
    const define = body[0];
    {
        try expectEqual(define.get(components.AstKind), .define);
        try expectEqual(typeOf(define), builtins.Void);
        try expectEqualStrings(literalOf(define.get(components.Name).entity), "sum");
        const value = define.get(components.Value).entity;
        try expectEqual(typeOf(value), builtins.I32);
        try expectEqualStrings(literalOf(value), "0");
    }
    const for_ = body[1];
    try expectEqual(for_.get(components.AstKind), .for_);
    try expectEqual(typeOf(for_), builtins.Void);
    const i = for_.get(components.LoopVariable).entity;
    {
        try expectEqual(i.get(components.AstKind), .define);
        try expectEqual(typeOf(i), builtins.Void);
        try expectEqualStrings(literalOf(i.get(components.Name).entity), "i");
        const value = i.get(components.Value).entity;
        try expectEqual(typeOf(value), builtins.IntLiteral);
        try expectEqualStrings(literalOf(value), "0");
    }
    const iterator = for_.get(components.Iterator).entity;
    try expectEqual(iterator.get(components.AstKind), .range);
    const range = iterator.get(components.Range);
    try expectEqual(typeOf(range.first), builtins.IntLiteral);
    try expectEqualStrings(literalOf(range.first), "0");
    try expectEqual(typeOf(range.last), builtins.IntLiteral);
    try expectEqualStrings(literalOf(range.last), "10");
    const for_body = for_.get(components.Body).slice();
    try expectEqual(for_body.len, 1);
    const assign = for_body[0];
    try expectEqual(assign.get(components.AstKind), .assign);
    try expectEqual(typeOf(assign), builtins.Void);
    try expectEqualStrings(literalOf(assign.get(components.Name).entity), "sum");
    const value = assign.get(components.Value).entity;
    try expectEqual(value.get(components.AstKind), .intrinsic);
    try expectEqual(value.get(components.Intrinsic), .add);
    const arguments = value.get(components.Arguments).slice();
    try expectEqual(arguments.len, 2);
    const lhs = arguments[0];
    try expectEqual(lhs.get(components.AstKind), .local);
    try expectEqual(lhs.get(components.Local).entity, define);
    const rhs = arguments[1];
    try expectEqual(rhs.get(components.AstKind), .local);
    try expectEqual(rhs.get(components.Local).entity, i);
    const local = body[2];
    try expectEqual(local.get(components.AstKind), .local);
    try expectEqual(local.get(components.Local).entity, define);
    try expectEqual(typeOf(local), builtins.I32);
}

test "analyze semantics of increment" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = fn(): i64
        \\  x = 0
        \\  x = x + 1
        \\  x
        \\end
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.I64);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 3);
    const define = body[0];
    try expectEqual(define.get(components.AstKind), .define);
    try expectEqual(typeOf(define), builtins.I64);
    try expectEqualStrings(literalOf(define.get(components.Name).entity), "x");
    try expectEqualStrings(literalOf(define.get(components.Value).entity), "0");
    const assign = body[1];
    try expectEqual(assign.get(components.AstKind), .assign);
    try expectEqual(typeOf(assign), builtins.Void);
    try expectEqualStrings(literalOf(assign.get(components.Name).entity), "x");
    const intrinsic = assign.get(components.Value).entity;
    try expectEqual(intrinsic.get(components.AstKind), .intrinsic);
    try expectEqual(intrinsic.get(components.Intrinsic), .add);
    try expectEqual(typeOf(intrinsic), builtins.I64);
    const arguments = intrinsic.get(components.Arguments).slice();
    try expectEqual(arguments.len, 2);
    const lhs = arguments[0];
    try expectEqual(lhs.get(components.AstKind), .local);
    try expectEqual(lhs.get(components.Local).entity, define);
    const rhs = arguments[1];
    try expectEqual(rhs.get(components.AstKind), .int);
    try expectEqualStrings(literalOf(rhs), "1");
    const local = body[2];
    try expectEqual(local.get(components.AstKind), .local);
    try expectEqual(local.get(components.Local).entity, define);
    try expectEqual(typeOf(local), builtins.I64);
}

test "analyze semantics of add between typed and inferred" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = fn(): i64
        \\  a: i64 = 10
        \\  b = 0
        \\  b = a + b
        \\  b
        \\end
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.I64);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 4);
    const a = body[0];
    try expectEqual(a.get(components.AstKind), .define);
    try expectEqual(typeOf(a), builtins.I64);
    try expectEqualStrings(literalOf(a.get(components.Name).entity), "a");
    try expectEqualStrings(literalOf(a.get(components.Value).entity), "10");
    const b = body[1];
    try expectEqual(b.get(components.AstKind), .define);
    try expectEqual(typeOf(b), builtins.I64);
    try expectEqualStrings(literalOf(b.get(components.Name).entity), "b");
    try expectEqualStrings(literalOf(b.get(components.Value).entity), "0");
    const assign = body[2];
    try expectEqual(assign.get(components.AstKind), .assign);
    try expectEqual(typeOf(assign), builtins.Void);
    try expectEqualStrings(literalOf(assign.get(components.Name).entity), "b");
    const intrinsic = assign.get(components.Value).entity;
    try expectEqual(intrinsic.get(components.AstKind), .intrinsic);
    try expectEqual(intrinsic.get(components.Intrinsic), .add);
    try expectEqual(typeOf(intrinsic), builtins.I64);
    const arguments = intrinsic.get(components.Arguments).slice();
    try expectEqual(arguments.len, 2);
    const lhs = arguments[0];
    try expectEqual(lhs.get(components.AstKind), .local);
    try expectEqual(lhs.get(components.Local).entity, a);
    const rhs = arguments[1];
    try expectEqual(rhs.get(components.AstKind), .local);
    try expectEqual(rhs.get(components.Local).entity, b);
    const local = body[3];
    try expectEqual(local.get(components.AstKind), .local);
    try expectEqual(local.get(components.Local).entity, b);
    try expectEqual(typeOf(local), builtins.I64);
}

test "analyze semantics of pipeline" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\square = fn(x: i64): i64
        \\  x * x
        \\end
        \\
        \\start = fn(): i64
        \\  5 |> square()
        \\end
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.I64);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 1);
    const call = body[0];
    try expectEqual(call.get(components.AstKind), .call);
    const arguments = call.get(components.Arguments).slice();
    try expectEqual(arguments.len, 1);
    try expectEqual(typeOf(call), builtins.I64);
    const five = arguments[0];
    try expectEqual(typeOf(five), builtins.I64);
    try expectEqualStrings(literalOf(five), "5");
    const square = call.get(components.Callable).entity;
    try expectEqualStrings(literalOf(square.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(square.get(components.Name).entity), "square");
}

test "analyze semantics of pipeline with parenthesis omitted" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\square = fn(x: i64): i64
        \\  x * x
        \\end
        \\
        \\start = fn(): i64
        \\  5 |> square
        \\end
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.I64);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 1);
    const call = body[0];
    try expectEqual(call.get(components.AstKind), .call);
    const arguments = call.get(components.Arguments).slice();
    try expectEqual(arguments.len, 1);
    try expectEqual(typeOf(call), builtins.I64);
    const five = arguments[0];
    try expectEqual(typeOf(five), builtins.I64);
    try expectEqualStrings(literalOf(five), "5");
    const square = call.get(components.Callable).entity;
    try expectEqualStrings(literalOf(square.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(square.get(components.Name).entity), "square");
}

test "analyze semantics of pipeline with position specified" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\min = fn(x: i64, y: i64): i64
        \\  if x < y then x else y end
        \\end
        \\
        \\start = fn(): i64
        \\  5 |> min(3, _)
        \\end
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.I64);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 1);
    const call = body[0];
    try expectEqual(call.get(components.AstKind), .call);
    const arguments = call.get(components.Arguments).slice();
    try expectEqual(arguments.len, 2);
    try expectEqual(typeOf(call), builtins.I64);
    const three = arguments[0];
    try expectEqual(typeOf(three), builtins.I64);
    try expectEqualStrings(literalOf(three), "3");
    const five = arguments[1];
    try expectEqual(typeOf(five), builtins.I64);
    try expectEqualStrings(literalOf(five), "5");
    const min = call.get(components.Callable).entity;
    try expectEqualStrings(literalOf(min.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(min.get(components.Name).entity), "min");
}

test "analyze semantics of pipeline calling imported function" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\math = import("math.yeti")
        \\
        \\start = fn(): i64
        \\  5 |> math.min(3, _)
        \\end
    );
    _ = try fs.newFile("math.yeti",
        \\min = fn(x: i64, y: i64): i64
        \\  if x < y then x else y end
        \\end
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.I64);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 1);
    const call = body[0];
    try expectEqual(call.get(components.AstKind), .call);
    const arguments = call.get(components.Arguments).slice();
    try expectEqual(arguments.len, 2);
    try expectEqual(typeOf(call), builtins.I64);
    const three = arguments[0];
    try expectEqual(typeOf(three), builtins.I64);
    try expectEqualStrings(literalOf(three), "3");
    const five = arguments[1];
    try expectEqual(typeOf(five), builtins.I64);
    try expectEqualStrings(literalOf(five), "5");
    const min = call.get(components.Callable).entity;
    try expectEqualStrings(literalOf(min.get(components.Module).entity), "math");
    try expectEqualStrings(literalOf(min.get(components.Name).entity), "min");
}

test "analyze semantics of pipeline calling imported function with parenthesis omitted" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\math = import("math.yeti")
        \\
        \\start = fn(): i64
        \\  5 |> math.square
        \\end
    );
    _ = try fs.newFile("math.yeti",
        \\square = fn(x: i64): i64
        \\  x * x
        \\end
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.I64);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 1);
    const call = body[0];
    try expectEqual(call.get(components.AstKind), .call);
    const arguments = call.get(components.Arguments).slice();
    try expectEqual(arguments.len, 1);
    try expectEqual(typeOf(call), builtins.I64);
    const five = arguments[0];
    try expectEqual(typeOf(five), builtins.I64);
    try expectEqualStrings(literalOf(five), "5");
    const square = call.get(components.Callable).entity;
    try expectEqualStrings(literalOf(square.get(components.Module).entity), "math");
    try expectEqualStrings(literalOf(square.get(components.Name).entity), "square");
}

test "analyze semantics of calling imported function with local arguments" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\bar = import("bar.yeti")
        \\
        \\g = fn(x: i64): i64
        \\  x + x
        \\end
        \\
        \\start = fn(): i64
        \\  bar.f(g(300))
        \\end
    );
    _ = try fs.newFile("bar.yeti",
        \\f = fn(x: i64): i64
        \\  x * x
        \\end
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.I64);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 1);
    const g = blk: {
        const f = body[0];
        try expectEqual(f.get(components.AstKind), .call);
        const arguments = f.get(components.Arguments).slice();
        try expectEqual(arguments.len, 1);
        try expectEqual(typeOf(f), builtins.I64);
        const callable = f.get(components.Callable).entity;
        try expectEqualStrings(literalOf(callable.get(components.Module).entity), "bar");
        try expectEqualStrings(literalOf(callable.get(components.Name).entity), "f");
        break :blk arguments[0];
    };
    try expectEqual(g.get(components.AstKind), .call);
    const arguments = g.get(components.Arguments).slice();
    try expectEqual(arguments.len, 1);
    try expectEqual(typeOf(g), builtins.I64);
    const callable = g.get(components.Callable).entity;
    try expectEqualStrings(literalOf(callable.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(callable.get(components.Name).entity), "g");
    const five = arguments[0];
    try expectEqual(typeOf(five), builtins.I64);
    try expectEqualStrings(literalOf(five), "300");
}

test "analyze semantics of calling imported function twice" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\bar = import("bar.yeti")
        \\
        \\start = fn(): i64
        \\  bar.f(bar.f(300))
        \\end
    );
    _ = try fs.newFile("bar.yeti",
        \\f = fn(x: i64): i64
        \\  x * x
        \\end
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.I64);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 1);
    const f = body[0];
    try expectEqual(f.get(components.AstKind), .call);
    const f_arguments = f.get(components.Arguments).slice();
    try expectEqual(f_arguments.len, 1);
    try expectEqual(typeOf(f), builtins.I64);
    const f_callable = f.get(components.Callable).entity;
    const f_module = f_callable.get(components.Module).entity;
    try expectEqualStrings(literalOf(f_module), "bar");
    try expectEqualStrings(literalOf(f_callable.get(components.Name).entity), "f");
    const f_inner = f_arguments[0];
    try expectEqual(f_inner.get(components.AstKind), .call);
    const f_inner_arguments = f_inner.get(components.Arguments).slice();
    try expectEqual(f_inner_arguments.len, 1);
    try expectEqual(typeOf(f_inner), builtins.I64);
    const f_inner_callable = f_inner.get(components.Callable).entity;
    try expectEqual(f_inner_callable, f_callable);
}

test "analyze semantics of foreign exports" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\square = fn(x: i64): i64
        \\  x * x
        \\end
        \\
        \\foreign_export(square)
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const square = top_level.findString("square").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(square.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(square.get(components.Name).entity), "square");
    try expectEqual(square.get(components.Parameters).len(), 1);
    try expectEqual(square.get(components.ReturnType).entity, builtins.I64);
    const body = square.get(components.Body).slice();
    try expectEqual(body.len, 1);
}

test "analyze semantics of foreign exports with recursion" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\fib = fn(n: i64): i64
        \\  if n < 2 then
        \\    0
        \\  else
        \\    fib(n - 1) + fib(n - 2)
        \\  end
        \\end
        \\
        \\foreign_export(fib)
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const fib = top_level.findString("fib").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(fib.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(fib.get(components.Name).entity), "fib");
    try expectEqual(fib.get(components.Parameters).len(), 1);
    try expectEqual(fib.get(components.ReturnType).entity, builtins.I64);
    const body = fib.get(components.Body).slice();
    try expectEqual(body.len, 1);
}

test "analyze semantics of foreign import" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\log = foreign_import("console", "log", Fn(value: i64): void)
        \\
        \\start = fn(): void
        \\  log(10)
        \\end
    );
    _ = try analyzeSemantics(codebase, fs, "foo.yeti");
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.Void);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 1);
    const log = body[0];
    try expectEqual(log.get(components.AstKind), .call);
    const arguments = log.get(components.Arguments).slice();
    try expectEqual(arguments.len, 1);
    const callable = log.get(components.Callable).entity;
    try expectEqualStrings(literalOf(callable.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(callable.get(components.Name).entity), "log");
    const parameters = callable.get(components.Parameters).slice();
    try expectEqual(parameters.len, 1);
    try expectEqual(callable.get(components.ReturnType).entity, builtins.Void);
    const parameter = parameters[0];
    try expectEqual(typeOf(parameter), builtins.I64);
    try expectEqualStrings(literalOf(parameter.get(components.Name).entity), "value");
}

test "analyze semantics of casting int literal to *i64" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = fn(): *i64
        \\  cast(*i64, 0)
        \\end
    );
    _ = try analyzeSemantics(codebase, fs, "foo.yeti");
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    const return_type = start.get(components.ReturnType).entity;
    try expectEqualStrings(literalOf(return_type), "*i64");
    try expectEqual(parentType(return_type), builtins.Ptr);
    try expectEqualStrings(literalOf(valueType(return_type)), "i64");
    try expectEqual(valueType(return_type), builtins.I64);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 1);
    const cast = body[0];
    try expectEqual(cast.get(components.AstKind), .cast);
    const pointer_type = typeOf(cast);
    try expectEqual(parentType(pointer_type), builtins.Ptr);
    try expectEqual(valueType(pointer_type), builtins.I64);
    const zero = cast.get(components.Value).entity;
    try expectEqual(zero.get(components.AstKind), .int);
    try expectEqual(typeOf(zero), builtins.I32);
    try expectEqualStrings(literalOf(zero), "0");
}

test "analyze semantics of casting i32 to *i64" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = fn(): *i64
        \\  i: i32 = 0
        \\  cast(*i64, i)
        \\end
    );
    _ = try analyzeSemantics(codebase, fs, "foo.yeti");
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    const return_type = start.get(components.ReturnType).entity;
    try expectEqualStrings(literalOf(return_type), "*i64");
    try expectEqual(parentType(return_type), builtins.Ptr);
    try expectEqualStrings(literalOf(valueType(return_type)), "i64");
    try expectEqual(valueType(return_type), builtins.I64);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 2);
    const define = body[0];
    try expectEqual(define.get(components.AstKind), .define);
    try expectEqual(typeOf(define), builtins.I32);
    try expectEqualStrings(literalOf(define.get(components.Name).entity), "i");
    try expectEqualStrings(literalOf(define.get(components.Value).entity), "0");
    const cast = body[1];
    try expectEqual(cast.get(components.AstKind), .cast);
    const pointer_type = typeOf(cast);
    try expectEqual(parentType(pointer_type), builtins.Ptr);
    try expectEqual(valueType(pointer_type), builtins.I64);
    const local = cast.get(components.Value).entity;
    try expectEqual(local.get(components.AstKind), .local);
    try expectEqual(local.get(components.Local).entity, define);
    try expectEqual(typeOf(local), builtins.I32);
}

test "analyze semantics of pointer store" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = fn(): void
        \\  ptr = cast(*i64, 0)
        \\  *ptr = 10
        \\end
    );
    _ = try analyzeSemantics(codebase, fs, "foo.yeti");
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.Void);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 2);
    const define = body[0];
    try expectEqual(define.get(components.AstKind), .define);
    try expectEqualStrings(literalOf(define.get(components.Name).entity), "ptr");
    const cast = define.get(components.Value).entity;
    try expectEqual(cast.get(components.AstKind), .cast);
    const pointer_type = typeOf(cast);
    try expectEqual(parentType(pointer_type), builtins.Ptr);
    try expectEqual(valueType(pointer_type), builtins.I64);
    const zero = cast.get(components.Value).entity;
    try expectEqual(zero.get(components.AstKind), .int);
    try expectEqual(typeOf(zero), builtins.I32);
    try expectEqualStrings(literalOf(zero), "0");
    try expectEqual(valueType(typeOf(define)), builtins.I64);
    const store = body[1];
    try expectEqual(store.get(components.AstKind), .intrinsic);
    try expectEqual(store.get(components.Intrinsic), .store);
    try expectEqual(typeOf(store), builtins.Void);
    const arguments = store.get(components.Arguments).slice();
    try expectEqual(arguments.len, 2);
    const lhs = arguments[0];
    try expectEqual(lhs.get(components.AstKind), .local);
    try expectEqual(lhs.get(components.Local).entity, define);
    const rhs = arguments[1];
    try expectEqual(rhs.get(components.AstKind), .int);
    try expectEqual(typeOf(rhs), builtins.I64);
    try expectEqualStrings(literalOf(rhs), "10");
}

test "analyze semantics of pointer load" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = fn(): i64
        \\  ptr = cast(*i64, 0)
        \\  *ptr
        \\end
    );
    _ = try analyzeSemantics(codebase, fs, "foo.yeti");
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.I64);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 2);
    const define = body[0];
    try expectEqual(define.get(components.AstKind), .define);
    try expectEqualStrings(literalOf(define.get(components.Name).entity), "ptr");
    const cast = define.get(components.Value).entity;
    try expectEqual(cast.get(components.AstKind), .cast);
    const pointer_type = typeOf(cast);
    try expectEqual(parentType(pointer_type), builtins.Ptr);
    try expectEqual(valueType(pointer_type), builtins.I64);
    const zero = cast.get(components.Value).entity;
    try expectEqual(zero.get(components.AstKind), .int);
    try expectEqual(typeOf(zero), builtins.I32);
    try expectEqualStrings(literalOf(zero), "0");
    try expectEqual(valueType(typeOf(define)), builtins.I64);
    const load = body[1];
    try expectEqual(load.get(components.AstKind), .intrinsic);
    try expectEqual(load.get(components.Intrinsic), .load);
    try expectEqual(typeOf(load), builtins.I64);
    const arguments = load.get(components.Arguments).slice();
    try expectEqual(arguments.len, 1);
    const ptr = arguments[0];
    try expectEqual(ptr.get(components.AstKind), .local);
    try expectEqual(ptr.get(components.Local).entity, define);
}

test "analyze semantics of adding *i64 and int literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = fn(): *i64
        \\  ptr = cast(*i64, 0)
        \\  ptr + 1
        \\end
    );
    _ = try analyzeSemantics(codebase, fs, "foo.yeti");
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    const return_type = start.get(components.ReturnType).entity;
    try expectEqual(valueType(return_type), builtins.I64);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 2);
    const define = body[0];
    try expectEqual(define.get(components.AstKind), .define);
    try expectEqualStrings(literalOf(define.get(components.Name).entity), "ptr");
    const cast = define.get(components.Value).entity;
    try expectEqual(cast.get(components.AstKind), .cast);
    const pointer_type = typeOf(cast);
    try expectEqual(parentType(pointer_type), builtins.Ptr);
    try expectEqual(valueType(pointer_type), builtins.I64);
    const zero = cast.get(components.Value).entity;
    try expectEqual(zero.get(components.AstKind), .int);
    try expectEqual(typeOf(zero), builtins.I32);
    try expectEqualStrings(literalOf(zero), "0");
    try expectEqual(valueType(typeOf(define)), builtins.I64);
    const add = body[1];
    try expectEqual(add.get(components.AstKind), .intrinsic);
    try expectEqual(add.get(components.Intrinsic), .add_ptr_i32);
    try expectEqual(typeOf(add), return_type);
}

test "analyze semantics of subtracting *i64 and int literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = fn(): *i64
        \\  ptr = cast(*i64, 0)
        \\  ptr - 1
        \\end
    );
    _ = try analyzeSemantics(codebase, fs, "foo.yeti");
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    const return_type = start.get(components.ReturnType).entity;
    try expectEqual(valueType(return_type), builtins.I64);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 2);
    const define = body[0];
    try expectEqual(define.get(components.AstKind), .define);
    try expectEqualStrings(literalOf(define.get(components.Name).entity), "ptr");
    const cast = define.get(components.Value).entity;
    try expectEqual(cast.get(components.AstKind), .cast);
    const pointer_type = typeOf(cast);
    try expectEqual(parentType(pointer_type), builtins.Ptr);
    try expectEqual(valueType(pointer_type), builtins.I64);
    const zero = cast.get(components.Value).entity;
    try expectEqual(zero.get(components.AstKind), .int);
    try expectEqual(typeOf(zero), builtins.I32);
    try expectEqualStrings(literalOf(zero), "0");
    try expectEqual(valueType(typeOf(define)), builtins.I64);
    const add = body[1];
    try expectEqual(add.get(components.AstKind), .intrinsic);
    try expectEqual(add.get(components.Intrinsic), .subtract_ptr_i32);
    try expectEqual(typeOf(add), return_type);
}

test "analyze semantics of comparing two *i64" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = fn(): i32
        \\  ptr = cast(*i64, 0)
        \\  ptr == ptr
        \\end
    );
    _ = try analyzeSemantics(codebase, fs, "foo.yeti");
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    const return_type = start.get(components.ReturnType).entity;
    try expectEqual(return_type, builtins.I32);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 2);
    const define = body[0];
    try expectEqual(define.get(components.AstKind), .define);
    try expectEqualStrings(literalOf(define.get(components.Name).entity), "ptr");
    const cast = define.get(components.Value).entity;
    try expectEqual(cast.get(components.AstKind), .cast);
    const pointer_type = typeOf(cast);
    try expectEqual(parentType(pointer_type), builtins.Ptr);
    try expectEqual(valueType(pointer_type), builtins.I64);
    const zero = cast.get(components.Value).entity;
    try expectEqual(zero.get(components.AstKind), .int);
    try expectEqual(typeOf(zero), builtins.I32);
    try expectEqualStrings(literalOf(zero), "0");
    try expectEqual(valueType(typeOf(define)), builtins.I64);
    const equal = body[1];
    try expectEqual(equal.get(components.AstKind), .intrinsic);
    try expectEqual(equal.get(components.Intrinsic), .equal);
    try expectEqual(typeOf(equal), builtins.I32);
}

test "analyze semantics of vector load" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = fn(): i64x2
        \\  ptr = cast(*i64x2, 0)
        \\  *ptr
        \\end
    );
    _ = try analyzeSemantics(codebase, fs, "foo.yeti");
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.I64X2);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 2);
    const define = body[0];
    try expectEqual(define.get(components.AstKind), .define);
    try expectEqualStrings(literalOf(define.get(components.Name).entity), "ptr");
    const cast = define.get(components.Value).entity;
    try expectEqual(cast.get(components.AstKind), .cast);
    const pointer_type = typeOf(cast);
    try expectEqual(parentType(pointer_type), builtins.Ptr);
    try expectEqual(valueType(pointer_type), builtins.I64X2);
    const zero = cast.get(components.Value).entity;
    try expectEqual(zero.get(components.AstKind), .int);
    try expectEqual(typeOf(zero), builtins.I32);
    try expectEqualStrings(literalOf(zero), "0");
    try expectEqual(valueType(typeOf(define)), builtins.I64X2);
    const load = body[1];
    try expectEqual(load.get(components.AstKind), .intrinsic);
    try expectEqual(load.get(components.Intrinsic), .v128_load);
    try expectEqual(typeOf(load), builtins.I64X2);
    const arguments = load.get(components.Arguments).slice();
    try expectEqual(arguments.len, 1);
    const ptr = arguments[0];
    try expectEqual(ptr.get(components.AstKind), .local);
    try expectEqual(ptr.get(components.Local).entity, define);
}

test "analyze semantics of binary operators on two int vectors" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const b = codebase.get(components.Builtins);
    const type_strings = [_][]const u8{ "i64x2", "i32x4", "i16x8", "i8x16", "u64x2", "u32x4", "u16x8", "u8x16" };
    const builtins = [_]Entity{ b.I64X2, b.I32X4, b.I16X8, b.I8X16, b.U64X2, b.U32X4, b.U16X8, b.U8X16 };
    const op_strings = [_][]const u8{ "+", "-", "*" };
    const intrinsics = [_]components.Intrinsic{ .add, .subtract, .multiply };
    for (type_strings) |type_string, type_index| {
        for (op_strings) |op_string, i| {
            var fs = try MockFileSystem.init(&arena);
            _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
                \\start = fn(): {s}
                \\  v = *cast(*{s}, 0)
                \\  v {s} v
                \\end
            , .{ type_string, type_string, op_string }));
            _ = try analyzeSemantics(codebase, fs, "foo.yeti");
            const module = try analyzeSemantics(codebase, fs, "foo.yeti");
            const top_level = module.get(components.TopLevel);
            const start = top_level.findString("start").get(components.Overloads).slice()[0];
            try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
            try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
            try expectEqual(start.get(components.Parameters).len(), 0);
            try expectEqual(start.get(components.ReturnType).entity, builtins[type_index]);
            const body = start.get(components.Body).slice();
            try expectEqual(body.len, 2);
            const v = body[0];
            try expectEqual(v.get(components.AstKind), .define);
            try expectEqualStrings(literalOf(v.get(components.Name).entity), "v");
            const load = v.get(components.Value).entity;
            try expectEqual(load.get(components.AstKind), .intrinsic);
            try expectEqual(load.get(components.Intrinsic), .v128_load);
            try expectEqual(typeOf(load), builtins[type_index]);
            const arguments = load.get(components.Arguments).slice();
            try expectEqual(arguments.len, 1);
            const cast = arguments[0];
            try expectEqual(cast.get(components.AstKind), .cast);
            const pointer_type = typeOf(cast);
            try expectEqual(parentType(pointer_type), b.Ptr);
            try expectEqual(valueType(pointer_type), builtins[type_index]);
            const zero = cast.get(components.Value).entity;
            try expectEqual(zero.get(components.AstKind), .int);
            try expectEqual(typeOf(zero), b.I32);
            try expectEqualStrings(literalOf(zero), "0");
            try expectEqual(typeOf(v), builtins[type_index]);
            const intrinsic = body[1];
            try expectEqual(intrinsic.get(components.AstKind), .intrinsic);
            try expectEqual(intrinsic.get(components.Intrinsic), intrinsics[i]);
            try expectEqual(typeOf(intrinsic), builtins[type_index]);
            const intrinsic_arguments = intrinsic.get(components.Arguments).slice();
            try expectEqual(intrinsic_arguments.len, 2);
            const lhs = intrinsic_arguments[0];
            try expectEqual(lhs.get(components.AstKind), .local);
            try expectEqual(lhs.get(components.Local).entity, v);
            const rhs = intrinsic_arguments[1];
            try expectEqual(rhs.get(components.AstKind), .local);
            try expectEqual(rhs.get(components.Local).entity, v);
        }
    }
}

test "analyze semantics of binary operators on two float vectors" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const b = codebase.get(components.Builtins);
    const type_strings = [_][]const u8{ "f64x2", "f32x4" };
    const builtins = [_]Entity{ b.F64X2, b.F32X4 };
    const op_strings = [_][]const u8{ "+", "-", "*", "/" };
    const intrinsics = [_]components.Intrinsic{ .add, .subtract, .multiply, .divide };
    for (type_strings) |type_string, type_index| {
        for (op_strings) |op_string, i| {
            var fs = try MockFileSystem.init(&arena);
            _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
                \\start = fn(): {s}
                \\  v = *cast(*{s}, 0)
                \\  v {s} v
                \\end
            , .{ type_string, type_string, op_string }));
            _ = try analyzeSemantics(codebase, fs, "foo.yeti");
            const module = try analyzeSemantics(codebase, fs, "foo.yeti");
            const top_level = module.get(components.TopLevel);
            const start = top_level.findString("start").get(components.Overloads).slice()[0];
            try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
            try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
            try expectEqual(start.get(components.Parameters).len(), 0);
            try expectEqual(start.get(components.ReturnType).entity, builtins[type_index]);
            const body = start.get(components.Body).slice();
            try expectEqual(body.len, 2);
            const v = body[0];
            try expectEqual(v.get(components.AstKind), .define);
            try expectEqualStrings(literalOf(v.get(components.Name).entity), "v");
            const load = v.get(components.Value).entity;
            try expectEqual(load.get(components.AstKind), .intrinsic);
            try expectEqual(load.get(components.Intrinsic), .v128_load);
            try expectEqual(typeOf(load), builtins[type_index]);
            const arguments = load.get(components.Arguments).slice();
            try expectEqual(arguments.len, 1);
            const cast = arguments[0];
            try expectEqual(cast.get(components.AstKind), .cast);
            const pointer_type = typeOf(cast);
            try expectEqual(parentType(pointer_type), b.Ptr);
            try expectEqual(valueType(pointer_type), builtins[type_index]);
            const zero = cast.get(components.Value).entity;
            try expectEqual(zero.get(components.AstKind), .int);
            try expectEqual(typeOf(zero), b.I32);
            try expectEqualStrings(literalOf(zero), "0");
            try expectEqual(typeOf(v), builtins[type_index]);
            const intrinsic = body[1];
            try expectEqual(intrinsic.get(components.AstKind), .intrinsic);
            try expectEqual(intrinsic.get(components.Intrinsic), intrinsics[i]);
            try expectEqual(typeOf(intrinsic), builtins[type_index]);
            const intrinsic_arguments = intrinsic.get(components.Arguments).slice();
            try expectEqual(intrinsic_arguments.len, 2);
            const lhs = intrinsic_arguments[0];
            try expectEqual(lhs.get(components.AstKind), .local);
            try expectEqual(lhs.get(components.Local).entity, v);
            const rhs = intrinsic_arguments[1];
            try expectEqual(rhs.get(components.AstKind), .local);
            try expectEqual(rhs.get(components.Local).entity, v);
        }
    }
}

test "analyze semantics of vector store" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = fn(): void
        \\  ptr = cast(*i64x2, 0)
        \\  *ptr = *ptr
        \\end
    );
    _ = try analyzeSemantics(codebase, fs, "foo.yeti");
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.Void);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 2);
    const define = body[0];
    try expectEqual(define.get(components.AstKind), .define);
    try expectEqualStrings(literalOf(define.get(components.Name).entity), "ptr");
    const cast = define.get(components.Value).entity;
    try expectEqual(cast.get(components.AstKind), .cast);
    const pointer_type = typeOf(cast);
    try expectEqual(parentType(pointer_type), builtins.Ptr);
    try expectEqual(valueType(pointer_type), builtins.I64X2);
    const zero = cast.get(components.Value).entity;
    try expectEqual(zero.get(components.AstKind), .int);
    try expectEqual(typeOf(zero), builtins.I32);
    try expectEqualStrings(literalOf(zero), "0");
    try expectEqual(valueType(typeOf(define)), builtins.I64X2);
    const store = body[1];
    try expectEqual(store.get(components.AstKind), .intrinsic);
    try expectEqual(store.get(components.Intrinsic), .v128_store);
    try expectEqual(typeOf(store), builtins.Void);
    const arguments = store.get(components.Arguments).slice();
    try expectEqual(arguments.len, 2);
    const ptr = arguments[0];
    try expectEqual(ptr.get(components.AstKind), .local);
    try expectEqual(ptr.get(components.Local).entity, define);
}

test "analyze semantics of struct" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\Rectangle = struct
        \\  width: f64
        \\  height: f64
        \\end
        \\
        \\start = fn(): Rectangle
        \\  Rectangle(10, 30)
        \\end
    );
    _ = try analyzeSemantics(codebase, fs, "foo.yeti");
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    const rectangle = start.get(components.ReturnType).entity;
    try expectEqualStrings(literalOf(rectangle.get(components.Name).entity), "Rectangle");
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 1);
    const construct = body[0];
    try expectEqual(construct.get(components.AstKind), .construct);
    try expectEqual(typeOf(construct), rectangle);
    const arguments = construct.get(components.Arguments).slice();
    try expectEqual(arguments.len, 2);
    try expectEqualStrings(literalOf(arguments[0]), "10");
    try expectEqualStrings(literalOf(arguments[1]), "30");
}

test "analyze semantics of struct field access" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    const builtins = codebase.get(components.Builtins);
    _ = try fs.newFile("foo.yeti",
        \\Rectangle = struct
        \\  width: f64
        \\  height: f64
        \\end
        \\
        \\start = fn(): f64
        \\  r = Rectangle(10, 30)
        \\  r.width
        \\end
    );
    _ = try analyzeSemantics(codebase, fs, "foo.yeti");
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.F64);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 2);
    const define = body[0];
    try expectEqual(define.get(components.AstKind), .define);
    const rectangle = typeOf(define);
    try expectEqualStrings(literalOf(rectangle.get(components.Name).entity), "Rectangle");
    try expectEqualStrings(literalOf(define.get(components.Name).entity), "r");
    const construct = define.get(components.Value).entity;
    try expectEqual(construct.get(components.AstKind), .construct);
    try expectEqual(typeOf(construct), rectangle);
    const arguments = construct.get(components.Arguments).slice();
    try expectEqual(arguments.len, 2);
    try expectEqualStrings(literalOf(arguments[0]), "10");
    try expectEqualStrings(literalOf(arguments[1]), "30");
    const field = body[1];
    try expectEqual(typeOf(field), builtins.F64);
    try expectEqual(field.get(components.Local).entity, define);
    try expectEqualStrings(literalOf(field.get(components.Field).entity), "width");
}

test "analyze semantics of struct field write" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    const builtins = codebase.get(components.Builtins);
    _ = try fs.newFile("foo.yeti",
        \\Rectangle = struct
        \\  width: f64
        \\  height: f64
        \\end
        \\
        \\start = fn(): Rectangle
        \\  r = Rectangle(10, 30)
        \\  r.width = 45
        \\  r
        \\end
    );
    _ = try analyzeSemantics(codebase, fs, "foo.yeti");
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    const rectangle = start.get(components.ReturnType).entity;
    try expectEqualStrings(literalOf(rectangle.get(components.Name).entity), "Rectangle");
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 3);
    const define = body[0];
    try expectEqual(define.get(components.AstKind), .define);
    try expectEqual(typeOf(define), rectangle);
    try expectEqualStrings(literalOf(define.get(components.Name).entity), "r");
    const construct = define.get(components.Value).entity;
    try expectEqual(construct.get(components.AstKind), .construct);
    try expectEqual(typeOf(construct), rectangle);
    const arguments = construct.get(components.Arguments).slice();
    try expectEqual(arguments.len, 2);
    try expectEqualStrings(literalOf(arguments[0]), "10");
    try expectEqualStrings(literalOf(arguments[1]), "30");
    const assign_field = body[1];
    try expectEqual(assign_field.get(components.AstKind), .assign_field);
    try expectEqual(typeOf(assign_field), builtins.Void);
    try expectEqual(assign_field.get(components.Local).entity, define);
    try expectEqualStrings(literalOf(assign_field.get(components.Field).entity), "width");
    try expectEqualStrings(literalOf(assign_field.get(components.Value).entity), "45");
    const local = body[2];
    try expectEqual(local.get(components.AstKind), .local);
}
