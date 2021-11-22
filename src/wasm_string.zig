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
const strings_module = @import("strings.zig");
const Strings = strings_module.Strings;
const InternedString = strings_module.InternedString;

const WasmString = List(u8, .{ .initial_capacity = 1000 });

fn wasmStringType(string: *WasmString, type_: Entity) !void {
    const builtins = type_.ecs.get(components.Builtins);
    if (eql(type_, builtins.I64)) {
        try string.appendSlice("i64");
    } else if (eql(type_, builtins.U64)) {
        try string.appendSlice("u64");
    } else {
        panic("\nwasm string unsupported type {s}\n", .{literalOf(type_)});
    }
}

fn wasmStringFunctionName(string: *WasmString, function: Entity) !void {
    try string.appendSlice("\n\n  (func $");
    try string.appendSlice(literalOf(function.get(components.Module).entity));
    try string.append('/');
    try string.appendSlice(literalOf(function.get(components.Name).entity));
}

fn wasmStringFunctionParameters(string: *WasmString, function: Entity) !void {
    for (function.get(components.Parameters).slice()) |parameter| {
        try string.appendSlice(" (param $");
        try string.appendSlice(literalOf(parameter.get(components.Name).entity));
        try string.append(' ');
        try wasmStringType(string, parameter.get(components.Type).entity);
        try string.append(')');
    }
}

fn wasmStringFunctionReturnType(string: *WasmString, function: Entity) !void {
    try string.appendSlice(" (result ");
    try wasmStringType(string, function.get(components.ReturnType).entity);
    try string.append(')');
}

fn wasmStringFunctionLocals(string: *WasmString, function: Entity) !void {
    const parameters = function.get(components.Parameters).slice();
    const parameter_names = try function.ecs.arena.allocator.alloc(InternedString, parameters.len);
    for (parameters) |parameter, i| {
        parameter_names[i] = parameter.get(components.Name).entity.get(components.Literal).interned;
    }
    const strings = function.ecs.get(Strings);
    var locals = function.get(components.Locals).iterate();
    while (locals.next()) |local| {
        const local_name = local.get(components.Name).entity.get(components.Literal).interned;
        var found = false;
        for (parameter_names) |parameter_name| {
            if (eql(parameter_name, local_name)) {
                found = true;
            }
        }
        if (found) {
            continue;
        }
        try string.appendSlice("\n    (local $");
        try string.appendSlice(strings.get(local_name));
        try string.append(' ');
        try wasmStringType(string, local.get(components.Type).entity);
        try string.append(')');
    }
}

fn wasmStringInstruction(string: *WasmString, wasm_instruction: Entity) !void {
    switch (wasm_instruction.get(components.WasmInstructionKind)) {
        .i64_const => {
            try string.appendSlice("\n    (i64.const ");
            try string.appendSlice(literalOf(wasm_instruction.get(components.Result).entity));
            try string.append(')');
        },
        .u64_const => {
            try string.appendSlice("\n    (u64.const ");
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
        .get_local => {
            try string.appendSlice("\n    (get_local $");
            const result = wasm_instruction.get(components.Result).entity;
            try string.appendSlice(literalOf(result.get(components.Name).entity));
            try string.append(')');
        },
        .set_local => {
            try string.appendSlice("\n    (set_local $");
            const result = wasm_instruction.get(components.Result).entity;
            try string.appendSlice(literalOf(result.get(components.Name).entity));
            try string.append(')');
        },
    }
}

fn wasmStringFunction(string: *WasmString, function: Entity) !void {
    try wasmStringFunctionName(string, function);
    try wasmStringFunctionParameters(string, function);
    try wasmStringFunctionReturnType(string, function);
    try wasmStringFunctionLocals(string, function);
    for (function.get(components.WasmInstructions).slice()) |wasm_instruction| {
        try wasmStringInstruction(string, wasm_instruction);
    }
    try string.append(')');
}

pub fn wasmString(wasm: Entity) ![]u8 {
    const codebase = wasm.ecs;
    var string = WasmString.init(&codebase.arena.allocator);
    try string.appendSlice("(module");
    for (codebase.get(components.Functions).slice()) |function| {
        try wasmStringFunction(&string, function);
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
    const wasm = try codegen(ir);
    const wasm_string = try wasmString(wasm);
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
    const wasm = try codegen(ir);
    const wasm_string = try wasmString(wasm);
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
    const wasm = try codegen(ir);
    const wasm_string = try wasmString(wasm);
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
    const wasm = try codegen(ir);
    const wasm_string = try wasmString(wasm);
    try expectEqualStrings(wasm_string,
        \\(module
        \\
        \\  (func $foo/start (result i64)
        \\    (local $x i64)
        \\    (i64.const 10)
        \\    (set_local $x)
        \\    (get_local $x))
        \\
        \\(export "_start" (func $foo/start)))
    );
}

test "wasm string function with argument" {
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
    const wasm_string = try wasmString(wasm);
    try expectEqualStrings(wasm_string,
        \\(module
        \\
        \\  (func $foo/start (result i64)
        \\    (local $x i64)
        \\    (i64.const 10)
        \\    (set_local $x)
        \\    (get_local $x)
        \\    (call $foo/id))
        \\
        \\  (func $foo/id (param $x i64) (result i64)
        \\    (get_local $x))
        \\
        \\(export "_start" (func $foo/start)))
    );
}

test "wasm string function with argument implicit type" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try FileSystem.init(&arena);
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
    const wasm = try codegen(ir);
    const wasm_string = try wasmString(wasm);
    try expectEqualStrings(wasm_string,
        \\(module
        \\
        \\  (func $foo/start (result i64)
        \\    (local $x i64)
        \\    (i64.const 10)
        \\    (set_local $x)
        \\    (get_local $x)
        \\    (call $foo/id))
        \\
        \\  (func $foo/id (param $x i64) (result i64)
        \\    (get_local $x))
        \\
        \\(export "_start" (func $foo/start)))
    );
}

test "wasm string function with int literal argument" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try FileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = function(): I64
        \\  id(10)
        \\end
        \\
        \\id = function(x: I64): I64
        \\  x
        \\end
    );
    const ir = try lower(codebase, fs, "foo.yeti", "start");
    const wasm = try codegen(ir);
    const wasm_string = try wasmString(wasm);
    try expectEqualStrings(wasm_string,
        \\(module
        \\
        \\  (func $foo/start (result i64)
        \\    (i64.const 10)
        \\    (call $foo/id))
        \\
        \\  (func $foo/id (param $x i64) (result i64)
        \\    (get_local $x))
        \\
        \\(export "_start" (func $foo/start)))
    );
}

test "codegen function with U64 argument" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try FileSystem.init(&arena);
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
    const wasm = try codegen(ir);
    const wasm_string = try wasmString(wasm);
    try expectEqualStrings(wasm_string,
        \\(module
        \\
        \\  (func $foo/start (result u64)
        \\    (local $x u64)
        \\    (u64.const 10)
        \\    (set_local $x)
        \\    (get_local $x)
        \\    (call $foo/id))
        \\
        \\  (func $foo/id (param $x u64) (result u64)
        \\    (get_local $x))
        \\
        \\(export "_start" (func $foo/start)))
    );
}
