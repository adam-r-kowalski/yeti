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
const file_system = @import("file_system.zig");
const initFileSystem = file_system.initFileSystem;
const newFile = file_system.newFile;
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
    allocator: *Allocator,
};

fn codegenIntConst(context: Context, ir_instruction: Entity) !Entity {
    const builtins = context.codebase.get(components.Builtins);
    const int_const = ir_instruction.get(components.Result).entity;
    const type_of = int_const.get(components.Type).entity;
    if (eql(type_of, builtins.I64)) {
        const wasm_instruction = try context.codebase.createEntity(.{
            components.WasmInstructionKind.i64_const,
            components.Result.init(int_const),
        });
        _ = try context.wasm_instructions.append(wasm_instruction);
        return int_const;
    } else {
        panic("\ncompiler bug in codegen int_const\n", .{});
    }
}

fn codegenRet(ir_instruction: Entity, on_stack: Entity) !void {
    const result = ir_instruction.get(components.Result).entity;
    assert(eql(result, on_stack));
}

pub fn codegen(codebase: *ECS, ir: Entity) !Entity {
    const allocator = &codebase.arena.allocator;
    for (codebase.get(components.Functions).slice()) |function| {
        var wasm_instructions = components.WasmInstructions.init(allocator);
        const context = Context{
            .codebase = codebase,
            .wasm_instructions = &wasm_instructions,
            .allocator = allocator,
        };
        const basic_blocks = function.get(components.BasicBlocks).slice();
        try expectEqual(basic_blocks.len, 1);
        const basic_block = basic_blocks[0].get(components.IrInstructions).slice();
        try expectEqual(basic_block.len, 2);
        var on_stack: Entity = undefined;
        for (basic_block) |ir_instruction| {
            const kind = ir_instruction.get(components.IrInstructionKind);
            switch (kind) {
                .int_const => on_stack = try codegenIntConst(context, ir_instruction),
                .ret => try codegenRet(ir_instruction, on_stack),
                else => panic("\nunsupported instruction kind {}\n", .{kind}),
            }
        }
        _ = try function.set(.{wasm_instructions});
    }
    return ir;
}

pub fn wasmString(codebase: *ECS, wasm: Entity) ![]u8 {
    var string = List(u8, .{}).init(&codebase.arena.allocator);
    try string.appendSlice("(module");
    for (codebase.get(components.Functions).slice()) |function| {
        try string.appendSlice("\n\n  (func $");
        const module_name = literalOf(function.get(components.Module).entity);
        try string.appendSlice(module_name);
        try string.append('/');
        const function_name = literalOf(function.get(components.Name).entity);
        try string.appendSlice(function_name);
        try string.appendSlice(" (result ");
        const return_type = literalOf(function.get(components.ReturnType).entity);
        try string.appendSlice(return_type);
        try string.append(')');
        for (function.get(components.WasmInstructions).slice()) |wasm_instruction| {
            switch (wasm_instruction.get(components.WasmInstructionKind)) {
                .i64_const => {
                    try string.appendSlice("\n    (i64.const ");
                    try string.appendSlice(literalOf(wasm_instruction.get(components.Result).entity));
                    try string.append(')');
                },
            }
        }
        try string.append(')');
    }
    try string.appendSlice("\n\n(export \"_start\" (func $");
    try string.appendSlice(literalOf(wasm));
    try string.appendSlice("/start)))");
    return string.mutSlice();
}

test "return int literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try initFileSystem(&arena);
    _ = try newFile(&fs, "foo.yeti",
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
    const wasm_string = try wasmString(codebase, wasm);
    // TODO: the (result I64) should be (result i64)
    // TODO: map yeti types to wasm types
    try expectEqualStrings(wasm_string,
        \\(module
        \\
        \\  (func $foo/start (result I64)
        \\    (i64.const 5))
        \\
        \\(export "_start" (func $foo/start)))
    );
}
