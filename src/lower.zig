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
        basic_block: Entity,

        const Self = @This();

        fn lowerSymbol(self: Self, entity: Entity) !Entity {
            const literal = entity.get(components.Literal);
            const local_scope = self.basic_block.get(components.Scope);
            if (local_scope.hasLiteral(literal)) |local| {
                const instructions = self.basic_block.getPtr(components.IrInstructions);
                const instruction = try self.codebase.createEntity(.{
                    components.IrInstructionKind.get_local,
                    components.Result.init(local),
                });
                try instructions.append(instruction);
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

        fn lowerNumber(self: Self, entity: Entity, kind: components.IrInstructionKind) !Entity {
            const instructions = self.basic_block.getPtr(components.IrInstructions);
            const instruction = try self.codebase.createEntity(.{
                kind,
                components.Result.init(entity),
            });
            try instructions.append(instruction);
            return entity;
        }

        fn lowerDot(self: Self, entity: Entity) !Entity {
            const dot_arguments = entity.get(components.Arguments).slice();
            const module = try self.lowerExpression(dot_arguments[0]);
            assert(eql(typeOf(module), self.codebase.get(components.Builtins).Module));
            const call = dot_arguments[1];
            assert(call.get(components.AstKind) == .call);
            const context = Self{
                .allocator = self.allocator,
                .codebase = self.codebase,
                .file_system = self.file_system,
                .module = module,
                .function = self.function,
                .basic_block = self.basic_block,
            };
            return try context.lowerCall(call);
        }

        fn lowerAddSameType(self: Self, result_type: Entity) !Entity {
            const result = try self.codebase.createEntity(.{components.Type.init(result_type)});
            const instructions = self.basic_block.getPtr(components.IrInstructions);
            const instruction = try self.codebase.createEntity(.{
                components.IrInstructionKind.int_add,
                components.Result.init(result),
            });
            try instructions.append(instruction);
            return result;
        }

        fn i64Of(entity: Entity) !i64 {
            if (entity.has(i64)) |cached| {
                return cached;
            } else {
                const literal = literalOf(entity);
                const value = try std.fmt.parseInt(i64, literal, 10);
                _ = try entity.set(.{value});
                return value;
            }
        }

        fn lowerAdd(self: Self, entity: Entity) !Entity {
            const builtins = self.codebase.get(components.Builtins);
            const arguments = entity.get(components.Arguments).slice();
            const lhs = try self.lowerExpression(arguments[0]);
            const rhs = try self.lowerExpression(arguments[1]);
            const lhs_type = typeOf(lhs);
            const rhs_type = typeOf(rhs);
            if (eql(lhs_type, builtins.I64)) {
                if (eql(rhs_type, builtins.I64)) {
                    return try self.lowerAddSameType(builtins.I64);
                }
                if (eql(rhs_type, builtins.IntLiteral)) {
                    _ = try rhs.set(.{components.Type.init(builtins.I64)});
                    return try self.lowerAddSameType(builtins.I64);
                }
                panic("\nlower {s} + {s} not implemented\n", .{
                    literalOf(lhs_type), literalOf(rhs_type),
                });
            }
            if (eql(lhs_type, builtins.U64)) {
                if (eql(rhs_type, builtins.U64)) {
                    return try self.lowerAddSameType(builtins.U64);
                }
                if (eql(rhs_type, builtins.IntLiteral)) {
                    _ = try rhs.set(.{components.Type.init(builtins.U64)});
                    return try self.lowerAddSameType(builtins.U64);
                }
                panic("\nlower {s} + {s} not implemented\n", .{
                    literalOf(lhs_type), literalOf(rhs_type),
                });
            }
            if (eql(lhs_type, builtins.IntLiteral)) {
                if (eql(rhs_type, builtins.I64)) {
                    _ = try lhs.set(.{components.Type.init(builtins.I64)});
                    return try self.lowerAddSameType(builtins.I64);
                }
                if (eql(rhs_type, builtins.U64)) {
                    _ = try lhs.set(.{components.Type.init(builtins.U64)});
                    return try self.lowerAddSameType(builtins.U64);
                }
                assert(eql(rhs_type, builtins.IntLiteral));

                const lhs_value = try i64Of(lhs);
                const rhs_value = try i64Of(rhs);
                const result_value = lhs_value + rhs_value;
                const result_literal = try std.fmt.allocPrint(self.allocator, "{}", .{result_value});
                const interned = try self.codebase.getPtr(Strings).intern(result_literal);
                const result = try self.codebase.createEntity(.{
                    components.Literal.init(interned),
                    components.Type.init(builtins.IntLiteral),
                    result_value,
                });
                const instructions = self.basic_block.getPtr(components.IrInstructions);
                const instruction = try self.codebase.createEntity(.{
                    components.IrInstructionKind.int_const,
                    components.Result.init(result),
                });
                try instructions.append(instruction);
                return result;
            }
            panic("\nlower add failed\n", .{});
        }

        fn lowerBinaryOp(self: Self, entity: Entity) !Entity {
            const binary_op = entity.get(components.BinaryOp);
            return try switch (binary_op) {
                .dot => self.lowerDot(entity),
                .add => self.lowerAdd(entity),
                else => panic("\nlowerBinaryOp unsupported binary op {}\n", .{binary_op}),
            };
        }

        const Match = enum {
            none,
            implict_conversion,
            exact,
        };

        fn bestOverload(self: Self, callable: Entity, arguments: []const Entity) !Entity {
            const top_level = self.module.get(components.TopLevel);
            const literal = callable.get(components.Literal);
            var best_overload: Entity = undefined;
            var best_match = Match.none;
            const builtins = self.codebase.get(components.Builtins);
            for (top_level.findLiteral(literal).get(components.Overloads).slice()) |overload| {
                var basic_blocks = components.BasicBlocks.init(self.allocator);
                const basic_block = try self.codebase.createEntity(.{
                    components.IrInstructions.init(self.allocator),
                    components.Scope.init(self.allocator, self.codebase.getPtr(Strings)),
                });
                _ = try basic_blocks.append(basic_block);
                _ = try overload.set(.{basic_blocks});
                const context = Self{
                    .allocator = self.allocator,
                    .codebase = self.codebase,
                    .file_system = self.file_system,
                    .module = self.module,
                    .function = overload,
                    .basic_block = basic_block,
                };
                try context.lowerFunctionParameters();
                const parameters = overload.get(components.Parameters).slice();
                if (parameters.len != arguments.len) continue;
                var match = Match.exact;
                for (parameters) |parameter, i| {
                    const parameter_type = typeOf(parameter);
                    const argument_type = typeOf(arguments[i]);
                    if (eql(parameter_type, argument_type)) continue;
                    if (eql(argument_type, builtins.IntLiteral)) {
                        if (eql(parameter_type, builtins.I64) or eql(parameter_type, builtins.U64)) {
                            if (best_match == .none) {
                                best_match = .implict_conversion;
                            }
                        }
                    } else {
                        match = .none;
                        break;
                    }
                }
                if (@enumToInt(match) < @enumToInt(best_match)) continue;
                if (match != .none and match == best_match) {
                    panic("ambiguous overload set overload match {} best match {}", .{ match, best_match });
                }
                best_match = match;
                best_overload = overload;
            }
            assert(best_match != .none);
            return best_overload;
        }

        fn lowerCall(self: Self, call: Entity) !Entity {
            const callable = call.get(components.Callable).entity;
            const call_arguments = call.get(components.Arguments).slice();
            var function_arguments = try components.Arguments.withCapacity(self.allocator, call_arguments.len);
            for (call_arguments) |argument| {
                function_arguments.appendAssumeCapacity(try self.lowerExpression(argument));
            }
            const function = try self.bestOverload(callable, function_arguments.slice());
            {
                const context = Self{
                    .allocator = self.allocator,
                    .codebase = self.codebase,
                    .file_system = self.file_system,
                    .module = self.module,
                    .function = function,
                    .basic_block = function.get(components.BasicBlocks).slice()[0],
                };
                try context.lowerFunction();
            }
            const function_parameters = function.get(components.Parameters).slice();
            for (function_arguments.slice()) |argument, i| {
                try implicitTypeConversion(argument, typeOf(function_parameters[i]));
            }
            const return_type = function.get(components.ReturnType).entity;
            const result = try self.codebase.createEntity(.{components.Type.init(return_type)});
            const instructions = self.basic_block.getPtr(components.IrInstructions);
            const instruction = try self.codebase.createEntity(.{
                components.IrInstructionKind.call,
                components.Callable.init(function),
                function_arguments,
                components.Result.init(result),
            });
            try instructions.append(instruction);
            return result;
        }

        fn implicitTypeConversion(value: Entity, expected_type: Entity) !void {
            const actual_type = typeOf(value);
            const builtins = value.ecs.get(components.Builtins);
            if (eql(actual_type, builtins.IntLiteral)) {
                if (eql(expected_type, builtins.I64) or eql(expected_type, builtins.U64) or eql(expected_type, builtins.F64)) {
                    _ = try value.set(.{components.Type.init(expected_type)});
                } else {
                    panic("\ncannot implicitly convert {s} to {s}\n", .{
                        literalOf(actual_type),
                        literalOf(expected_type),
                    });
                }
            } else if (eql(actual_type, builtins.FloatLiteral)) {
                if (eql(expected_type, builtins.F64)) {
                    _ = try value.set(.{components.Type.init(expected_type)});
                } else {
                    panic("\ncannot implicitly convert {s} to {s}\n", .{
                        literalOf(actual_type),
                        literalOf(expected_type),
                    });
                }
            } else {
                assert(eql(expected_type, actual_type));
            }
        }

        fn lowerDefine(self: Self, define: Entity) !Entity {
            const scope = self.basic_block.getPtr(components.Scope);
            const value = try self.lowerExpression(define.get(components.Value).entity);
            if (define.has(components.TypeAst)) |type_ast| {
                const explicit_type = try lowerExpression(self, type_ast.entity);
                try implicitTypeConversion(value, explicit_type);
            }
            const instructions = self.basic_block.getPtr(components.IrInstructions);
            const instruction = try self.codebase.createEntity(.{
                components.IrInstructionKind.set_local,
                components.Result.init(value),
            });
            try instructions.append(instruction);
            const name = define.get(components.Name);
            _ = try value.set(.{name});
            try scope.putName(name, value);
            return self.codebase.get(components.Builtins).Void;
        }

        fn lowerExpression(self: Self, entity: Entity) error{ Overflow, InvalidCharacter, OutOfMemory, CantOpenFile }!Entity {
            const kind = entity.get(components.AstKind);
            return switch (kind) {
                .symbol => try self.lowerSymbol(entity),
                .int => try self.lowerNumber(entity, .int_const),
                .float => try self.lowerNumber(entity, .float_const),
                .binary_op => try self.lowerBinaryOp(entity),
                .call => try self.lowerCall(entity),
                .define => try self.lowerDefine(entity),
                else => panic("\nlowerExpression unsupported kind {}\n", .{kind}),
            };
        }

        fn lowerFunctionParameters(self: Self) !void {
            if (self.function.has(components.LoweredParameters) != null) return;
            const scope = self.basic_block.getPtr(components.Scope);
            const parameters = self.function.get(components.Parameters).slice();
            for (parameters) |parameter| {
                const parameter_type = try lowerExpression(self, parameter.get(components.TypeAst).entity);
                _ = try parameter.set(.{
                    components.Type.init(parameter_type),
                    components.Name.init(parameter),
                });
                try scope.putLiteral(parameter.get(components.Literal), parameter);
            }
            _ = try self.function.set(.{components.LoweredParameters{ .value = true }});
        }

        fn lowerFunctionReturnType(self: Self) !Entity {
            const return_type = try self.lowerExpression(self.function.get(components.ReturnTypeAst).entity);
            _ = try self.function.set(.{components.ReturnType.init(return_type)});
            return return_type;
        }

        fn lowerFunctionBody(self: Self) !Entity {
            const body = self.function.get(components.Body).slice();
            var return_entity: Entity = undefined;
            for (body) |expression| {
                return_entity = try self.lowerExpression(expression);
            }
            return return_entity;
        }

        fn lowerFunction(self: Self) !void {
            _ = try self.function.set(.{components.Module.init(self.module)});
            _ = try self.codebase.getPtr(components.Functions).append(self.function);
            try self.lowerFunctionParameters();
            const return_type = try self.lowerFunctionReturnType();
            const return_entity = try self.lowerFunctionBody();
            try implicitTypeConversion(return_entity, return_type);
        }
    };
}

