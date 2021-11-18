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

const Stack = List(Entity, .{});

const Context = struct {
    codebase: *ECS,
    wasm_instructions: *components.WasmInstructions,
    allocator: *Allocator,
    builtins: components.Builtins,
    stack: *Stack,
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
        try context.stack.append(int_const);
        return;
    }
    if (eql(type_of, context.builtins.IntLiteral)) {
        return;
    }
    panic("\ncompiler bug in codegen int_const\n", .{});
}

fn codegenCall(context: Context, ir_instruction: Entity) !void {
    for (ir_instruction.get(components.Arguments).slice()) |argument| {
        const type_ = argument.get(components.Type).entity;
        if (eql(type_, context.builtins.I64)) {
            const wasm_instruction = try context.codebase.createEntity(.{
                components.WasmInstructionKind.i64_const,
                components.Result.init(argument),
            });
            _ = try context.wasm_instructions.append(wasm_instruction);
        } else {
            panic("codegen call unsupported argument type", .{});
        }
    }
    const wasm_instruction = try context.codebase.createEntity(.{
        components.WasmInstructionKind.call,
        ir_instruction.get(components.Callable),
    });
    _ = try context.wasm_instructions.append(wasm_instruction);
    try context.stack.append(ir_instruction.get(components.Result).entity);
}

fn codegenRet(context: Context, ir_instruction: Entity) !void {
    const result = ir_instruction.get(components.Result);
    if (context.stack.len > 0 and eql(context.stack.last(), result.entity)) {
        return;
    }
    // const wasm_instruction = try context.codebase.createEntity(.{
    //     components.WasmInstructionKind.get_local,
    //     result,
    // });
    // _ = try context.wasm_instructions.append(wasm_instruction);
}

pub fn codegen(codebase: *ECS, ir: Entity) !Entity {
    const allocator = &codebase.arena.allocator;
    for (codebase.get(components.Functions).slice()) |function| {
        var wasm_instructions = components.WasmInstructions.init(allocator);
        var stack = Stack.init(allocator);
        const context = Context{
            .codebase = codebase,
            .wasm_instructions = &wasm_instructions,
            .allocator = allocator,
            .builtins = codebase.get(components.Builtins),
            .stack = &stack,
        };
        const basic_blocks = function.get(components.BasicBlocks).slice();
        try expectEqual(basic_blocks.len, 1);
        const basic_block = basic_blocks[0].get(components.IrInstructions).slice();
        for (basic_block) |ir_instruction| {
            const kind = ir_instruction.get(components.IrInstructionKind);
            switch (kind) {
                .int_const => try codegenIntConst(context, ir_instruction),
                .call => try codegenCall(context, ir_instruction),
                .ret => try codegenRet(context, ir_instruction),
            }
        }
        _ = try function.set(.{wasm_instructions});
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
    const wasm = try codegen(codebase, ir);
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
    const wasm = try codegen(codebase, ir);
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
    const wasm = try codegen(codebase, ir);
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
    const wasm = try codegen(codebase, ir);
    const top_level = wasm.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    const start_instructions = start.get(components.WasmInstructions).slice();
    try expectEqual(start_instructions.len, 1);
    const i64_const = start_instructions[0];
    try expectEqual(i64_const.get(components.WasmInstructionKind), .i64_const);
    try expectEqualStrings(literalOf(i64_const.get(components.Result).entity), "10");
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
    const wasm = try codegen(codebase, ir);
    const top_level = wasm.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    const start_instructions = start.get(components.WasmInstructions).slice();
    try expectEqual(start_instructions.len, 1);
    const i64_const = start_instructions[0];
    try expectEqual(i64_const.get(components.WasmInstructionKind), .i64_const);
    try expectEqualStrings(literalOf(i64_const.get(components.Result).entity), "10");
}

// test "codegen assignment explicit type" {
//     var arena = Arena.init(std.heap.page_allocator);
//     defer arena.deinit();
//     var codebase = try initCodebase(&arena);
//     var fs = try FileSystem.init(&arena);
//     _ = try fs.newFile("foo.yeti",
//         \\start = function(): I64
//         \\  x: I64 = 10
//         \\  x
//         \\end
//     );
//     const ir = try lower(codebase, fs, "foo.yeti", "start");
//     const wasm = try codegen(codebase, ir);
//     const top_level = wasm.get(components.TopLevel);
//     const start = top_level.findString("start").get(components.Overloads).slice()[0];
//     const start_instructions = start.get(components.WasmInstructions).slice();
//     try expectEqual(start_instructions.len, 3);
//     const i64_const = start_instructions[0];
//     try expectEqual(i64_const.get(components.WasmInstructionKind), .i64_const);
//     try expectEqualStrings(literalOf(i64_const.get(components.Result).entity), "10");
//     const set_local = start_instructions[1];
//     try expectEqual(set_local.get(components.WasmInstructionKind), .set_local);
// }

// test "codegen function with argument" {
//     var arena = Arena.init(std.heap.page_allocator);
//     defer arena.deinit();
//     var codebase = try initCodebase(&arena);
//     var fs = try FileSystem.init(&arena);
//     _ = try fs.newFile("foo.yeti",
//         \\start = function(): I64
//         \\  x: I64 = 10
//         \\  id(x)
//         \\end
//         \\
//         \\id = function(x: I64): I64
//         \\  x
//         \\end
//     );
//     const ir = try lower(codebase, fs, "foo.yeti", "start");
//     const wasm = try codegen(codebase, ir);
//     const top_level = wasm.get(components.TopLevel);
//     const start = top_level.findString("start").get(components.Overloads).slice()[0];
//     const start_instructions = start.get(components.WasmInstructions).slice();
//     try expectEqual(start_instructions.len, 3);
//     const i64_const = start_instructions[0];
//     try expectEqual(i64_const.get(components.WasmInstructionKind), .i64_const);
//     try expectEqualStrings(literalOf(i64_const.get(components.Result).entity), "10");
//     try expectEqual(i64_const.get(components.WasmInstructionKind), .i64_const);
//     try expectEqualStrings(literalOf(i64_const.get(components.Result).entity), "10");
// }
