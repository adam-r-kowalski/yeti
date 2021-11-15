const std = @import("std");
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const Arena = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;
const eql = std.meta.eql;
const panic = std.debug.panic;
const assert = std.debug.assert;

const initCodebase = @import("init_codebase.zig").initCodebase;
const FileSystem = @import("file_system.zig").FileSystem;
const lower = @import("lower.zig").lower;
const codegen = @import("codegen.zig").codegen;
const ecs = @import("ecs.zig");
const Entity = ecs.Entity;
const ECS = ecs.ECS;
const components = @import("components.zig");
const test_utils = @import("test_utils.zig");
const literalOf = test_utils.literalOf;
const List = @import("list.zig").List;

const WasmString = List(u8, .{ .initial_capacity = 1000 });

fn wasmStringType(codebase: *ECS, string: *WasmString, type_: Entity) !void {
    const builtins = codebase.get(components.Builtins);
    if (eql(type_, builtins.I64)) {
        try string.appendSlice("i64");
    } else {
        panic("\nwasm string unsupported type {s}\n", .{literalOf(type_)});
    }
}

pub fn wasmString(codebase: *ECS, wasm: Entity) ![]u8 {
    var string = WasmString.init(&codebase.arena.allocator);
    try string.appendSlice("(module");
    for (codebase.get(components.Functions).slice()) |function| {
        try string.appendSlice("\n\n  (func $");
        try string.appendSlice(literalOf(function.get(components.Module).entity));
        try string.append('/');
        try string.appendSlice(literalOf(function.get(components.Name).entity));
        try string.appendSlice(" (result ");
        try wasmStringType(codebase, &string, function.get(components.ReturnType).entity);
        try string.append(')');
        for (function.get(components.WasmInstructions).slice()) |wasm_instruction| {
            switch (wasm_instruction.get(components.WasmInstructionKind)) {
                .i64_const => {
                    try string.appendSlice("\n    (i64.const ");
                    try string.appendSlice(literalOf(wasm_instruction.get(components.Result).entity));
                    try string.append(')');
                },
                .call => {
                    try string.appendSlice("\n    (call $");
                    const callable = wasm_instruction.get(components.Callable).entity;
                    try string.appendSlice(literalOf(callable.get(components.Module).entity));
                    try string.append('/');
                    try string.appendSlice(literalOf(callable.get(components.Name).entity));
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

test "wasm string int literal" {
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
    const wasm_string = try wasmString(codebase, wasm);
    try expectEqualStrings(wasm_string,
        \\(module
        \\
        \\  (func $foo/start (result i64)
        \\    (i64.const 5))
        \\
        \\(export "_start" (func $foo/start)))
    );
}

test "wasm string call local function" {
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
    const wasm_string = try wasmString(codebase, wasm);
    try expectEqualStrings(wasm_string,
        \\(module
        \\
        \\  (func $foo/start (result i64)
        \\    (call $foo/baz))
        \\
        \\  (func $foo/baz (result i64)
        \\    (i64.const 10))
        \\
        \\(export "_start" (func $foo/start)))
    );
}

test "wasm string call function from import" {
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
    const wasm_string = try wasmString(codebase, wasm);
    try expectEqualStrings(wasm_string,
        \\(module
        \\
        \\  (func $foo/start (result i64)
        \\    (call $bar/baz))
        \\
        \\  (func $bar/baz (result i64)
        \\    (i64.const 10))
        \\
        \\(export "_start" (func $foo/start)))
    );
}

test "wasm string assignment" {
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
    const wasm_string = try wasmString(codebase, wasm);
    try expectEqualStrings(wasm_string,
        \\(module
        \\
        \\  (func $foo/start (result i64)
        \\    (i64.const 10))
        \\
        \\(export "_start" (func $foo/start)))
    );
}