pub fn lower(codebase: *ECS, file_system: anytype, module_name: []const u8, function_name: []const u8) !Entity {
    try initBuiltins(codebase);
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
    var basic_blocks = components.BasicBlocks.init(allocator);
    const basic_block = try codebase.createEntity(.{
        components.IrInstructions.init(allocator),
        components.Scope.init(allocator, codebase.getPtr(Strings)),
    });
    _ = try basic_blocks.append(basic_block);
    const function = overloads[0];
    _ = try function.set(.{basic_blocks});
    const context = Context(@TypeOf(file_system)){
        .allocator = allocator,
        .codebase = codebase,
        .file_system = file_system,
        .module = module,
        .function = function,
        .basic_block = basic_block,
    };
    try context.lowerFunction();
    return module;
}

test "lower int literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = function(): I64
        \\  5
        \\end
    );
    const ir = try lower(codebase, fs, "foo.yeti", "start");
    const builtins = codebase.get(components.Builtins);
    const top_level = ir.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.I64);
    const basic_blocks = start.get(components.BasicBlocks).slice();
    try expectEqual(basic_blocks.len, 1);
    const basic_block = basic_blocks[0].get(components.IrInstructions).slice();
    try expectEqual(basic_block.len, 1);
    const int_const = basic_block[0];
    try expectEqual(int_const.get(components.IrInstructionKind), .int_const);
    const five = int_const.get(components.Result).entity;
    try expectEqualStrings(literalOf(five), "5");
    try expectEqual(typeOf(five), builtins.I64);
}

