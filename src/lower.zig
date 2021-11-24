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

fn Helpers(comptime FileSystem: type) type {
    return struct {
        const Context = struct {
            allocator: *Allocator,
            codebase: *ECS,
            file_system: FileSystem,
            module: Entity,
            function: Entity,
            basic_block: Entity,
        };

        fn lowerSymbol(context: Context, entity: Entity) !Entity {
            const literal = entity.get(components.Literal);
            const local_scope = context.basic_block.get(components.Scope);
            if (local_scope.hasLiteral(literal)) |local| {
                const instructions = context.basic_block.getPtr(components.IrInstructions);
                const instruction = try context.codebase.createEntity(.{
                    components.IrInstructionKind.get_local,
                    components.Result.init(local),
                });
                try instructions.append(instruction);
                return local;
            }
            const global_scope = context.codebase.get(components.Scope);
            if (global_scope.hasLiteral(literal)) |global| {
                return global;
            }
            const top_level_scope = context.module.get(components.TopLevel);
            if (top_level_scope.hasLiteral(literal)) |top_level| {
                const kind = top_level.get(components.AstKind);
                switch (kind) {
                    .import => {
                        // TODO: Don't reparse the module every time. Cache them based on path
                        const module_name = literalOf(top_level.get(components.Path).entity);
                        const contents = try context.file_system.read(module_name);
                        const module = try context.codebase.createEntity(.{});
                        var tokens = try tokenize(module, contents);
                        try parse(module, &tokens);
                        const interned = try context.codebase.getPtr(Strings).intern(module_name[0 .. module_name.len - 5]);
                        _ = try module.set(.{components.Literal.init(interned)});
                        return module;
                    },
                    else => panic("\nlowerSumbol unspported top level kind {}\n", .{kind}),
                }
            }
            panic("\nlowerSymbol failed for symbol {s}\n", .{literalOf(entity)});
        }

        fn lowerInt(context: Context, entity: Entity) !Entity {
            const instructions = context.basic_block.getPtr(components.IrInstructions);
            const instruction = try context.codebase.createEntity(.{
                components.IrInstructionKind.int_const,
                components.Result.init(entity),
            });
            try instructions.append(instruction);
            return entity;
        }

        fn lowerDot(context: Context, entity: Entity) !Entity {
            const dot_arguments = entity.get(components.Arguments).slice();
            const module = try lowerExpression(context, dot_arguments[0]);
            assert(eql(typeOf(module), context.codebase.get(components.Builtins).Module));
            const call = dot_arguments[1];
            assert(call.get(components.AstKind) == .call);
            const new_context = Context{
                .allocator = context.allocator,
                .codebase = context.codebase,
                .file_system = context.file_system,
                .module = module,
                .function = context.function,
                .basic_block = context.basic_block,
            };
            return try lowerCall(new_context, call);
        }

        fn lowerAdd(context: Context, entity: Entity) !Entity {
            const builtins = context.codebase.get(components.Builtins);
            const arguments = entity.get(components.Arguments).slice();
            const lhs = try lowerExpression(context, arguments[0]);
            const rhs = try lowerExpression(context, arguments[1]);
            const lhs_type = typeOf(lhs);
            const rhs_type = typeOf(rhs);
            assert(eql(lhs_type, builtins.I64));
            assert(eql(rhs_type, builtins.I64));
            const result = try context.codebase.createEntity(.{components.Type.init(builtins.I64)});
            const instructions = context.basic_block.getPtr(components.IrInstructions);
            const instruction = try context.codebase.createEntity(.{
                components.IrInstructionKind.int_add,
                components.Result.init(result),
            });
            try instructions.append(instruction);
            return result;
        }

        fn lowerBinaryOp(context: Context, entity: Entity) !Entity {
            const binary_op = entity.get(components.BinaryOp);
            return try switch (binary_op) {
                .dot => lowerDot(context, entity),
                .add => lowerAdd(context, entity),
                else => panic("\nlowerBinaryOp unsupported binary op {}\n", .{binary_op}),
            };
        }

        const Match = enum {
            none,
            implict_conversion,
            exact,
        };

        fn bestOverload(context: Context, callable: Entity, arguments: []const Entity) !Entity {
            const top_level = context.module.get(components.TopLevel);
            const literal = callable.get(components.Literal);
            var best_overload: Entity = undefined;
            var best_match = Match.none;
            const builtins = context.codebase.get(components.Builtins);
            for (top_level.findLiteral(literal).get(components.Overloads).slice()) |overload| {
                var basic_blocks = components.BasicBlocks.init(context.allocator);
                const basic_block = try context.codebase.createEntity(.{
                    components.IrInstructions.init(context.allocator),
                    components.Scope.init(context.allocator, context.codebase.getPtr(Strings)),
                });
                _ = try basic_blocks.append(basic_block);
                _ = try overload.set(.{basic_blocks});
                const new_context = Context{
                    .allocator = context.allocator,
                    .codebase = context.codebase,
                    .file_system = context.file_system,
                    .module = context.module,
                    .function = overload,
                    .basic_block = basic_block,
                };
                try lowerFunctionParameters(new_context);
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

        fn lowerCall(context: Context, call: Entity) !Entity {
            const callable = call.get(components.Callable).entity;
            const call_arguments = call.get(components.Arguments).slice();
            var function_arguments = try components.Arguments.withCapacity(context.allocator, call_arguments.len);
            for (call_arguments) |argument| {
                function_arguments.appendAssumeCapacity(try lowerExpression(context, argument));
            }
            const function = try bestOverload(context, callable, function_arguments.slice());
            {
                const new_context = Context{
                    .allocator = context.allocator,
                    .codebase = context.codebase,
                    .file_system = context.file_system,
                    .module = context.module,
                    .function = function,
                    .basic_block = function.get(components.BasicBlocks).slice()[0],
                };
                try lowerFunction(new_context);
            }
            const function_parameters = function.get(components.Parameters).slice();
            for (function_arguments.slice()) |argument, i| {
                try implicitTypeConversion(argument, typeOf(function_parameters[i]));
            }
            const return_type = function.get(components.ReturnType).entity;
            const result = try context.codebase.createEntity(.{components.Type.init(return_type)});
            const instructions = context.basic_block.getPtr(components.IrInstructions);
            const instruction = try context.codebase.createEntity(.{
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
                if (eql(expected_type, builtins.I64) or eql(expected_type, builtins.U64)) {
                    _ = try value.set(.{components.Type.init(expected_type)});
                } else {
                    panic("lower define found invalid explicit type for int literal", .{});
                }
            } else {
                assert(eql(expected_type, actual_type));
            }
        }

        fn lowerDefine(context: Context, define: Entity) !Entity {
            const scope = context.basic_block.getPtr(components.Scope);
            const value = try lowerExpression(context, define.get(components.Value).entity);
            if (define.has(components.TypeAst)) |type_ast| {
                const explicit_type = try lowerExpression(context, type_ast.entity);
                try implicitTypeConversion(value, explicit_type);
            }
            const instructions = context.basic_block.getPtr(components.IrInstructions);
            const instruction = try context.codebase.createEntity(.{
                components.IrInstructionKind.set_local,
                components.Result.init(value),
            });
            try instructions.append(instruction);
            const name = define.get(components.Name);
            _ = try value.set(.{name});
            try scope.putName(name, value);
            return context.codebase.get(components.Builtins).Void;
        }

        fn lowerExpression(context: Context, entity: Entity) error{ OutOfMemory, CantOpenFile }!Entity {
            const kind = entity.get(components.AstKind);
            return switch (kind) {
                .symbol => try lowerSymbol(context, entity),
                .int => try lowerInt(context, entity),
                .binary_op => try lowerBinaryOp(context, entity),
                .call => try lowerCall(context, entity),
                .define => try lowerDefine(context, entity),
                else => panic("\nlowerExpression unsupported kind {}\n", .{kind}),
            };
        }

        fn lowerFunctionParameters(context: Context) !void {
            if (context.function.has(components.LoweredParameters) != null) return;
            const scope = context.basic_block.getPtr(components.Scope);
            const parameters = context.function.get(components.Parameters).slice();
            for (parameters) |parameter| {
                const parameter_type = try lowerExpression(context, parameter.get(components.TypeAst).entity);
                _ = try parameter.set(.{
                    components.Type.init(parameter_type),
                    components.Name.init(parameter),
                });
                try scope.putLiteral(parameter.get(components.Literal), parameter);
            }
            _ = try context.function.set(.{components.LoweredParameters{ .value = true }});
        }

        fn lowerFunctionReturnType(context: Context) !Entity {
            const return_type = try lowerExpression(context, context.function.get(components.ReturnTypeAst).entity);
            _ = try context.function.set(.{components.ReturnType.init(return_type)});
            return return_type;
        }

        fn lowerFunctionBody(context: Context) !Entity {
            const body = context.function.get(components.Body).slice();
            var return_entity: Entity = undefined;
            for (body) |expression| {
                return_entity = try lowerExpression(context, expression);
            }
            return return_entity;
        }

        fn lowerFunction(context: Context) !void {
            _ = try context.function.set(.{components.Module.init(context.module)});
            _ = try context.codebase.getPtr(components.Functions).append(context.function);
            try lowerFunctionParameters(context);
            const return_type = try lowerFunctionReturnType(context);
            const return_entity = try lowerFunctionBody(context);
            try implicitTypeConversion(return_entity, return_type);
        }
    };
}

pub fn lower(codebase: *ECS, file_system: anytype, module_name: []const u8, function_name: []const u8) !Entity {
    const helpers = Helpers(@TypeOf(file_system));
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
    const context = helpers.Context{
        .allocator = allocator,
        .codebase = codebase,
        .file_system = file_system,
        .module = module,
        .function = function,
        .basic_block = basic_block,
    };
    try helpers.lowerFunction(context);
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
