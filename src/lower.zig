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
const FileSystem = @import("file_system.zig").FileSystem;
const components = @import("components.zig");
const test_utils = @import("test_utils.zig");
const literalOf = test_utils.literalOf;
const typeOf = test_utils.typeOf;

fn Context(comptime FS: type) type {
    return struct {
        allocator: *Allocator,
        codebase: *ECS,
        fs: FS,
        ast: Entity,
        function: Entity,
        basic_block: Entity,
    };
}

fn lowerSymbol(comptime FS: type, context: Context(FS), entity: Entity) !Entity {
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
    // TODO:lookup symbol from cached ir module component
    const top_level_scope = context.ast.get(components.TopLevel);
    if (top_level_scope.hasLiteral(literal)) |top_level| {
        const kind = top_level.get(components.AstKind);
        switch (kind) {
            .import => {
                const module_name = literalOf(top_level.get(components.Path).entity);
                const contents = try context.fs.read(module_name);
                var tokens = try tokenize(context.codebase, contents);
                // TODO:cache the ast into ir module component
                const ast = try parse(context.codebase, &tokens);
                const interned = try context.codebase.getPtr(Strings).intern(module_name[0 .. module_name.len - 5]);
                _ = try ast.set(.{components.Literal.init(interned)});
                return ast;
            },
            else => panic("\nlowerSumbol unspported top level kind {}\n", .{kind}),
        }
    }
    panic("\nlowerSymbol failed for symbol {s}\n", .{literalOf(entity)});
}

fn lowerInt(comptime FS: type, context: Context(FS), entity: Entity) !Entity {
    const instructions = context.basic_block.getPtr(components.IrInstructions);
    const instruction = try context.codebase.createEntity(.{
        components.IrInstructionKind.int_const,
        components.Result.init(entity),
    });
    try instructions.append(instruction);
    return entity;
}