test "lower float literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = function(): F64
        \\  5.3
        \\end
    );
    const ir = try lower(codebase, fs, "foo.yeti", "start");
    const builtins = codebase.get(components.Builtins);
    const top_level = ir.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.F64);
    const basic_blocks = start.get(components.BasicBlocks).slice();
    try expectEqual(basic_blocks.len, 1);
    const basic_block = basic_blocks[0].get(components.IrInstructions).slice();
    try expectEqual(basic_block.len, 1);
    const float_const = basic_block[0];
    try expectEqual(float_const.get(components.IrInstructionKind), .float_const);
    const five_three = float_const.get(components.Result).entity;
    try expectEqualStrings(literalOf(five_three), "5.3");
    try expectEqual(typeOf(five_three), builtins.F64);
}

test "lower int literal as f64" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = function(): F64
        \\  5
        \\end
    );
    const ir = try lower(codebase, fs, "foo.yeti", "start");
    const builtins = codebase.get(components.Builtins);
    const top_level = ir.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.F64);
    const basic_blocks = start.get(components.BasicBlocks).slice();
    try expectEqual(basic_blocks.len, 1);
    const basic_block = basic_blocks[0].get(components.IrInstructions).slice();
    try expectEqual(basic_block.len, 1);
    const int_const = basic_block[0];
    try expectEqual(int_const.get(components.IrInstructionKind), .int_const);
    const five = int_const.get(components.Result).entity;
    try expectEqualStrings(literalOf(five), "5");
    try expectEqual(typeOf(five), builtins.F64);
}

test "lower call local function" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = function(): I64
        \\  baz()
        \\end
        \\
        \\baz = function(): I64
        \\  10
        \\end
    );
    const ir = try lower(codebase, fs, "foo.yeti", "start");
    const builtins = codebase.get(components.Builtins);
    const top_level = ir.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.I64);
    const baz = blk: {
        const basic_blocks = start.get(components.BasicBlocks).slice();
        try expectEqual(basic_blocks.len, 1);
        const basic_block = basic_blocks[0].get(components.IrInstructions).slice();
        try expectEqual(basic_block.len, 1);
        const call = basic_block[0];
        try expectEqual(call.get(components.IrInstructionKind), .call);
        const result = call.get(components.Result).entity;
        try expectEqual(typeOf(result), builtins.I64);
        try expectEqual(call.get(components.Arguments).len(), 0);
        break :blk call.get(components.Callable).entity;
    };
    try expectEqualStrings(literalOf(baz.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(baz.get(components.Name).entity), "baz");
    try expectEqual(baz.get(components.Parameters).len(), 0);
    try expectEqual(baz.get(components.ReturnType).entity, builtins.I64);
    const basic_blocks = baz.get(components.BasicBlocks).slice();
    try expectEqual(basic_blocks.len, 1);
    const basic_block = basic_blocks[0].get(components.IrInstructions).slice();
    try expectEqual(basic_block.len, 1);
    const int_const = basic_block[0];
    try expectEqual(int_const.get(components.IrInstructionKind), .int_const);
    const ten = int_const.get(components.Result).entity;
    try expectEqualStrings(literalOf(ten), "10");
    try expectEqual(typeOf(ten), builtins.I64);
}

test "call function from import" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\bar = import("bar.yeti")
        \\
        \\start = function(): I64
        \\  bar.baz()
        \\end
    );
    _ = try fs.newFile("bar.yeti",
        \\baz = function(): I64
        \\  10
        \\end
    );
    const ir = try lower(codebase, fs, "foo.yeti", "start");
    const builtins = codebase.get(components.Builtins);
    const top_level = ir.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.I64);
    const baz = blk: {
        const basic_blocks = start.get(components.BasicBlocks).slice();
        try expectEqual(basic_blocks.len, 1);
        const basic_block = basic_blocks[0].get(components.IrInstructions).slice();
        try expectEqual(basic_block.len, 1);
        const call = basic_block[0];
        try expectEqual(call.get(components.IrInstructionKind), .call);
        const bar_baz = call.get(components.Result).entity;
        try expectEqual(typeOf(bar_baz), builtins.I64);
        try expectEqual(call.get(components.Arguments).len(), 0);
        break :blk call.get(components.Callable).entity;
    };
    try expectEqualStrings(literalOf(baz.get(components.Module).entity), "bar");
    try expectEqualStrings(literalOf(baz.get(components.Name).entity), "baz");
    try expectEqual(baz.get(components.Parameters).len(), 0);
    try expectEqual(baz.get(components.ReturnType).entity, builtins.I64);
    const basic_blocks = baz.get(components.BasicBlocks).slice();
    try expectEqual(basic_blocks.len, 1);
    const basic_block = basic_blocks[0].get(components.IrInstructions).slice();
    try expectEqual(basic_block.len, 1);
    const int_const = basic_block[0];
    try expectEqual(int_const.get(components.IrInstructionKind), .int_const);
    const ten = int_const.get(components.Result).entity;
    try expectEqualStrings(literalOf(ten), "10");
    try expectEqual(typeOf(ten), builtins.I64);
}

test "lower assignment" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = function(): I64
        \\  x = 10
        \\  x
        \\end
    );
    const ir = try lower(codebase, fs, "foo.yeti", "start");
    const builtins = codebase.get(components.Builtins);
    const top_level = ir.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.I64);
    const basic_blocks = start.get(components.BasicBlocks).slice();
    try expectEqual(basic_blocks.len, 1);
    const basic_block = basic_blocks[0].get(components.IrInstructions).slice();
    try expectEqual(basic_block.len, 3);
    const int_const = basic_block[0];
    try expectEqual(int_const.get(components.IrInstructionKind), .int_const);
    const ten = int_const.get(components.Result).entity;
    try expectEqual(typeOf(ten), builtins.I64);
    try expectEqualStrings(literalOf(ten), "10");
    const set_local = basic_block[1];
    try expectEqual(set_local.get(components.IrInstructionKind), .set_local);
    const x = set_local.get(components.Result).entity;
    try expectEqualStrings(literalOf(x.get(components.Name).entity), "x");
    try expectEqual(ten, x);
    try expectEqual(typeOf(x), builtins.I64);
    const get_local = basic_block[2];
    try expectEqual(get_local.get(components.IrInstructionKind), .get_local);
    try expectEqual(ten, get_local.get(components.Result).entity);
}

