const std = @import("std");
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const Arena = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;
const eql = std.meta.eql;
const panic = std.debug.panic;
const assert = std.debug.assert;

const init_codebase = @import("init_codebase.zig");
const initCodebase = init_codebase.initCodebase;
const FileSystem = @import("file_system.zig").FileSystem;
const lower = @import("lower.zig").lower;
const ecs = @import("ecs.zig");
const Entity = ecs.Entity;
const ECS = ecs.ECS;
const components = @import("components.zig");
const test_utils = @import("test_utils.zig");
const literalOf = test_utils.literalOf;
const List = @import("list.zig").List;

const Context = struct {
    codebase: *ECS,
    wasm_instructions: *components.WasmInstructions,
    locals: *components.Locals,
    allocator: *Allocator,
    builtins: components.Builtins,
};

fn codegenIntConst(context: Context, ir_instruction: Entity) !void {
    const int_const = ir_instruction.get(components.Result).entity;
    const type_of = int_const.get(components.Type).entity;
    if (eql(type_of, context.builtins.I64)) {
        const wasm_instruction = try context.codebase.createEntity(.{
            components.WasmInstructionKind.i64_const,
            components.Result.init(int_const),
        });
        _ = try context.wasm_instructions.append(wasm_instruction);
        return;
    }
    if (eql(type_of, context.builtins.IntLiteral)) {
        return;
    }
    panic("\ncompiler bug in codegen int_const\n", .{});
}

fn codegenCall(context: Context, ir_instruction: Entity) !void {
    const wasm_instruction = try context.codebase.createEntity(.{
        components.WasmInstructionKind.call,
        ir_instruction.get(components.Callable),
    });
    _ = try context.wasm_instructions.append(wasm_instruction);
}

fn codegenGetLocal(context: Context, ir_instruction: Entity) !void {
    const local = ir_instruction.get(components.Result).entity;
    const type_of = local.get(components.Type).entity;
    if (eql(type_of, context.builtins.I64)) {
        const wasm_instruction = try context.codebase.createEntity(.{
            components.WasmInstructionKind.get_local,
            components.Result.init(local),
        });
        _ = try context.wasm_instructions.append(wasm_instruction);
        try context.locals.put(local);
        return;
    }
    panic("\ncodegen get local type not supported {s}\n", .{literalOf(type_of)});
}

fn codegenSetLocal(context: Context, ir_instruction: Entity) !void {
    const local = ir_instruction.get(components.Result).entity;
    const type_of = local.get(components.Type).entity;
    if (eql(type_of, context.builtins.I64)) {
        const wasm_instruction = try context.codebase.createEntity(.{
            components.WasmInstructionKind.set_local,
            components.Result.init(local),
        });
        _ = try context.wasm_instructions.append(wasm_instruction);
        try context.locals.put(local);
        return;
    }
    if (eql(type_of, context.builtins.IntLiteral)) {
        return;
    }
    panic("\ncodegen set local type not supported {s}\n", .{literalOf(type_of)});
}

pub fn codegen(ir: Entity) !Entity {
    const codebase = ir.ecs;
    const allocator = &codebase.arena.allocator;
    const builtins = codebase.get(components.Builtins);
    for (ir.ecs.get(components.Functions).slice()) |function| {
        var locals = components.Locals.init(allocator);
        var wasm_instructions = components.WasmInstructions.init(allocator);
        const context = Context{
            .codebase = codebase,
            .wasm_instructions = &wasm_instructions,
            .locals = &locals,
            .allocator = allocator,
            .builtins = builtins,
        };
        const basic_blocks = function.get(components.BasicBlocks).slice();
        try expectEqual(basic_blocks.len, 1);
        const basic_block = basic_blocks[0].get(components.IrInstructions).slice();
        for (basic_block) |ir_instruction| {
            const kind = ir_instruction.get(components.IrInstructionKind);
            switch (kind) {
                .int_const => try codegenIntConst(context, ir_instruction),
                .call => try codegenCall(context, ir_instruction),
                .get_local => try codegenGetLocal(context, ir_instruction),
                .set_local => try codegenSetLocal(context, ir_instruction),
            }
        }
        _ = try function.set(.{ wasm_instructions, locals });
    }
    return ir;
}

test "codegen int literal" {
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
    const wasm = try codegen(ir);
    const top_level = wasm.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    const wasm_instructions = start.get(components.WasmInstructions).slice();
    try expectEqual(wasm_instructions.len, 1);
    const i64_const = wasm_instructions[0];
    try expectEqual(i64_const.get(components.WasmInstructionKind), .i64_const);
    try expectEqualStrings(literalOf(i64_const.get(components.Result).entity), "5");
}

test "codegen call local function" {
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
    const wasm = try codegen(ir);
    const top_level = wasm.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    const start_instructions = start.get(components.WasmInstructions).slice();
    try expectEqual(start_instructions.len, 1);
    const call = start_instructions[0];
    try expectEqual(call.get(components.WasmInstructionKind), .call);
    const baz = call.get(components.Callable).entity;
    const baz_instructions = baz.get(components.WasmInstructions).slice();
    try expectEqual(baz_instructions.len, 1);
    const i64_const = baz_instructions[0];
    try expectEqual(i64_const.get(components.WasmInstructionKind), .i64_const);
    try expectEqualStrings(literalOf(i64_const.get(components.Result).entity), "10");
}