fn lowerDot(comptime FS: type, context: Context(FS), entity: Entity) !Entity {
    const dot_arguments = entity.get(components.Arguments).slice();
    const ast = try lowerExpression(FS, context, dot_arguments[0]);
    assert(eql(typeOf(ast), context.codebase.get(components.Builtins).Module));
    const call = dot_arguments[1];
    assert(call.get(components.AstKind) == .call);
    const callable = call.get(components.Callable).entity;
    assert(callable.get(components.AstKind) == .symbol);
    // TODO: check if this function has already been lowered for these parameter types
    const top_level = ast.get(components.TopLevel);
    const literal = callable.get(components.Literal);
    const overloads = top_level.findLiteral(literal).get(components.Overloads).slice();
    assert(overloads.len == 1);
    const function = overloads[0];
    {
        var basic_blocks = components.BasicBlocks.init(context.allocator);
        const basic_block = try context.codebase.createEntity(.{
            components.IrInstructions.init(context.allocator),
            components.Scope.init(context.allocator, context.codebase.getPtr(Strings)),
        });
        _ = try basic_blocks.append(basic_block);
        _ = try function.set(.{basic_blocks});
        const new_context = Context(FS){
            .allocator = context.allocator,
            .codebase = context.codebase,
            .fs = context.fs,
            .ast = ast,
            .function = function,
            .basic_block = basic_block,
        };
        assert(new_context.function.get(components.Parameters).entities.len == 0);
        try lowerFunction(FS, new_context);
    }
    const call_arguments = call.get(components.Arguments).slice();
    var function_arguments = try components.Arguments.withCapacity(context.allocator, call_arguments.len);
    for (call_arguments) |argument| {
        function_arguments.appendAssumeCapacity(try lowerExpression(FS, context, argument));
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

fn lowerBinaryOp(comptime FS: type, context: Context(FS), entity: Entity) !Entity {
    const binary_op = entity.get(components.BinaryOp);
    return switch (binary_op) {
        .dot => lowerDot(FS, context, entity),
        else => panic("\nlowerBinaryOp unsupported binary op {}\n", .{binary_op}),
    };
}

fn lowerCall(comptime FS: type, context: Context(FS), call: Entity) !Entity {
    const callable = call.get(components.Callable).entity;
    const top_level = context.ast.get(components.TopLevel);
    const literal = callable.get(components.Literal);
    const overloads = top_level.findLiteral(literal).get(components.Overloads).slice();
    assert(overloads.len == 1);
    const function = overloads[0];
    {
        var basic_blocks = components.BasicBlocks.init(context.allocator);
        const basic_block = try context.codebase.createEntity(.{
            components.IrInstructions.init(context.allocator),
            components.Scope.init(context.allocator, context.codebase.getPtr(Strings)),
        });
        _ = try basic_blocks.append(basic_block);
        _ = try function.set(.{basic_blocks});
        const new_context = Context(FS){
            .allocator = context.allocator,
            .codebase = context.codebase,
            .fs = context.fs,
            .ast = context.ast,
            .function = function,
            .basic_block = basic_block,
        };
        // assert(new_context.function.get(components.Parameters).entities.len == 0);
        try lowerFunction(FS, new_context);
    }
    const call_arguments = call.get(components.Arguments).slice();
    var function_arguments = try components.Arguments.withCapacity(context.allocator, call_arguments.len);
    for (call_arguments) |argument| {
        function_arguments.appendAssumeCapacity(try lowerExpression(FS, context, argument));
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

fn lowerDefine(comptime FS: type, context: Context(FS), define: Entity) !Entity {
    const scope = context.basic_block.getPtr(components.Scope);
    const value = try lowerExpression(FS, context, define.get(components.Value).entity);
    if (define.has(components.TypeAst)) |type_ast| {
        const explicit_type = try lowerExpression(FS, context, type_ast.entity);
        const actual_type = value.get(components.Type).entity;
        const builtins = context.codebase.get(components.Builtins);
        if (eql(actual_type, builtins.IntLiteral)) {
            if (eql(explicit_type, builtins.I64) or eql(explicit_type, builtins.U64)) {
                _ = try value.set(.{components.Type.init(explicit_type)});
            } else {
                panic("lower define found invalid explicit type for int literal", .{});
            }
        } else {
            assert(eql(explicit_type, actual_type));
        }
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

fn lowerExpression(comptime FS: type, context: Context(FS), entity: Entity) error{ OutOfMemory, CantOpenFile }!Entity {
    const kind = entity.get(components.AstKind);
    return switch (kind) {
        .symbol => try lowerSymbol(FS, context, entity),
        .int => try lowerInt(FS, context, entity),
        .binary_op => try lowerBinaryOp(FS, context, entity),
        .call => try lowerCall(FS, context, entity),
        .define => try lowerDefine(FS, context, entity),
        else => panic("\nlowerExpression unsupported kind {}\n", .{kind}),
    };
}

fn lowerFunctionParameters(comptime FS: type, context: Context(FS)) !void {
    const scope = context.basic_block.getPtr(components.Scope);
    const parameters = context.function.get(components.Parameters).slice();
    for (parameters) |parameter| {
        const parameter_type = try lowerExpression(FS, context, parameter.get(components.TypeAst).entity);
        _ = try parameter.set(.{components.Type.init(parameter_type)});
        try scope.putLiteral(parameter.get(components.Literal), parameter);
    }
}

fn lowerFunctionReturnType(comptime FS: type, context: Context(FS)) !Entity {
    const return_type = try lowerExpression(FS, context, context.function.get(components.ReturnTypeAst).entity);
    _ = try context.function.set(.{components.ReturnType.init(return_type)});
    return return_type;
}

fn lowerFunctionBody(comptime FS: type, context: Context(FS)) !Entity {
    const body = context.function.get(components.Body).slice();
    var return_entity: Entity = undefined;
    for (body) |expression| {
        return_entity = try lowerExpression(FS, context, expression);
    }
    return return_entity;
}

fn lowerFunction(comptime FS: type, context: Context(FS)) !void {
    _ = try context.function.set(.{components.Module.init(context.ast)});
    _ = try context.codebase.getPtr(components.Functions).append(context.function);
    try lowerFunctionParameters(FS, context);
    const return_type = try lowerFunctionReturnType(FS, context);
    const return_entity = try lowerFunctionBody(FS, context);
    const return_entity_type = typeOf(return_entity);
    if (eql(return_entity_type, return_type)) return;
    const builtins = context.codebase.get(components.Builtins);
    if (eql(return_entity_type, builtins.IntLiteral) and eql(return_type, builtins.I64)) {
        _ = try return_entity.set(.{components.Type.init(builtins.I64)});
        return;
    }
    panic("\n\nTYPE ERROR: declared return type {s} actual return type {s}\n\n", .{
        literalOf(return_type),
        literalOf(return_entity_type),
    });
}

pub fn lower(codebase: *ECS, fs: anytype, module_name: []const u8, function_name: []const u8) !Entity {
    const FS = @TypeOf(fs);
    try initBuiltins(codebase);
    _ = try codebase.set(.{components.Functions.init(&codebase.arena.allocator)});
    const contents = try fs.read(module_name);
    var tokens = try tokenize(codebase, contents);
    const ast = try parse(codebase, &tokens);
    const interned = try codebase.getPtr(Strings).intern(module_name[0 .. module_name.len - 5]);
    _ = try ast.set(.{components.Literal.init(interned)});
    const top_level = ast.get(components.TopLevel);
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
    const context = Context(FS){
        .allocator = allocator,
        .codebase = codebase,
        .fs = fs,
        .ast = ast,
        .function = function,
        .basic_block = basic_block,
    };
    try lowerFunction(FS, context);
    return ast;
}

test "lower int literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try FileSystem.init(&arena);
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
    var fs = try FileSystem.init(&arena);
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
    var fs = try FileSystem.init(&arena);
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
    var fs = try FileSystem.init(&arena);
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
    var fs = try FileSystem.init(&arena);
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
    var fs = try FileSystem.init(&arena);
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
    var fs = try FileSystem.init(&arena);
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
    try expectEqualStrings(literalOf(x), "x");
    try expectEqual(x.get(components.Type).entity, builtins.I64);
    try expectEqual(id.get(components.ReturnType).entity, builtins.I64);
    const basic_blocks = id.get(components.BasicBlocks).slice();
    try expectEqual(basic_blocks.len, 1);
    const basic_block = basic_blocks[0].get(components.IrInstructions).slice();
    try expectEqual(basic_block.len, 1);
    const get_local = basic_block[0];
    try expectEqual(get_local.get(components.IrInstructionKind), .get_local);
    try expectEqual(get_local.get(components.Result).entity, x);
}