test "lower two assignments" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = function(): I64
        \\  x = 10
        \\  y = 42
        \\  x
        \\end
    );
    const ir = try lower(codebase, fs, "foo.yeti", "start");
    const builtins = codebase.get(components.Builtins);
    const top_level = ir.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.I64);
    const basic_blocks = start.get(components.BasicBlocks).slice();
    try expectEqual(basic_blocks.len, 1);
    const basic_block = basic_blocks[0].get(components.IrInstructions).slice();
    try expectEqual(basic_block.len, 5);
    const x = blk: {
        const int_const = basic_block[0];
        try expectEqual(int_const.get(components.IrInstructionKind), .int_const);
        const result = int_const.get(components.Result).entity;
        try expectEqual(typeOf(result), builtins.I64);
        try expectEqualStrings(literalOf(result), "10");
        const set_local = basic_block[1];
        try expectEqual(set_local.get(components.IrInstructionKind), .set_local);
        try expectEqual(set_local.get(components.Result).entity, result);
        break :blk result;
    };
    {
        const int_const = basic_block[2];
        try expectEqual(int_const.get(components.IrInstructionKind), .int_const);
        const result = int_const.get(components.Result).entity;
        try expectEqual(typeOf(result), builtins.IntLiteral);
        try expectEqualStrings(literalOf(result), "42");
        const set_local = basic_block[3];
        try expectEqual(set_local.get(components.IrInstructionKind), .set_local);
        try expectEqual(set_local.get(components.Result).entity, result);
    }
    const get_local = basic_block[4];
    try expectEqual(get_local.get(components.IrInstructionKind), .get_local);
    try expectEqual(get_local.get(components.Result).entity, x);
}

test "lower two assignments with explicit type" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = function(): I64
        \\  x: U64 = 10
        \\  y: I64 = 42
        \\  y
        \\end
    );
    const ir = try lower(codebase, fs, "foo.yeti", "start");
    const builtins = codebase.get(components.Builtins);
    const top_level = ir.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.I64);
    const basic_blocks = start.get(components.BasicBlocks).slice();
    try expectEqual(basic_blocks.len, 1);
    const basic_block = basic_blocks[0].get(components.IrInstructions).slice();
    try expectEqual(basic_block.len, 5);
    {
        const int_const = basic_block[0];
        try expectEqual(int_const.get(components.IrInstructionKind), .int_const);
        const result = int_const.get(components.Result).entity;
        try expectEqual(typeOf(result), builtins.U64);
        try expectEqualStrings(literalOf(result), "10");
        const set_local = basic_block[1];
        try expectEqual(set_local.get(components.IrInstructionKind), .set_local);
        try expectEqual(set_local.get(components.Result).entity, result);
    }
    const y = blk: {
        const int_const = basic_block[2];
        try expectEqual(int_const.get(components.IrInstructionKind), .int_const);
        const result = int_const.get(components.Result).entity;
        try expectEqual(typeOf(result), builtins.I64);
        try expectEqualStrings(literalOf(result), "42");
        const set_local = basic_block[3];
        try expectEqual(set_local.get(components.IrInstructionKind), .set_local);
        try expectEqual(set_local.get(components.Result).entity, result);
        break :blk result;
    };
    const get_local = basic_block[4];
    try expectEqual(get_local.get(components.IrInstructionKind), .get_local);
    try expectEqual(get_local.get(components.Result).entity, y);
}

test "lower assignments with explicit f64 type" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = function(): F64
        \\  x: F64 = 10.2
        \\  x
        \\end
    );
    const ir = try lower(codebase, fs, "foo.yeti", "start");
    const builtins = codebase.get(components.Builtins);
    const top_level = ir.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.F64);
    const basic_blocks = start.get(components.BasicBlocks).slice();
    try expectEqual(basic_blocks.len, 1);
    const basic_block = basic_blocks[0].get(components.IrInstructions).slice();
    try expectEqual(basic_block.len, 3);
    const float_const = basic_block[0];
    try expectEqual(float_const.get(components.IrInstructionKind), .float_const);
    const x = float_const.get(components.Result).entity;
    try expectEqual(typeOf(x), builtins.F64);
    try expectEqualStrings(literalOf(x), "10.2");
    const set_local = basic_block[1];
    try expectEqual(set_local.get(components.IrInstructionKind), .set_local);
    try expectEqual(set_local.get(components.Result).entity, x);
    const get_local = basic_block[2];
    try expectEqual(get_local.get(components.IrInstructionKind), .get_local);
    try expectEqual(get_local.get(components.Result).entity, x);
}

test "lower function with argument" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = function(): I64
        \\  x: I64 = 10
        \\  id(x)
        \\end
        \\
        \\id = function(x: I64): I64
        \\  x
        \\end
    );
    const ir = try lower(codebase, fs, "foo.yeti", "start");
    const builtins = codebase.get(components.Builtins);
    const top_level = ir.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.I64);
    const id = blk: {
        const basic_blocks = start.get(components.BasicBlocks).slice();
        try expectEqual(basic_blocks.len, 1);
        const basic_block = basic_blocks[0].get(components.IrInstructions).slice();
        try expectEqual(basic_block.len, 4);
        const int_const = basic_block[0];
        try expectEqual(int_const.get(components.IrInstructionKind), .int_const);
        const x = int_const.get(components.Result).entity;
        try expectEqualStrings(literalOf(x), "10");
        try expectEqual(typeOf(x), builtins.I64);
        const set_local = basic_block[1];
        try expectEqual(set_local.get(components.IrInstructionKind), .set_local);
        try expectEqual(set_local.get(components.Result).entity, x);
        const get_local = basic_block[2];
        try expectEqual(get_local.get(components.IrInstructionKind), .get_local);
        try expectEqual(get_local.get(components.Result).entity, x);
        try expectEqualStrings(literalOf(x.get(components.Name).entity), "x");
        const call = basic_block[3];
        try expectEqual(call.get(components.IrInstructionKind), .call);
        const result = call.get(components.Result).entity;
        try expectEqual(typeOf(result), builtins.I64);
        try expectEqualSlices(Entity, call.get(components.Arguments).slice(), &.{x});
        break :blk call.get(components.Callable).entity;
    };
    try expectEqualStrings(literalOf(id.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(id.get(components.Name).entity), "id");
    const parameters = id.get(components.Parameters).slice();
    try expectEqual(parameters.len, 1);
    const x = parameters[0];
    try expectEqualStrings(literalOf(x.get(components.Name).entity), "x");
    try expectEqual(typeOf(x), builtins.I64);
    try expectEqual(id.get(components.ReturnType).entity, builtins.I64);
    const basic_blocks = id.get(components.BasicBlocks).slice();
    try expectEqual(basic_blocks.len, 1);
    const basic_block = basic_blocks[0].get(components.IrInstructions).slice();
    try expectEqual(basic_block.len, 1);
    const get_local = basic_block[0];
    try expectEqual(get_local.get(components.IrInstructionKind), .get_local);
    try expectEqual(get_local.get(components.Result).entity, x);
}