test "codegen call function from import" {
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
    const wasm = try codegen(ir);
    const top_level = wasm.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    const start_instructions = start.get(components.WasmInstructions).slice();
    try expectEqual(start_instructions.len, 1);
    try expectEqual(start_instructions.len, 1);
    const call = start_instructions[0];
    try expectEqual(call.get(components.WasmInstructionKind), .call);
    const baz = call.get(components.Callable).entity;
    const baz_instructions = baz.get(components.WasmInstructions).slice();
    try expectEqual(baz_instructions.len, 1);
    const i64_const = baz_instructions[0];
    try expectEqual(i64_const.get(components.WasmInstructionKind), .i64_const);
    try expectEqualStrings(literalOf(i64_const.get(components.Result).entity), "10");
}

test "codegen assignment" {
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
    const wasm = try codegen(ir);
    const top_level = wasm.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    const start_instructions = start.get(components.WasmInstructions).slice();
    try expectEqual(start_instructions.len, 3);
    const i64_const = start_instructions[0];
    try expectEqual(i64_const.get(components.WasmInstructionKind), .i64_const);
    try expectEqualStrings(literalOf(i64_const.get(components.Result).entity), "10");
    const set_local = start_instructions[1];
    try expectEqual(set_local.get(components.WasmInstructionKind), .set_local);
    try expectEqualStrings(literalOf(set_local.get(components.Result).entity.get(components.Name).entity), "x");
    const get_local = start_instructions[2];
    try expectEqual(get_local.get(components.WasmInstructionKind), .get_local);
    try expectEqualStrings(literalOf(get_local.get(components.Result).entity.get(components.Name).entity), "x");
}

test "codegen two assignments" {
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
    const wasm = try codegen(ir);
    const top_level = wasm.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    const start_instructions = start.get(components.WasmInstructions).slice();
    try expectEqual(start_instructions.len, 3);
    const i64_const = start_instructions[0];
    try expectEqual(i64_const.get(components.WasmInstructionKind), .i64_const);
    const x = i64_const.get(components.Result).entity;
    try expectEqualStrings(literalOf(x), "10");
    const set_local = start_instructions[1];
    try expectEqual(set_local.get(components.WasmInstructionKind), .set_local);
    try expectEqual(set_local.get(components.Result).entity, x);
    const get_local = start_instructions[2];
    try expectEqual(get_local.get(components.WasmInstructionKind), .get_local);
    try expectEqual(get_local.get(components.Result).entity, x);
}

test "codegen assignment explicit type" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try FileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = function(): I64
        \\  x: I64 = 10
        \\  x
        \\end
    );
    const ir = try lower(codebase, fs, "foo.yeti", "start");
    const wasm = try codegen(ir);
    const top_level = wasm.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    const start_instructions = start.get(components.WasmInstructions).slice();
    try expectEqual(start_instructions.len, 3);
    const i64_const = start_instructions[0];
    try expectEqual(i64_const.get(components.WasmInstructionKind), .i64_const);
    const x = i64_const.get(components.Result).entity;
    try expectEqualStrings(literalOf(x), "10");
    const set_local = start_instructions[1];
    try expectEqual(set_local.get(components.WasmInstructionKind), .set_local);
    try expectEqual(set_local.get(components.Result).entity, x);
    const get_local = start_instructions[2];
    try expectEqual(get_local.get(components.WasmInstructionKind), .get_local);
    try expectEqual(get_local.get(components.Result).entity, x);
}

test "codegen function with argument" {
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
    const wasm = try codegen(ir);
    const top_level = wasm.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    const start_instructions = start.get(components.WasmInstructions).slice();
    try expectEqual(start_instructions.len, 4);
    const i64_const = start_instructions[0];
    try expectEqual(i64_const.get(components.WasmInstructionKind), .i64_const);
    const x = i64_const.get(components.Result).entity;
    try expectEqualStrings(literalOf(x), "10");
    const set_local = start_instructions[1];
    try expectEqual(set_local.get(components.WasmInstructionKind), .set_local);
    try expectEqual(set_local.get(components.Result).entity, x);
    const get_local = start_instructions[2];
    try expectEqual(get_local.get(components.WasmInstructionKind), .get_local);
    try expectEqual(get_local.get(components.Result).entity, x);
    const call = start_instructions[3];
    try expectEqual(call.get(components.WasmInstructionKind), .call);
    const id = call.get(components.Callable).entity;
    try expectEqualStrings(literalOf(id.get(components.Name).entity), "id");
    const id_instructions = id.get(components.WasmInstructions).slice();
    try expectEqual(id_instructions.len, 1);
    const id_get_local = id_instructions[0];
    try expectEqual(id_get_local.get(components.WasmInstructionKind), .get_local);
    try expectEqualStrings(literalOf(id_get_local.get(components.Result).entity.get(components.Name).entity), "x");
}
