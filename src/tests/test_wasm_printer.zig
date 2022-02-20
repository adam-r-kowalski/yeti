const std = @import("std");
const Arena = std.heap.ArenaAllocator;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const yeti = @import("yeti");
const initCodebase = yeti.initCodebase;
const MockFileSystem = yeti.FileSystem;
const components = yeti.components;
const analyzeSemantics = yeti.analyzeSemantics;
const codegen = yeti.codegen;
const printWasm = yeti.printWasm;

test "print wasm int literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "i64", "i32", "i16", "i8", "u64", "u32", "u16", "u8", "f64", "f32" };
    const wasm_types = [_][]const u8{ "i64", "i32", "i32", "i32", "i64", "i32", "i32", "i32", "f64", "f32" };
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start(): {s} {{
            \\  5
            \\}}
        , .{type_}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        try codegen(module);
        const wasm = try printWasm(module);
        try expectEqualStrings(wasm, try std.fmt.allocPrint(arena.allocator(),
            \\(module
            \\
            \\  (func $foo/start (result {s})
            \\    ({s}.const 5))
            \\
            \\  (export "_start" (func $foo/start)))
        , .{ wasm_types[i], wasm_types[i] }));
    }
}

test "print wasm float literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "f64", "f32" };
    const wasm_types = [_][]const u8{ "f64", "f32" };
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start(): {s} {{
            \\  5.3
            \\}}
        , .{type_}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        try codegen(module);
        const wasm = try printWasm(module);
        try expectEqualStrings(wasm, try std.fmt.allocPrint(arena.allocator(),
            \\(module
            \\
            \\  (func $foo/start (result {s})
            \\    ({s}.const 5.3))
            \\
            \\  (export "_start" (func $foo/start)))
        , .{ wasm_types[i], wasm_types[i] }));
    }
}

test "print wasm call local function" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "f64", "f32" };
    const wasm_types = [_][]const u8{ "f64", "f32" };
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start(): {s} {{
            \\  baz()
            \\}}
            \\
            \\baz(): {s} {{
            \\  10
            \\}}
        , .{ type_, type_ }));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        try codegen(module);
        const wasm = try printWasm(module);
        try expectEqualStrings(wasm, try std.fmt.allocPrint(arena.allocator(),
            \\(module
            \\
            \\  (func $foo/start (result {s})
            \\    (call $foo/baz))
            \\
            \\  (func $foo/baz (result {s})
            \\    ({s}.const 10))
            \\
            \\  (export "_start" (func $foo/start)))
        , .{ wasm_types[i], wasm_types[i], wasm_types[i] }));
    }
}

test "print wasm call local function with argument" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "i64", "i32", "u64", "u32", "f64", "f32" };
    const wasm_types = [_][]const u8{ "i64", "i32", "i64", "i32", "f64", "f32" };
    const const_kinds = [_][]const u8{ "i64.const", "i32.const", "i64.const", "i32.const", "f64.const", "f32.const" };
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start(): {s} {{
            \\  id(5)
            \\}}
            \\
            \\id(x: {s}): {s} {{
            \\  x
            \\}}
        , .{ type_, type_, type_ }));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        try codegen(module);
        const wasm = try printWasm(module);
        try expectEqualStrings(wasm, try std.fmt.allocPrint(arena.allocator(),
            \\(module
            \\
            \\  (func $foo/start (result {s})
            \\    ({s} 5)
            \\    (call $foo/id.{s}))
            \\
            \\  (func $foo/id.{s} (param $x {s}) (result {s})
            \\    (local.get $x))
            \\
            \\  (export "_start" (func $foo/start)))
        , .{ wasm_types[i], const_kinds[i], type_, type_, wasm_types[i], wasm_types[i] }));
    }
}

test "print wasm define int literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "i64", "u64", "f64" };
    const wasm_types = [_][]const u8{ "i64", "i64", "f64" };
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start(): {s} {{
            \\  x = 10
            \\  x
            \\}}
        , .{type_}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        try codegen(module);
        const wasm = try printWasm(module);
        try expectEqualStrings(wasm, try std.fmt.allocPrint(arena.allocator(),
            \\(module
            \\
            \\  (func $foo/start (result {s})
            \\    ({s}.const 10))
            \\
            \\  (export "_start" (func $foo/start)))
        , .{ wasm_types[i], wasm_types[i] }));
    }
}