test "lower function with argument implicit conversion" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = function(): I64
        \\  x = 10
        \\  id(x)
        \\end
        \\
        \\id = function(x: I64): I64
        \\  x
        \\end
    );
    const ir = try lower(codebase, fs, "foo.yeti", "start");
    const builtins = codebase.get(components.Builtins);
    const top_level = ir.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.I64);
    const id = blk: {
        const basic_blocks = start.get(components.BasicBlocks).slice();
        try expectEqual(basic_blocks.len, 1);
        const basic_block = basic_blocks[0].get(components.IrInstructions).slice();
        try expectEqual(basic_block.len, 4);
        const int_const = basic_block[0];
        try expectEqual(int_const.get(components.IrInstructionKind), .int_const);
        const x = int_const.get(components.Result).entity;
        try expectEqualStrings(literalOf(x), "10");
        try expectEqual(typeOf(x), builtins.I64);
        const set_local = basic_block[1];
        try expectEqual(set_local.get(components.IrInstructionKind), .set_local);
        try expectEqual(set_local.get(components.Result).entity, x);
        const get_local = basic_block[2];
        try expectEqual(get_local.get(components.IrInstructionKind), .get_local);
        try expectEqual(get_local.get(components.Result).entity, x);
        try expectEqualStrings(literalOf(x.get(components.Name).entity), "x");
        const call = basic_block[3];
        try expectEqual(call.get(components.IrInstructionKind), .call);
        const result = call.get(components.Result).entity;
        try expectEqual(typeOf(result), builtins.I64);
        try expectEqualSlices(Entity, call.get(components.Arguments).slice(), &.{x});
        break :blk call.get(components.Callable).entity;
    };
    try expectEqualStrings(literalOf(id.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(id.get(components.Name).entity), "id");
    const parameters = id.get(components.Parameters).slice();
    try expectEqual(parameters.len, 1);
    const x = parameters[0];
    try expectEqualStrings(literalOf(x.get(components.Name).entity), "x");
    try expectEqual(typeOf(x), builtins.I64);
    try expectEqual(id.get(components.ReturnType).entity, builtins.I64);
    const basic_blocks = id.get(components.BasicBlocks).slice();
    try expectEqual(basic_blocks.len, 1);
    const basic_block = basic_blocks[0].get(components.IrInstructions).slice();
    try expectEqual(basic_block.len, 1);
    const get_local = basic_block[0];
    try expectEqual(get_local.get(components.IrInstructionKind), .get_local);
    try expectEqual(get_local.get(components.Result).entity, x);
}

test "lower function call from import with implicit conversion" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\bar = import("bar.yeti")
        \\
        \\start = function(): I64
        \\  x = 10
        \\  bar.baz(x)
        \\end
    );
    _ = try fs.newFile("bar.yeti",
        \\baz = function(x: I64): I64
        \\  x
        \\end
    );
    const ir = try lower(codebase, fs, "foo.yeti", "start");
    const builtins = codebase.get(components.Builtins);
    const top_level = ir.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.I64);
    const baz = blk: {
        const basic_blocks = start.get(components.BasicBlocks).slice();
        try expectEqual(basic_blocks.len, 1);
        const basic_block = basic_blocks[0].get(components.IrInstructions).slice();
        try expectEqual(basic_block.len, 4);
        const int_const = basic_block[0];
        try expectEqual(int_const.get(components.IrInstructionKind), .int_const);
        const x = int_const.get(components.Result).entity;
        try expectEqualStrings(literalOf(x), "10");
        try expectEqual(typeOf(x), builtins.I64);
        const set_local = basic_block[1];
        try expectEqual(set_local.get(components.IrInstructionKind), .set_local);
        try expectEqual(set_local.get(components.Result).entity, x);
        const get_local = basic_block[2];
        try expectEqual(get_local.get(components.IrInstructionKind), .get_local);
        try expectEqual(get_local.get(components.Result).entity, x);
        try expectEqualStrings(literalOf(x.get(components.Name).entity), "x");
        const call = basic_block[3];
        try expectEqual(call.get(components.IrInstructionKind), .call);
        const result = call.get(components.Result).entity;
        try expectEqual(typeOf(result), builtins.I64);
        try expectEqualSlices(Entity, call.get(components.Arguments).slice(), &.{x});
        break :blk call.get(components.Callable).entity;
    };
    try expectEqualStrings(literalOf(baz.get(components.Module).entity), "bar");
    try expectEqualStrings(literalOf(baz.get(components.Name).entity), "baz");
    const parameters = baz.get(components.Parameters).slice();
    try expectEqual(parameters.len, 1);
    const x = parameters[0];
    try expectEqualStrings(literalOf(x.get(components.Name).entity), "x");
    try expectEqual(typeOf(x), builtins.I64);
    try expectEqual(baz.get(components.ReturnType).entity, builtins.I64);
    const basic_blocks = baz.get(components.BasicBlocks).slice();
    try expectEqual(basic_blocks.len, 1);
    const basic_block = basic_blocks[0].get(components.IrInstructions).slice();
    try expectEqual(basic_block.len, 1);
    const get_local = basic_block[0];
    try expectEqual(get_local.get(components.IrInstructionKind), .get_local);
    try expectEqual(get_local.get(components.Result).entity, x);
}

test "lower function with U64 argument" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = function(): U64
        \\  x: U64 = 10
        \\  id(x)
        \\end
        \\
        \\id = function(x: U64): U64
        \\  x
        \\end
    );
    const ir = try lower(codebase, fs, "foo.yeti", "start");
    const builtins = codebase.get(components.Builtins);
    const top_level = ir.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.U64);
    const id = blk: {
        const basic_blocks = start.get(components.BasicBlocks).slice();
        try expectEqual(basic_blocks.len, 1);
        const basic_block = basic_blocks[0].get(components.IrInstructions).slice();
        try expectEqual(basic_block.len, 4);
        const int_const = basic_block[0];
        try expectEqual(int_const.get(components.IrInstructionKind), .int_const);
        const x = int_const.get(components.Result).entity;
        try expectEqualStrings(literalOf(x), "10");
        try expectEqual(typeOf(x), builtins.U64);
        const set_local = basic_block[1];
        try expectEqual(set_local.get(components.IrInstructionKind), .set_local);
        try expectEqual(set_local.get(components.Result).entity, x);
        const get_local = basic_block[2];
        try expectEqual(get_local.get(components.IrInstructionKind), .get_local);
        try expectEqual(get_local.get(components.Result).entity, x);
        try expectEqualStrings(literalOf(x.get(components.Name).entity), "x");
        const call = basic_block[3];
        try expectEqual(call.get(components.IrInstructionKind), .call);
        const result = call.get(components.Result).entity;
        try expectEqual(typeOf(result), builtins.U64);
        try expectEqualSlices(Entity, call.get(components.Arguments).slice(), &.{x});
        break :blk call.get(components.Callable).entity;
    };
    try expectEqualStrings(literalOf(id.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(id.get(components.Name).entity), "id");
    const parameters = id.get(components.Parameters).slice();
    try expectEqual(parameters.len, 1);
    const x = parameters[0];
    try expectEqualStrings(literalOf(x.get(components.Name).entity), "x");
    try expectEqual(typeOf(x), builtins.U64);
    try expectEqual(id.get(components.ReturnType).entity, builtins.U64);
    const basic_blocks = id.get(components.BasicBlocks).slice();
    try expectEqual(basic_blocks.len, 1);
    const basic_block = basic_blocks[0].get(components.IrInstructions).slice();
    try expectEqual(basic_block.len, 1);
    const get_local = basic_block[0];
    try expectEqual(get_local.get(components.IrInstructionKind), .get_local);
    try expectEqual(get_local.get(components.Result).entity, x);
}

