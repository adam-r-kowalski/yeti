const std = @import("std");
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const Arena = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;
const eql = std.meta.eql;
const panic = std.debug.panic;
const assert = std.debug.assert;

const initCodebase = @import("init_codebase.zig").initCodebase;
const MockFileSystem = @import("file_system.zig").FileSystem;
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
    if (eql(type_, builtins.I64) or eql(type_, builtins.U64)) {
        try string.appendSlice("i64");
    } else if (eql(type_, builtins.I32) or eql(type_, builtins.U32)) {
        try string.appendSlice("i32");
    } else if (eql(type_, builtins.F64)) {
        try string.appendSlice("f64");
    } else if (eql(type_, builtins.F32)) {
        try string.appendSlice("f32");
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
    for (function.get(components.Locals).slice()) |local| {
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
        .i32_const => {
            try string.appendSlice("\n    (i32.const ");
            try string.appendSlice(literalOf(wasm_instruction.get(components.Result).entity));
            try string.append(')');
        },
        .f64_const => {
            try string.appendSlice("\n    (f64.const ");
            try string.appendSlice(literalOf(wasm_instruction.get(components.Result).entity));
            try string.append(')');
        },
        .f32_const => {
            try string.appendSlice("\n    (f32.const ");
            try string.appendSlice(literalOf(wasm_instruction.get(components.Result).entity));
            try string.append(')');
        },
        .i64_add => try string.appendSlice("\n    (i64.add)"),
        .i32_add => try string.appendSlice("\n    (i32.add)"),
        .f64_add => try string.appendSlice("\n    (f64.add)"),
        .f32_add => try string.appendSlice("\n    (f32.add)"),
        .i64_sub => try string.appendSlice("\n    (i64.sub)"),
        .i32_sub => try string.appendSlice("\n    (i32.sub)"),
        .f64_sub => try string.appendSlice("\n    (f64.sub)"),
        .f32_sub => try string.appendSlice("\n    (f32.sub)"),
        .i64_mul => try string.appendSlice("\n    (i64.mul)"),
        .i32_mul => try string.appendSlice("\n    (i32.mul)"),
        .f64_mul => try string.appendSlice("\n    (f64.mul)"),
        .f32_mul => try string.appendSlice("\n    (f32.mul)"),
        .i64_div => try string.appendSlice("\n    (i64.div_s)"),
        .i32_div => try string.appendSlice("\n    (i32.div_s)"),
        .u64_div => try string.appendSlice("\n    (i64.div_u)"),
        .u32_div => try string.appendSlice("\n    (i32.div_u)"),
        .f64_div => try string.appendSlice("\n    (f64.div)"),
        .f32_div => try string.appendSlice("\n    (f32.div)"),
        .i64_lt => try string.appendSlice("\n    (i64.lt_s)"),
        .i32_lt => try string.appendSlice("\n    (i32.lt_s)"),
        .u64_lt => try string.appendSlice("\n    (i64.lt_u)"),
        .u32_lt => try string.appendSlice("\n    (i32.lt_u)"),
        .f64_lt => try string.appendSlice("\n    (f64.lt)"),
        .f32_lt => try string.appendSlice("\n    (f32.lt)"),
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
    const types = [_][]const u8{ "I64", "I32", "U64", "U32", "F64", "F32" };
    const wasm_types = [_][]const u8{ "i64", "i32", "i64", "i32", "f64", "f32" };
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(&arena.allocator,
            \\start = function(): {s}
            \\  5
            \\end
        , .{type_}));
        const module = try lower(codebase, fs, "foo.yeti", "start");
        try codegen(module);
        const wasm_string = try wasmString(module);
        try expectEqualStrings(wasm_string, try std.fmt.allocPrint(&arena.allocator,
            \\(module
            \\
            \\  (func $foo/start (result {s})
            \\    ({s}.const 5))
            \\
            \\(export "_start" (func $foo/start)))
        , .{ wasm_types[i], wasm_types[i] }));
    }
}

test "wasm string float literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "F64", "F32" };
    const wasm_types = [_][]const u8{ "f64", "f32" };
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(&arena.allocator,
            \\start = function(): {s}
            \\  5.3
            \\end
        , .{type_}));
        const module = try lower(codebase, fs, "foo.yeti", "start");
        try codegen(module);
        const wasm_string = try wasmString(module);
        try expectEqualStrings(wasm_string, try std.fmt.allocPrint(&arena.allocator,
            \\(module
            \\
            \\  (func $foo/start (result {s})
            \\    ({s}.const 5.3))
            \\
            \\(export "_start" (func $foo/start)))
        , .{ wasm_types[i], wasm_types[i] }));
    }
}

test "wasm string call local function" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "F64", "F32" };
    const wasm_types = [_][]const u8{ "f64", "f32" };
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
        const module = try lower(codebase, fs, "foo.yeti", "start");
        try codegen(module);
        const wasm_string = try wasmString(module);
        try expectEqualStrings(wasm_string, try std.fmt.allocPrint(&arena.allocator,
            \\(module
            \\
            \\  (func $foo/start (result {s})
            \\    (call $foo/baz))
            \\
            \\  (func $foo/baz (result {s})
            \\    ({s}.const 10))
            \\
            \\(export "_start" (func $foo/start)))
        , .{ wasm_types[i], wasm_types[i], wasm_types[i] }));
    }
}

