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

        fn implicitlyConvertibleTo(self: *Self, to: Entity, from: Entity) Match {
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
            assert(self.implicitlyConvertibleTo(expected_type, actual_type) != .no);
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
                return local;
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
                    else => panic("\nlowerSumbol unspported top level kind {}\n", .{kind}),
                }
            }
            panic("\nlowerSymbol failed for symbol {s}\n", .{literalOf(entity)});
        }

        fn bestOverload(self: *Self, callable: Entity, arguments: []const Entity) !Entity {
            const top_level = self.module.get(components.TopLevel);
            const literal = callable.get(components.Literal);
            var best_overload: Entity = undefined;
            var best_match = Match.no;
            for (top_level.findLiteral(literal).get(components.Overloads).slice()) |overload| {
                if (!overload.contains(components.LoweredParameters)) {
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
                    switch (self.implicitlyConvertibleTo(parameter_type, argument_type)) {
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
            if (!overload.contains(components.LoweredBody)) {
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

        fn analyzeBinaryOp(self: *Self, entity: Entity) !Entity {
            const binary_op = entity.get(components.BinaryOp);
            return try switch (binary_op) {
                .dot => self.analyzeDot(entity),
                else => panic("\nanalyze binary op unsupported {}\n", .{binary_op}),
            };
        }

        fn analyzeExpression(self: *Self, entity: Entity) error{ Overflow, InvalidCharacter, OutOfMemory, CantOpenFile, CannotUnifyTypes }!Entity {
            const kind = entity.get(components.AstKind);
            return switch (kind) {
                .symbol => try self.analyzeSymbol(entity),
                .int, .float => entity,
                .call => try self.analyzeCall(entity),
                .binary_op => try self.analyzeBinaryOp(entity),
                else => panic("\nlowerExpression unsupported kind {}\n", .{kind}),
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
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(&arena.allocator,
            \\start = function(): {s}
            \\  5
            \\end
        , .{type_}));
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
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(&arena.allocator,
            \\start = function(): {s}
            \\  5.3
            \\end
        , .{type_}));
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
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(&arena.allocator,
            \\start = function(): {s}
            \\  baz()
            \\end
            \\
            \\baz = function(): {s}
            \\  10
            \\end
        , .{ type_, type_ }));
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
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(&arena.allocator,
            \\bar = import("bar.yeti")
            \\
            \\start = function(): {s}
            \\  bar.baz()
            \\end
        , .{type_}));
        _ = try fs.newFile("bar.yeti", try std.fmt.allocPrint(&arena.allocator,
            \\baz = function(): {s}
            \\  10
            \\end
        , .{type_}));
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
    const types = [_][]const u8{ "F64", "F32" };
    const builtin_types = [_]Entity{ builtins.F64, builtins.F32 };
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(&arena.allocator,
            \\start = function(): {s}
            \\  x = 10
            \\  x
            \\end
        , .{type_}));
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