test "lower function with U64 argument" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = function(): U64
        \\  x: U64 = 10
        \\  id(x)
        \\end
        \\
        \\id = function(x: U64): U64
        \\  x
        \\end
    );
    const ir = try lower(codebase, fs, "foo.yeti", "start");
    const builtins = codebase.get(components.Builtins);
    const top_level = ir.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.U64);
    const id = blk: {
        const basic_blocks = start.get(components.BasicBlocks).slice();
        try expectEqual(basic_blocks.len, 1);
        const basic_block = basic_blocks[0].get(components.IrInstructions).slice();
        try expectEqual(basic_block.len, 4);
        const int_const = basic_block[0];
        try expectEqual(int_const.get(components.IrInstructionKind), .int_const);
        const x = int_const.get(components.Result).entity;
        try expectEqualStrings(literalOf(x), "10");
        try expectEqual(typeOf(x), builtins.U64);
        const set_local = basic_block[1];
        try expectEqual(set_local.get(components.IrInstructionKind), .set_local);
        try expectEqual(set_local.get(components.Result).entity, x);
        const get_local = basic_block[2];
        try expectEqual(get_local.get(components.IrInstructionKind), .get_local);
        try expectEqual(get_local.get(components.Result).entity, x);
        try expectEqualStrings(literalOf(x.get(components.Name).entity), "x");
        const call = basic_block[3];
        try expectEqual(call.get(components.IrInstructionKind), .call);
        const result = call.get(components.Result).entity;
        try expectEqual(typeOf(result), builtins.U64);
        try expectEqualSlices(Entity, call.get(components.Arguments).slice(), &.{x});
        break :blk call.get(components.Callable).entity;
    };
    try expectEqualStrings(literalOf(id.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(id.get(components.Name).entity), "id");
    const parameters = id.get(components.Parameters).slice();
    try expectEqual(parameters.len, 1);
    const x = parameters[0];
    try expectEqualStrings(literalOf(x.get(components.Name).entity), "x");
    try expectEqual(typeOf(x), builtins.U64);
    try expectEqual(id.get(components.ReturnType).entity, builtins.U64);
    const basic_blocks = id.get(components.BasicBlocks).slice();
    try expectEqual(basic_blocks.len, 1);
    const basic_block = basic_blocks[0].get(components.IrInstructions).slice();
    try expectEqual(basic_block.len, 1);
    const get_local = basic_block[0];
    try expectEqual(get_local.get(components.IrInstructionKind), .get_local);
    try expectEqual(get_local.get(components.Result).entity, x);
}

test "lower function with U64 return" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = function(): U64
        \\  42
        \\end
    );
    const ir = try lower(codebase, fs, "foo.yeti", "start");
    const builtins = codebase.get(components.Builtins);
    const top_level = ir.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.U64);
    const basic_blocks = start.get(components.BasicBlocks).slice();
    try expectEqual(basic_blocks.len, 1);
    const basic_block = basic_blocks[0].get(components.IrInstructions).slice();
    try expectEqual(basic_block.len, 1);
    const int_const = basic_block[0];
    try expectEqual(int_const.get(components.IrInstructionKind), .int_const);
    const result = int_const.get(components.Result).entity;
    try expectEqualStrings(literalOf(result), "42");
    try expectEqual(typeOf(result), builtins.U64);
}

test "lower function overload using I64" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = function(): I64
        \\  x: I64 = 0
        \\  f(x)
        \\end
        \\
        \\f = function(x: I64): I64
        \\  42
        \\end
        \\
        \\f = function(x: U64): I64
        \\  24
        \\end
    );
    const ir = try lower(codebase, fs, "foo.yeti", "start");
    const builtins = codebase.get(components.Builtins);
    const top_level = ir.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.I64);
    const f = blk: {
        const basic_blocks = start.get(components.BasicBlocks).slice();
        try expectEqual(basic_blocks.len, 1);
        const basic_block = basic_blocks[0].get(components.IrInstructions).slice();
        try expectEqual(basic_block.len, 4);
        const int_const = basic_block[0];
        try expectEqual(int_const.get(components.IrInstructionKind), .int_const);
        const x = int_const.get(components.Result).entity;
        try expectEqualStrings(literalOf(x), "0");
        try expectEqual(typeOf(x), builtins.I64);
        const set_local = basic_block[1];
        try expectEqual(set_local.get(components.IrInstructionKind), .set_local);
        try expectEqual(set_local.get(components.Result).entity, x);
        const get_local = basic_block[2];
        try expectEqual(get_local.get(components.IrInstructionKind), .get_local);
        try expectEqual(get_local.get(components.Result).entity, x);
        try expectEqualStrings(literalOf(x.get(components.Name).entity), "x");
        const call = basic_block[3];
        try expectEqual(call.get(components.IrInstructionKind), .call);
        const result = call.get(components.Result).entity;
        try expectEqual(typeOf(result), builtins.I64);
        try expectEqualSlices(Entity, call.get(components.Arguments).slice(), &.{x});
        break :blk call.get(components.Callable).entity;
    };
    try expectEqualStrings(literalOf(f.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(f.get(components.Name).entity), "f");
    const parameters = f.get(components.Parameters).slice();
    try expectEqual(parameters.len, 1);
    const x = parameters[0];
    try expectEqualStrings(literalOf(x.get(components.Name).entity), "x");
    try expectEqual(typeOf(x), builtins.I64);
    try expectEqual(f.get(components.ReturnType).entity, builtins.I64);
    const basic_blocks = f.get(components.BasicBlocks).slice();
    try expectEqual(basic_blocks.len, 1);
    const basic_block = basic_blocks[0].get(components.IrInstructions).slice();
    try expectEqual(basic_block.len, 1);
    const int_const = basic_block[0];
    try expectEqual(int_const.get(components.IrInstructionKind), .int_const);
    const result = int_const.get(components.Result).entity;
    try expectEqualStrings(literalOf(result), "42");
    try expectEqual(typeOf(result), builtins.I64);
}