test "wasm string call function from import" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{"F64"};
    const wasm_types = [_][]const u8{"f64"};
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
        const module = try lower(codebase, fs, "foo.yeti", "start");
        try codegen(module);
        const wasm_string = try wasmString(module);
        try expectEqualStrings(wasm_string, try std.fmt.allocPrint(&arena.allocator,
            \\(module
            \\
            \\  (func $foo/start (result {s})
            \\    (call $bar/baz))
            \\
            \\  (func $bar/baz (result {s})
            \\    ({s}.const 10))
            \\
            \\(export "_start" (func $foo/start)))
        , .{ wasm_types[i], wasm_types[i], wasm_types[i] }));
    }
}

test "wasm string assignment" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "I64", "U64", "F64" };
    const wasm_types = [_][]const u8{ "i64", "i64", "f64" };
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(&arena.allocator,
            \\start = function(): {s}
            \\  x = 10
            \\  x
            \\end
        , .{type_}));
        const module = try lower(codebase, fs, "foo.yeti", "start");
        try codegen(module);
        const wasm_string = try wasmString(module);
        try expectEqualStrings(wasm_string, try std.fmt.allocPrint(&arena.allocator,
            \\(module
            \\
            \\  (func $foo/start (result {s})
            \\    (local $x {s})
            \\    ({s}.const 10)
            \\    (set_local $x)
            \\    (get_local $x))
            \\
            \\(export "_start" (func $foo/start)))
        , .{ wasm_types[i], wasm_types[i], wasm_types[i] }));
    }
}

test "wasm string function with argument" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "I64", "U64", "F64" };
    const wasm_types = [_][]const u8{ "i64", "i64", "f64" };
    for (types) |type_, i| {
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
        , .{ type_, type_, type_, type_ }));
        const module = try lower(codebase, fs, "foo.yeti", "start");
        try codegen(module);
        const wasm_string = try wasmString(module);
        try expectEqualStrings(wasm_string, try std.fmt.allocPrint(&arena.allocator,
            \\(module
            \\
            \\  (func $foo/start (result {s})
            \\    (local $x {s})
            \\    ({s}.const 10)
            \\    (set_local $x)
            \\    (get_local $x)
            \\    (call $foo/id))
            \\
            \\  (func $foo/id (param $x {s}) (result {s})
            \\    (get_local $x))
            \\
            \\(export "_start" (func $foo/start)))
        , .{ wasm_types[i], wasm_types[i], wasm_types[i], wasm_types[i], wasm_types[i] }));
    }
}

test "wasm string function with argument implicit type" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "I64", "U64", "F64" };
    const wasm_types = [_][]const u8{ "i64", "i64", "f64" };
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(&arena.allocator,
            \\start = function(): {s}
            \\  x = 10
            \\  id(x)
            \\end
            \\
            \\id = function(x: {s}): {s}
            \\  x
            \\end
        , .{ type_, type_, type_ }));
        const module = try lower(codebase, fs, "foo.yeti", "start");
        try codegen(module);
        const wasm_string = try wasmString(module);
        try expectEqualStrings(wasm_string, try std.fmt.allocPrint(&arena.allocator,
            \\(module
            \\
            \\  (func $foo/start (result {s})
            \\    (local $x {s})
            \\    ({s}.const 10)
            \\    (set_local $x)
            \\    (get_local $x)
            \\    (call $foo/id))
            \\
            \\  (func $foo/id (param $x {s}) (result {s})
            \\    (get_local $x))
            \\
            \\(export "_start" (func $foo/start)))
        , .{ wasm_types[i], wasm_types[i], wasm_types[i], wasm_types[i], wasm_types[i] }));
    }
}

test "wasm string function with int literal argument" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "I64", "U64", "F64" };
    const wasm_types = [_][]const u8{ "i64", "i64", "f64" };
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(&arena.allocator,
            \\start = function(): {s}
            \\  id(10)
            \\end
            \\
            \\id = function(x: {s}): {s}
            \\  x
            \\end
        , .{ type_, type_, type_ }));
        const module = try lower(codebase, fs, "foo.yeti", "start");
        try codegen(module);
        const wasm_string = try wasmString(module);
        try expectEqualStrings(wasm_string, try std.fmt.allocPrint(&arena.allocator,
            \\(module
            \\
            \\  (func $foo/start (result {s})
            \\    ({s}.const 10)
            \\    (call $foo/id))
            \\
            \\  (func $foo/id (param $x {s}) (result {s})
            \\    (get_local $x))
            \\
            \\(export "_start" (func $foo/start)))
        , .{ wasm_types[i], wasm_types[i], wasm_types[i], wasm_types[i] }));
    }
}

test "wasm string add" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "I64", "U64", "F64" };
    const wasm_types = [_][]const u8{ "i64", "i64", "f64" };
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(&arena.allocator,
            \\start = function(): {s}
            \\  x: {s} = 10
            \\  y: {s} = 32
            \\  x + y
            \\end
        , .{ type_, type_, type_ }));
        const module = try lower(codebase, fs, "foo.yeti", "start");
        try codegen(module);
        const wasm_string = try wasmString(module);
        try expectEqualStrings(wasm_string, try std.fmt.allocPrint(&arena.allocator,
            \\(module
            \\
            \\  (func $foo/start (result {s})
            \\    (local $x {s})
            \\    (local $y {s})
            \\    ({s}.const 10)
            \\    (set_local $x)
            \\    ({s}.const 32)
            \\    (set_local $y)
            \\    (get_local $x)
            \\    (get_local $y)
            \\    ({s}.add))
            \\
            \\(export "_start" (func $foo/start)))
        , .{ wasm_types[i], wasm_types[i], wasm_types[i], wasm_types[i], wasm_types[i], wasm_types[i] }));
    }
}
