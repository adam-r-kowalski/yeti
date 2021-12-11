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

fn Context(comptime FileSystem: type) type {
    return struct {
        allocator: *Allocator,
        codebase: *ECS,
        file_system: FileSystem,
        module: Entity,
        function: Entity,
        active_scopes: []const u64,
        builtins: *const components.Builtins,

        const Self = @This();

        const Match = enum {
            no,
            implict_conversion,
            exact,
        };

        fn convertibleTo(self: *Self, to: Entity, from: Entity) Match {
            if (eql(to, from)) return .exact;
            const b = self.builtins;
            const builtins = [_]Entity{ b.I64, b.I32, b.U64, b.U32, b.F64, b.F32 };
            const float_builtins = [_]Entity{ b.F64, b.F32 };
            if (eql(from, b.IntLiteral)) {
                for (builtins) |builtin| {
                    if (eql(to, builtin)) return .implict_conversion;
                }
                return .no;
            }
            if (eql(from, b.FloatLiteral)) {
                for (float_builtins) |builtin| {
                    if (eql(to, builtin)) return .implict_conversion;
                }
                return .no;
            }
            return .no;
        }

        fn implicitTypeConversion(self: *Self, value: Entity, expected_type: Entity) error{OutOfMemory}!void {
            const actual_type = typeOf(value);
            assert(self.convertibleTo(expected_type, actual_type) != .no);
            _ = try value.set(.{components.Type.init(expected_type)});
            if (value.has(components.DependentEntities)) |dependent_entities| {
                for (dependent_entities.slice()) |entity| {
                    try self.implicitTypeConversion(entity, expected_type);
                }
            }
        }

        fn analyzeSymbol(self: *Self, entity: Entity) !Entity {
            const literal = entity.get(components.Literal);
            const scopes = self.function.get(components.Scopes);
            if (scopes.hasLiteral(literal)) |local| {
                return try self.codebase.createEntity(.{
                    components.AstKind.local,
                    components.Local.init(local),
                    local.get(components.Type),
                    try components.DependentEntities.fromSlice(self.allocator, &.{local}),
                });
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
                        // TODO: Don't reparse the module every time. Cache them based on path
                        const module_name = literalOf(top_level.get(components.Path).entity);
                        const contents = try self.file_system.read(module_name);
                        const module = try self.codebase.createEntity(.{});
                        var tokens = try tokenize(module, contents);
                        try parse(module, &tokens);
                        const interned = try self.codebase.getPtr(Strings).intern(module_name[0 .. module_name.len - 5]);
                        _ = try module.set(.{components.Literal.init(interned)});
                        return module;
                    },
                    else => panic("\nanalyzeSumbol unspported top level kind {}\n", .{kind}),
                }
            }
            panic("\nanalyzeSymbol failed for symbol {s}\n", .{literalOf(entity)});
        }

        fn bestOverload(self: *Self, callable: Entity, arguments: []const Entity) !Entity {
            const top_level = self.module.get(components.TopLevel);
            const literal = callable.get(components.Literal);
            var best_overload: Entity = undefined;
            var best_match = Match.no;
            for (top_level.findLiteral(literal).get(components.Overloads).slice()) |overload| {
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
                        .implict_conversion => if (match == .exact) {
                            match = .implict_conversion;
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
            assert(best_match != .no);
            return best_overload;
        }

        fn analyzeCall(self: *Self, call: Entity) !Entity {
            const callable = call.get(components.Callable).entity;
            const call_arguments = call.get(components.Arguments).slice();
            var analyzed_arguments = try components.Arguments.withCapacity(self.allocator, call_arguments.len);
            for (call_arguments) |argument| {
                analyzed_arguments.appendAssumeCapacity(try self.analyzeExpression(argument));
            }
            const overload = try self.bestOverload(callable, analyzed_arguments.slice());
            if (!overload.contains(components.AnalyzedBody)) {
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

        fn analyzeDot(self: *Self, entity: Entity) !Entity {
            const dot_arguments = entity.get(components.Arguments).slice();
            const module = try self.analyzeExpression(dot_arguments[0]);
            assert(eql(typeOf(module), self.codebase.get(components.Builtins).Module));
            const call = dot_arguments[1];
            assert(call.get(components.AstKind) == .call);
            var context = Self{
                .allocator = self.allocator,
                .codebase = self.codebase,
                .file_system = self.file_system,
                .module = module,
                .function = self.function,
                .active_scopes = self.active_scopes,
                .builtins = self.builtins,
            };
            return try context.analyzeCall(call);
        }

        fn analyzeIntrinsic(self: *Self, entity: Entity, intrinsic: components.Intrinsic, result_is_i32: bool) !Entity {
            const arguments = entity.get(components.Arguments).slice();
            const lhs = try self.analyzeExpression(arguments[0]);
            const rhs = try self.analyzeExpression(arguments[1]);
            const lhs_type = typeOf(lhs);
            const rhs_type = typeOf(rhs);
            const b = self.builtins;
            const builtins = &[_]Entity{ b.I64, b.I32, b.U64, b.U32, b.F64, b.F32, b.IntLiteral, b.FloatLiteral };
            for (builtins) |builtin| {
                if (!eql(lhs_type, builtin)) continue;
                assert(self.convertibleTo(lhs_type, rhs_type) != .no);
                _ = try rhs.set(.{components.Type.init(lhs_type)});
                const type_of = components.Type.init(if (result_is_i32) b.I32 else lhs_type);
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
            const scopes = self.function.getPtr(components.Scopes);
            const value = try self.analyzeExpression(define.get(components.Value).entity);
            if (define.has(components.TypeAst)) |type_ast| {
                const explicit_type = try analyzeExpression(self, type_ast.entity);
                try self.implicitTypeConversion(value, explicit_type);
            }
            const name = define.get(components.Name);
            const analyzed_define = try self.codebase.createEntity(.{
                components.AstKind.define,
                components.Value.init(value),
                name,
                value.get(components.Type),
            });
            try scopes.putName(name, analyzed_define);
            return analyzed_define;
        }

        fn analyzeIf(self: *Self, if_: Entity) !Entity {
            const scopes = self.function.getPtr(components.Scopes);
            const conditional = try self.analyzeExpression(if_.get(components.Conditional).entity);
            try self.implicitTypeConversion(conditional, self.builtins.I32);
            const active_scopes = self.active_scopes;
            const then = if_.get(components.Then).slice();
            assert(then.len > 0);
            var then_entity: Entity = undefined;
            const then_scopes = try self.allocator.alloc(u64, active_scopes.len + 1);
            std.mem.copy(u64, then_scopes, active_scopes);
            then_scopes[active_scopes.len] = try scopes.pushScope();
            self.active_scopes = then_scopes;
            for (then) |entity| {
                then_entity = try self.analyzeExpression(entity);
            }
            const else_ = if_.get(components.Else).slice();
            assert(else_.len > 0);
            var else_entity: Entity = undefined;
            const else_scopes = try self.allocator.alloc(u64, active_scopes.len + 1);
            std.mem.copy(u64, else_scopes, active_scopes);
            else_scopes[active_scopes.len] = try scopes.pushScope();
            self.active_scopes = else_scopes;
            for (else_) |entity| {
                else_entity = try self.analyzeExpression(entity);
            }
            const type_of = typeOf(then_entity);
            assert(eql(type_of, typeOf(else_entity)));
            _ = try if_.set(.{components.Type.init(type_of)});
            if (eql(type_of, self.builtins.IntLiteral) or eql(type_of, self.builtins.FloatLiteral)) {
                _ = try if_.set(.{
                    try components.DependentEntities.fromSlice(self.allocator, &.{ then_entity, else_entity }),
                });
            }
            const finally_scopes = try self.allocator.alloc(u64, active_scopes.len + 1);
            std.mem.copy(u64, finally_scopes, active_scopes);
            finally_scopes[active_scopes.len] = try scopes.pushScope();
            self.active_scopes = finally_scopes;
            return if_;
        }

        fn analyzeExpression(self: *Self, entity: Entity) error{ Overflow, InvalidCharacter, OutOfMemory, CantOpenFile, CannotUnifyTypes }!Entity {
            const kind = entity.get(components.AstKind);
            return switch (kind) {
                .symbol => try self.analyzeSymbol(entity),
                .int, .float => entity,
                .call => try self.analyzeCall(entity),
                .binary_op => try self.analyzeBinaryOp(entity),
                .define => try self.analyzeDefine(entity),
                .if_ => try self.analyzeIf(entity),
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

        fn analyzeFunctionBody(self: *Self) !Entity {
            var analyzed_body = components.AnalyzedBody.init(self.allocator);
            const body = self.function.get(components.Body).slice();
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
            _ = try self.codebase.getPtr(components.Functions).append(self.function);
            if (!self.function.contains(components.AnalyzedParameters)) {
                try self.analyzeFunctionParameters();
            }
            const return_type = try self.analyzeFunctionReturnType();
            const return_entity = try self.analyzeFunctionBody();
            try self.implicitTypeConversion(return_entity, return_type);
        }
    };
}

pub fn analyzeSemantics(codebase: *ECS, file_system: anytype, module_name: []const u8, function_name: []const u8) !Entity {
    _ = try codebase.set(.{components.Functions.init(&codebase.arena.allocator)});
    const contents = try file_system.read(module_name);
    const module = try codebase.createEntity(.{});
    var tokens = try tokenize(module, contents);
    try parse(module, &tokens);
    const interned = try codebase.getPtr(Strings).intern(module_name[0 .. module_name.len - 5]);
    _ = try module.set(.{components.Literal.init(interned)});
    const top_level = module.get(components.TopLevel);
    const overloads = top_level.findString(function_name).get(components.Overloads).slice();
    assert(overloads.len == 1);
    const allocator = &codebase.arena.allocator;
    var scopes = components.Scopes.init(allocator, codebase.getPtr(Strings));
    const scope = try scopes.pushScope();
    const function = overloads[0];
    _ = try function.set(.{scopes});
    const active_scopes = [_]u64{scope};
    var context = Context(@TypeOf(file_system)){
        .allocator = allocator,
        .codebase = codebase,
        .file_system = file_system,
        .module = module,
        .function = function,
        .active_scopes = &active_scopes,
        .builtins = codebase.getPtr(components.Builtins),
    };
    try context.analyzeFunction();
    return module;
}

test "analyze semantics int literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    const types = [_][]const u8{ "I64", "I32", "U64", "U32", "F64", "F32" };
    const builtin_types = [_]Entity{ builtins.I64, builtins.I32, builtins.U64, builtins.U32, builtins.F64, builtins.F32 };
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(&arena.allocator,
            \\start = function(): {s}
            \\  5
            \\end
        , .{type_of}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti", "start");
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
        try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
        try expectEqual(start.get(components.Parameters).len(), 0);
        try expectEqual(start.get(components.ReturnType).entity, builtin_types[i]);
        const body = start.get(components.AnalyzedBody).slice();
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
    const types = [_][]const u8{ "F64", "F32" };
    const builtin_types = [_]Entity{ builtins.F64, builtins.F32 };
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(&arena.allocator,
            \\start = function(): {s}
            \\  5.3
            \\end
        , .{type_of}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti", "start");
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
        try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
        try expectEqual(start.get(components.Parameters).len(), 0);
        try expectEqual(start.get(components.ReturnType).entity, builtin_types[i]);
        const body = start.get(components.AnalyzedBody).slice();
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
    const types = [_][]const u8{ "I64", "I32", "U64", "U32", "F64", "F32" };
    const builtin_types = [_]Entity{ builtins.I64, builtins.I32, builtins.U64, builtins.U32, builtins.F64, builtins.F32 };
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(&arena.allocator,
            \\start = function(): {s}
            \\  baz()
            \\end
            \\
            \\baz = function(): {s}
            \\  10
            \\end
        , .{ type_of, type_of }));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti", "start");
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
        try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
        try expectEqual(start.get(components.Parameters).len(), 0);
        try expectEqual(start.get(components.ReturnType).entity, builtin_types[i]);
        const baz = blk: {
            const body = start.get(components.AnalyzedBody).slice();
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
        const body = baz.get(components.AnalyzedBody).slice();
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
    const types = [_][]const u8{ "I64", "I32", "U64", "U32", "F64", "F32" };
    const builtin_types = [_]Entity{ builtins.I64, builtins.I32, builtins.U64, builtins.U32, builtins.F64, builtins.F32 };
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(&arena.allocator,
            \\bar = import("bar.yeti")
            \\
            \\start = function(): {s}
            \\  bar.baz()
            \\end
        , .{type_of}));
        _ = try fs.newFile("bar.yeti", try std.fmt.allocPrint(&arena.allocator,
            \\baz = function(): {s}
            \\  10
            \\end
        , .{type_of}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti", "start");
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
        try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
        try expectEqual(start.get(components.Parameters).len(), 0);
        try expectEqual(start.get(components.ReturnType).entity, builtin_types[i]);
        const baz = blk: {
            const body = start.get(components.AnalyzedBody).slice();
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
        const body = baz.get(components.AnalyzedBody).slice();
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
    const types = [_][]const u8{ "I64", "I32", "U64", "U32", "F64", "F32" };
    const builtin_types = [_]Entity{ builtins.I64, builtins.I32, builtins.U64, builtins.U32, builtins.F64, builtins.F32 };
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(&arena.allocator,
            \\start = function(): {s}
            \\  x = 10
            \\  x
            \\end
        , .{type_of}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti", "start");
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
        try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
        try expectEqual(start.get(components.Parameters).len(), 0);
        try expectEqual(start.get(components.ReturnType).entity, builtin_types[i]);
        const body = start.get(components.AnalyzedBody).slice();
        try expectEqual(body.len, 2);
        const define = body[0];
        try expectEqual(define.get(components.AstKind), .define);
        try expectEqual(typeOf(define), builtin_types[i]);
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
    const types = [_][]const u8{ "F64", "F32" };
    const builtin_types = [_]Entity{ builtins.F64, builtins.F32 };
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(&arena.allocator,
            \\start = function(): {s}
            \\  x = 10
            \\  y = 15
            \\  x
            \\end
        , .{type_of}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti", "start");
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
        try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
        try expectEqual(start.get(components.Parameters).len(), 0);
        try expectEqual(start.get(components.ReturnType).entity, builtin_types[i]);
        const body = start.get(components.AnalyzedBody).slice();
        try expectEqual(body.len, 3);
        const x = body[0];
        try expectEqual(x.get(components.AstKind), .define);
        try expectEqual(typeOf(x), builtin_types[i]);
        try expectEqualStrings(literalOf(x.get(components.Name).entity), "x");
        try expectEqualStrings(literalOf(x.get(components.Value).entity), "10");
        const y = body[1];
        try expectEqual(y.get(components.AstKind), .define);
        try expectEqual(typeOf(y), builtins.IntLiteral);
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
    const types = [_][]const u8{ "F64", "F32" };
    const builtin_types = [_]Entity{ builtins.F64, builtins.F32 };
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(&arena.allocator,
            \\start = function(): {s}
            \\  x: {s} = 10
            \\  x
            \\end
        , .{ type_of, type_of }));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti", "start");
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
        try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
        try expectEqual(start.get(components.Parameters).len(), 0);
        try expectEqual(start.get(components.ReturnType).entity, builtin_types[i]);
        const body = start.get(components.AnalyzedBody).slice();
        try expectEqual(body.len, 2);
        const define = body[0];
        try expectEqual(define.get(components.AstKind), .define);
        try expectEqual(typeOf(define), builtin_types[i]);
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
    const types = [_][]const u8{ "I64", "I32", "U64", "U32", "F64", "F32" };
    const builtin_types = [_]Entity{ builtins.I64, builtins.I32, builtins.U64, builtins.U32, builtins.F64, builtins.F32 };
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(&arena.allocator,
            \\start = function(): {s}
            \\  x: {s} = 10
            \\  id(x)
            \\end
            \\
            \\id = function(x: {s}): {s}
            \\  x
            \\end
        , .{ type_of, type_of, type_of, type_of }));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti", "start");
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
        try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
        try expectEqual(start.get(components.Parameters).len(), 0);
        try expectEqual(start.get(components.ReturnType).entity, builtin_types[i]);
        const id = blk: {
            const body = start.get(components.AnalyzedBody).slice();
            try expectEqual(body.len, 2);
            const define = body[0];
            try expectEqual(define.get(components.AstKind), .define);
            try expectEqual(typeOf(define), builtin_types[i]);
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
        const body = id.get(components.AnalyzedBody).slice();
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
    const types = [_][]const u8{ "I64", "I32", "U64", "U32", "F64", "F32" };
    const builtin_types = [_]Entity{ builtins.I64, builtins.I32, builtins.U64, builtins.U32, builtins.F64, builtins.F32 };
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(&arena.allocator,
            \\start = function(): {s}
            \\  x = id(10)
            \\  id(25)
            \\end
            \\
            \\id = function(x: {s}): {s}
            \\  x
            \\end
        , .{ type_of, type_of, type_of }));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti", "start");
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
        try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
        try expectEqual(start.get(components.Parameters).len(), 0);
        try expectEqual(start.get(components.ReturnType).entity, builtin_types[i]);
        const start_body = start.get(components.AnalyzedBody).slice();
        try expectEqual(start_body.len, 2);
        const id = blk: {
            const define = start_body[0];
            try expectEqual(define.get(components.AstKind), .define);
            try expectEqual(typeOf(define), builtin_types[i]);
            try expectEqualStrings(literalOf(define.get(components.Name).entity), "x");
            const call = define.get(components.Value).entity;
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
        const body = id.get(components.AnalyzedBody).slice();
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
    const types = [_][]const u8{ "I64", "I32", "U64", "U32", "F64", "F32" };
    const builtin_types = [_]Entity{ builtins.I64, builtins.I32, builtins.U64, builtins.U32, builtins.F64, builtins.F32 };
    const op_strings = [_][]const u8{ "+", "-", "*", "/" };
    const intrinsics = [_]components.Intrinsic{ .add, .subtract, .multiply, .divide };
    for (op_strings) |op_string, op_index| {
        for (types) |type_of, i| {
            var fs = try MockFileSystem.init(&arena);
            _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(&arena.allocator,
                \\start = function(): {s}
                \\  x: {s} = 10
                \\  y: {s} = 32
                \\  x {s} y
                \\end
            , .{ type_of, type_of, type_of, op_string }));
            const module = try analyzeSemantics(codebase, fs, "foo.yeti", "start");
            const top_level = module.get(components.TopLevel);
            const start = top_level.findString("start").get(components.Overloads).slice()[0];
            try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
            try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
            try expectEqual(start.get(components.Parameters).len(), 0);
            try expectEqual(start.get(components.ReturnType).entity, builtin_types[i]);
            const body = start.get(components.AnalyzedBody).slice();
            try expectEqual(body.len, 3);
            const x = body[0];
            try expectEqual(x.get(components.AstKind), .define);
            try expectEqual(typeOf(x), builtin_types[i]);
            try expectEqualStrings(literalOf(x.get(components.Name).entity), "x");
            try expectEqualStrings(literalOf(x.get(components.Value).entity), "10");
            const y = body[1];
            try expectEqual(y.get(components.AstKind), .define);
            try expectEqual(typeOf(y), builtin_types[i]);
            try expectEqualStrings(literalOf(y.get(components.Name).entity), "y");
            try expectEqualStrings(literalOf(y.get(components.Value).entity), "32");
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
    const types = [_][]const u8{ "I64", "I32", "U64", "U32", "F64", "F32" };
    const builtin_types = [_]Entity{ builtins.I64, builtins.I32, builtins.U64, builtins.U32, builtins.F64, builtins.F32 };
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
            _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(&arena.allocator,
                \\start = function(): I32
                \\  x: {s} = 10
                \\  y: {s} = 32
                \\  x {s} y
                \\end
            , .{ type_of, type_of, op_string }));
            const module = try analyzeSemantics(codebase, fs, "foo.yeti", "start");
            const top_level = module.get(components.TopLevel);
            const start = top_level.findString("start").get(components.Overloads).slice()[0];
            try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
            try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
            try expectEqual(start.get(components.Parameters).len(), 0);
            try expectEqual(start.get(components.ReturnType).entity, builtins.I32);
            const body = start.get(components.AnalyzedBody).slice();
            try expectEqual(body.len, 3);
            const x = body[0];
            try expectEqual(x.get(components.AstKind), .define);
            try expectEqual(typeOf(x), builtin_types[i]);
            try expectEqualStrings(literalOf(x.get(components.Name).entity), "x");
            try expectEqualStrings(literalOf(x.get(components.Value).entity), "10");
            const y = body[1];
            try expectEqual(y.get(components.AstKind), .define);
            try expectEqual(typeOf(y), builtin_types[i]);
            try expectEqualStrings(literalOf(y.get(components.Name).entity), "y");
            try expectEqualStrings(literalOf(y.get(components.Value).entity), "32");
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
    const types = [_][]const u8{"I64"};
    const builtin_types = [_]Entity{builtins.I64};
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(&arena.allocator,
            \\start = function(): {s}
            \\  if 1 then 20 else 30 end
            \\end
        , .{type_of}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti", "start");
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
        try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
        try expectEqual(start.get(components.Parameters).len(), 0);
        try expectEqual(start.get(components.ReturnType).entity, builtin_types[i]);
        const body = start.get(components.AnalyzedBody).slice();
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