test "lower function overload using U64" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = function(): I64
        \\  x: U64 = 0
        \\  f(x)
        \\end
        \\
        \\f = function(x: I64): I64
        \\  42
        \\end
        \\
        \\f = function(x: U64): I64
        \\  24
        \\end
    );
    const ir = try lower(codebase, fs, "foo.yeti", "start");
    const builtins = codebase.get(components.Builtins);
    const top_level = ir.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.I64);
    const f = blk: {
        const basic_blocks = start.get(components.BasicBlocks).slice();
        try expectEqual(basic_blocks.len, 1);
        const basic_block = basic_blocks[0].get(components.IrInstructions).slice();
        try expectEqual(basic_block.len, 4);
        const int_const = basic_block[0];
        try expectEqual(int_const.get(components.IrInstructionKind), .int_const);
        const x = int_const.get(components.Result).entity;
        try expectEqualStrings(literalOf(x), "0");
        try expectEqual(typeOf(x), builtins.U64);
        const set_local = basic_block[1];
        try expectEqual(set_local.get(components.IrInstructionKind), .set_local);
        try expectEqual(set_local.get(components.Result).entity, x);
        const get_local = basic_block[2];
        try expectEqual(get_local.get(components.IrInstructionKind), .get_local);
        try expectEqual(get_local.get(components.Result).entity, x);
        try expectEqualStrings(literalOf(x.get(components.Name).entity), "x");
        const call = basic_block[3];
        try expectEqual(call.get(components.IrInstructionKind), .call);
        const result = call.get(components.Result).entity;
        try expectEqual(typeOf(result), builtins.I64);
        try expectEqualSlices(Entity, call.get(components.Arguments).slice(), &.{x});
        break :blk call.get(components.Callable).entity;
    };
    try expectEqualStrings(literalOf(f.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(f.get(components.Name).entity), "f");
    const parameters = f.get(components.Parameters).slice();
    try expectEqual(parameters.len, 1);
    const x = parameters[0];
    try expectEqualStrings(literalOf(x.get(components.Name).entity), "x");
    try expectEqual(typeOf(x), builtins.U64);
    try expectEqual(f.get(components.ReturnType).entity, builtins.I64);
    const basic_blocks = f.get(components.BasicBlocks).slice();
    try expectEqual(basic_blocks.len, 1);
    const basic_block = basic_blocks[0].get(components.IrInstructions).slice();
    try expectEqual(basic_block.len, 1);
    const int_const = basic_block[0];
    try expectEqual(int_const.get(components.IrInstructionKind), .int_const);
    const result = int_const.get(components.Result).entity;
    try expectEqualStrings(literalOf(result), "24");
    try expectEqual(typeOf(result), builtins.I64);
}

test "lower i64 add" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = function(): I64
        \\  x: I64 = 10
        \\  y: I64 = 32
        \\  x + y
        \\end
    );
    const ir = try lower(codebase, fs, "foo.yeti", "start");
    const builtins = codebase.get(components.Builtins);
    const top_level = ir.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.I64);
    const basic_blocks = start.get(components.BasicBlocks).slice();
    try expectEqual(basic_blocks.len, 1);
    const basic_block = basic_blocks[0].get(components.IrInstructions).slice();
    try expectEqual(basic_block.len, 7);
    const x = blk: {
        const int_const = basic_block[0];
        try expectEqual(int_const.get(components.IrInstructionKind), .int_const);
        const result = int_const.get(components.Result).entity;
        try expectEqualStrings(literalOf(result), "10");
        try expectEqual(typeOf(result), builtins.I64);
        const set_local = basic_block[1];
        try expectEqual(set_local.get(components.IrInstructionKind), .set_local);
        try expectEqual(set_local.get(components.Result).entity, result);
        break :blk result;
    };
    const y = blk: {
        const int_const = basic_block[2];
        try expectEqual(int_const.get(components.IrInstructionKind), .int_const);
        const result = int_const.get(components.Result).entity;
        try expectEqualStrings(literalOf(result), "32");
        try expectEqual(typeOf(result), builtins.I64);
        const set_local = basic_block[3];
        try expectEqual(set_local.get(components.IrInstructionKind), .set_local);
        try expectEqual(set_local.get(components.Result).entity, result);
        break :blk result;
    };
    {
        const get_local = basic_block[4];
        try expectEqual(get_local.get(components.IrInstructionKind), .get_local);
        try expectEqual(get_local.get(components.Result).entity, x);
    }
    {
        const get_local = basic_block[5];
        try expectEqual(get_local.get(components.IrInstructionKind), .get_local);
        try expectEqual(get_local.get(components.Result).entity, y);
    }
    const int_add = basic_block[6];
    try expectEqual(int_add.get(components.IrInstructionKind), .int_add);
    const result = int_add.get(components.Result).entity;
    try expectEqual(typeOf(result), builtins.I64);
}

test "lower u64 add" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = function(): U64
        \\  x: U64 = 10
        \\  y: U64 = 32
        \\  x + y
        \\end
    );
    const ir = try lower(codebase, fs, "foo.yeti", "start");
    const builtins = codebase.get(components.Builtins);
    const top_level = ir.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.U64);
    const basic_blocks = start.get(components.BasicBlocks).slice();
    try expectEqual(basic_blocks.len, 1);
    const basic_block = basic_blocks[0].get(components.IrInstructions).slice();
    try expectEqual(basic_block.len, 7);
    const x = blk: {
        const int_const = basic_block[0];
        try expectEqual(int_const.get(components.IrInstructionKind), .int_const);
        const result = int_const.get(components.Result).entity;
        try expectEqualStrings(literalOf(result), "10");
        try expectEqual(typeOf(result), builtins.U64);
        const set_local = basic_block[1];
        try expectEqual(set_local.get(components.IrInstructionKind), .set_local);
        try expectEqual(set_local.get(components.Result).entity, result);
        break :blk result;
    };
    const y = blk: {
        const int_const = basic_block[2];
        try expectEqual(int_const.get(components.IrInstructionKind), .int_const);
        const result = int_const.get(components.Result).entity;
        try expectEqualStrings(literalOf(result), "32");
        try expectEqual(typeOf(result), builtins.U64);
        const set_local = basic_block[3];
        try expectEqual(set_local.get(components.IrInstructionKind), .set_local);
        try expectEqual(set_local.get(components.Result).entity, result);
        break :blk result;
    };
    {
        const get_local = basic_block[4];
        try expectEqual(get_local.get(components.IrInstructionKind), .get_local);
        try expectEqual(get_local.get(components.Result).entity, x);
    }
    {
        const get_local = basic_block[5];
        try expectEqual(get_local.get(components.IrInstructionKind), .get_local);
        try expectEqual(get_local.get(components.Result).entity, y);
    }
    const int_add = basic_block[6];
    try expectEqual(int_add.get(components.IrInstructionKind), .int_add);
    const result = int_add.get(components.Result).entity;
    try expectEqual(typeOf(result), builtins.U64);
}

test "lower int literal add" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = function(): U64
        \\  10 + 32
        \\end
    );
    const ir = try lower(codebase, fs, "foo.yeti", "start");
    const builtins = codebase.get(components.Builtins);
    const top_level = ir.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.U64);
    const basic_blocks = start.get(components.BasicBlocks).slice();
    try expectEqual(basic_blocks.len, 1);
    const basic_block = basic_blocks[0].get(components.IrInstructions).slice();
    try expectEqual(basic_block.len, 3);
    {
        const int_const = basic_block[0];
        try expectEqual(int_const.get(components.IrInstructionKind), .int_const);
        const result = int_const.get(components.Result).entity;
        try expectEqualStrings(literalOf(result), "10");
        try expectEqual(typeOf(result), builtins.IntLiteral);
    }
    {
        const int_const = basic_block[1];
        try expectEqual(int_const.get(components.IrInstructionKind), .int_const);
        const result = int_const.get(components.Result).entity;
        try expectEqualStrings(literalOf(result), "32");
        try expectEqual(typeOf(result), builtins.IntLiteral);
    }
    const int_const = basic_block[2];
    try expectEqual(int_const.get(components.IrInstructionKind), .int_const);
    const result = int_const.get(components.Result).entity;
    try expectEqualStrings(literalOf(result), "42");
    try expectEqual(typeOf(result), builtins.U64);
}

test "lower i64 add int literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = function(): I64
        \\  x: I64 = 10
        \\  x + 32
        \\end
    );
    const ir = try lower(codebase, fs, "foo.yeti", "start");
    const builtins = codebase.get(components.Builtins);
    const top_level = ir.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.I64);
    const basic_blocks = start.get(components.BasicBlocks).slice();
    try expectEqual(basic_blocks.len, 1);
    const basic_block = basic_blocks[0].get(components.IrInstructions).slice();
    try expectEqual(basic_block.len, 5);
    const x = blk: {
        const int_const = basic_block[0];
        try expectEqual(int_const.get(components.IrInstructionKind), .int_const);
        const result = int_const.get(components.Result).entity;
        try expectEqualStrings(literalOf(result), "10");
        try expectEqual(typeOf(result), builtins.I64);
        const set_local = basic_block[1];
        try expectEqual(set_local.get(components.IrInstructionKind), .set_local);
        try expectEqual(set_local.get(components.Result).entity, result);
        break :blk result;
    };
    const get_local = basic_block[2];
    try expectEqual(get_local.get(components.IrInstructionKind), .get_local);
    try expectEqual(get_local.get(components.Result).entity, x);
    {
        const int_const = basic_block[3];
        try expectEqual(int_const.get(components.IrInstructionKind), .int_const);
        const result = int_const.get(components.Result).entity;
        try expectEqualStrings(literalOf(result), "32");
        try expectEqual(typeOf(result), builtins.I64);
    }
    const int_add = basic_block[4];
    try expectEqual(int_add.get(components.IrInstructionKind), .int_add);
    const result = int_add.get(components.Result).entity;
    try expectEqual(typeOf(result), builtins.I64);
}

test "lower int literal add i64" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = function(): I64
        \\  x: I64 = 10
        \\  32 + x
        \\end
    );
    const ir = try lower(codebase, fs, "foo.yeti", "start");
    const builtins = codebase.get(components.Builtins);
    const top_level = ir.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.I64);
    const basic_blocks = start.get(components.BasicBlocks).slice();
    try expectEqual(basic_blocks.len, 1);
    const basic_block = basic_blocks[0].get(components.IrInstructions).slice();
    try expectEqual(basic_block.len, 5);
    const x = blk: {
        const int_const = basic_block[0];
        try expectEqual(int_const.get(components.IrInstructionKind), .int_const);
        const result = int_const.get(components.Result).entity;
        try expectEqualStrings(literalOf(result), "10");
        try expectEqual(typeOf(result), builtins.I64);
        const set_local = basic_block[1];
        try expectEqual(set_local.get(components.IrInstructionKind), .set_local);
        try expectEqual(set_local.get(components.Result).entity, result);
        break :blk result;
    };
    {
        const int_const = basic_block[2];
        try expectEqual(int_const.get(components.IrInstructionKind), .int_const);
        const result = int_const.get(components.Result).entity;
        try expectEqualStrings(literalOf(result), "32");
        try expectEqual(typeOf(result), builtins.I64);
    }
    const get_local = basic_block[3];
    try expectEqual(get_local.get(components.IrInstructionKind), .get_local);
    try expectEqual(get_local.get(components.Result).entity, x);
    const int_add = basic_block[4];
    try expectEqual(int_add.get(components.IrInstructionKind), .int_add);
    const result = int_add.get(components.Result).entity;
    try expectEqual(typeOf(result), builtins.I64);
}

test "lower u64 add int literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = function(): U64
        \\  x: U64 = 10
        \\  x + 32
        \\end
    );
    const ir = try lower(codebase, fs, "foo.yeti", "start");
    const builtins = codebase.get(components.Builtins);
    const top_level = ir.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.U64);
    const basic_blocks = start.get(components.BasicBlocks).slice();
    try expectEqual(basic_blocks.len, 1);
    const basic_block = basic_blocks[0].get(components.IrInstructions).slice();
    try expectEqual(basic_block.len, 5);
    const x = blk: {
        const int_const = basic_block[0];
        try expectEqual(int_const.get(components.IrInstructionKind), .int_const);
        const result = int_const.get(components.Result).entity;
        try expectEqualStrings(literalOf(result), "10");
        try expectEqual(typeOf(result), builtins.U64);
        const set_local = basic_block[1];
        try expectEqual(set_local.get(components.IrInstructionKind), .set_local);
        try expectEqual(set_local.get(components.Result).entity, result);
        break :blk result;
    };
    const get_local = basic_block[2];
    try expectEqual(get_local.get(components.IrInstructionKind), .get_local);
    try expectEqual(get_local.get(components.Result).entity, x);
    {
        const int_const = basic_block[3];
        try expectEqual(int_const.get(components.IrInstructionKind), .int_const);
        const result = int_const.get(components.Result).entity;
        try expectEqualStrings(literalOf(result), "32");
        try expectEqual(typeOf(result), builtins.U64);
    }
    const int_add = basic_block[4];
    try expectEqual(int_add.get(components.IrInstructionKind), .int_add);
    const result = int_add.get(components.Result).entity;
    try expectEqual(typeOf(result), builtins.U64);
}

test "lower int literal add u64" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = function(): U64
        \\  x: U64 = 10
        \\  32 + x
        \\end
    );
    const ir = try lower(codebase, fs, "foo.yeti", "start");
    const builtins = codebase.get(components.Builtins);
    const top_level = ir.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.U64);
    const basic_blocks = start.get(components.BasicBlocks).slice();
    try expectEqual(basic_blocks.len, 1);
    const basic_block = basic_blocks[0].get(components.IrInstructions).slice();
    try expectEqual(basic_block.len, 5);
    const x = blk: {
        const int_const = basic_block[0];
        try expectEqual(int_const.get(components.IrInstructionKind), .int_const);
        const result = int_const.get(components.Result).entity;
        try expectEqualStrings(literalOf(result), "10");
        try expectEqual(typeOf(result), builtins.U64);
        const set_local = basic_block[1];
        try expectEqual(set_local.get(components.IrInstructionKind), .set_local);
        try expectEqual(set_local.get(components.Result).entity, result);
        break :blk result;
    };
    {
        const int_const = basic_block[2];
        try expectEqual(int_const.get(components.IrInstructionKind), .int_const);
        const result = int_const.get(components.Result).entity;
        try expectEqualStrings(literalOf(result), "32");
        try expectEqual(typeOf(result), builtins.U64);
    }
    const get_local = basic_block[3];
    try expectEqual(get_local.get(components.IrInstructionKind), .get_local);
    try expectEqual(get_local.get(components.Result).entity, x);
    const int_add = basic_block[4];
    try expectEqual(int_add.get(components.IrInstructionKind), .int_add);
    const result = int_add.get(components.Result).entity;
    try expectEqual(typeOf(result), builtins.U64);
}
