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

test "print wasm arithmetic binary op" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const op_strings = [_][]const u8{ "+", "-", "*", "/" };
    const results = [_][6][]const u8{
        [_][]const u8{ "10", "10", "10", "10", "1.0e+01", "1.0e+01" },
        [_][]const u8{ "6", "6", "6", "6", "6.0e+00", "6.0e+00" },
        [_][]const u8{ "16", "16", "16", "16", "1.6e+01", "1.6e+01" },
        [_][]const u8{ "4", "4", "4", "4", "4.0e+00", "4.0e+00" },
    };
    const types = [_][]const u8{ "i64", "i32", "u64", "u32", "f64", "f32" };
    const wasm_types = [_][]const u8{ "i64", "i32", "i64", "i32", "f64", "f32" };
    for (op_strings) |op_string, op_index| {
        for (types) |type_, i| {
            var fs = try MockFileSystem.init(&arena);
            _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
                \\start(): {s} {{
                \\  x: {s} = 8
                \\  y: {s} = 2
                \\  x {s} y
                \\}}
            , .{ type_, type_, type_, op_string }));
            const module = try analyzeSemantics(codebase, fs, "foo.yeti");
            try codegen(module);
            const wasm = try printWasm(module);
            try expectEqualStrings(wasm, try std.fmt.allocPrint(arena.allocator(),
                \\(module
                \\
                \\  (func $foo/start (result {s})
                \\    ({s}.const {s}))
                \\
                \\  (export "_start" (func $foo/start)))
            , .{ wasm_types[i], wasm_types[i], results[op_index][i] }));
        }
    }
}

test "print wasm int binary op" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const op_strings = [_][]const u8{ "%", "&", "|", "^", "<<", ">>" };
    const results = [_][4][]const u8{
        [_][]const u8{ "0", "0", "0", "0" },
        [_][]const u8{ "0", "0", "0", "0" },
        [_][]const u8{ "10", "10", "10", "10" },
        [_][]const u8{ "10", "10", "10", "10" },
        [_][]const u8{ "32", "32", "32", "32" },
        [_][]const u8{ "2", "2", "2", "2" },
    };
    const types = [_][]const u8{ "i64", "i32", "u64", "u32" };
    const wasm_types = [_][]const u8{ "i64", "i32", "i64", "i32" };
    for (op_strings) |op_string, op_index| {
        for (types) |type_, i| {
            var fs = try MockFileSystem.init(&arena);
            _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
                \\start(): {s} {{
                \\  x: {s} = 8
                \\  y: {s} = 2
                \\  x {s} y
                \\}}
            , .{ type_, type_, type_, op_string }));
            const module = try analyzeSemantics(codebase, fs, "foo.yeti");
            try codegen(module);
            const wasm = try printWasm(module);
            try expectEqualStrings(wasm, try std.fmt.allocPrint(arena.allocator(),
                \\(module
                \\
                \\  (func $foo/start (result {s})
                \\    ({s}.const {s}))
                \\
                \\  (export "_start" (func $foo/start)))
            , .{ wasm_types[i], wasm_types[i], results[op_index][i] }));
        }
    }
}

test "print wasm arithmetic binary op non constant" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const op_strings = [_][]const u8{ "+", "-", "*", "/" };
    const instructions = [_][6][]const u8{
        [_][]const u8{ "i64.add", "i32.add", "i64.add", "i32.add", "f64.add", "f32.add" },
        [_][]const u8{ "i64.sub", "i32.sub", "i64.sub", "i32.sub", "f64.sub", "f32.sub" },
        [_][]const u8{ "i64.mul", "i32.mul", "i64.mul", "i32.mul", "f64.mul", "f32.mul" },
        [_][]const u8{ "i64.div_s", "i32.div_s", "i64.div_u", "i32.div_u", "f64.div", "f32.div" },
    };
    const types = [_][]const u8{ "i64", "i32", "u64", "u32", "f64", "f32" };
    const wasm_types = [_][]const u8{ "i64", "i32", "i64", "i32", "f64", "f32" };
    for (op_strings) |op_string, op_index| {
        for (types) |type_, i| {
            var fs = try MockFileSystem.init(&arena);
            _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
                \\start(): {s} {{
                \\  id(10) {s} id(25)
                \\}}
                \\
                \\id(x: {s}): {s} {{
                \\  x
                \\}}
            , .{ type_, op_string, type_, type_ }));
            const module = try analyzeSemantics(codebase, fs, "foo.yeti");
            try codegen(module);
            const wasm = try printWasm(module);
            try expectEqualStrings(wasm, try std.fmt.allocPrint(arena.allocator(),
                \\(module
                \\
                \\  (func $foo/start (result {s})
                \\    ({s}.const 10)
                \\    (call $foo/id.{s})
                \\    ({s}.const 25)
                \\    (call $foo/id.{s})
                \\    {s})
                \\
                \\  (func $foo/id.{s} (param $x {s}) (result {s})
                \\    (local.get $x))
                \\
                \\  (export "_start" (func $foo/start)))
            , .{
                wasm_types[i],
                wasm_types[i],
                type_,
                wasm_types[i],
                type_,
                instructions[op_index][i],
                type_,
                wasm_types[i],
                wasm_types[i],
            }));
        }
    }
}

test "print wasm arithmetic binary op non constant modulo" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const op_strings = [_][]const u8{ "+", "-", "*" };
    const instructions = [_][4][]const u8{
        [_][]const u8{ "i32.add", "i32.add", "i32.add", "i32.add" },
        [_][]const u8{ "i32.sub", "i32.sub", "i32.sub", "i32.sub" },
        [_][]const u8{ "i32.mul", "i32.mul", "i32.mul", "i32.mul" },
    };
    const types = [_][]const u8{ "i16", "i8", "u16", "u8" };
    const wasm_types = [_][]const u8{ "i32", "i32", "i32", "i32" };
    const constants = [_][]const u8{ "65535", "255", "65535", "255" };
    for (op_strings) |op_string, op_index| {
        for (types) |type_, i| {
            var fs = try MockFileSystem.init(&arena);
            _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
                \\start(): {s} {{
                \\  id(10) {s} id(25)
                \\}}
                \\
                \\id(x: {s}): {s} {{
                \\  x
                \\}}
            , .{ type_, op_string, type_, type_ }));
            const module = try analyzeSemantics(codebase, fs, "foo.yeti");
            try codegen(module);
            const wasm = try printWasm(module);
            try expectEqualStrings(wasm, try std.fmt.allocPrint(arena.allocator(),
                \\(module
                \\
                \\  (func $foo/start (result {s})
                \\    ({s}.const 10)
                \\    (call $foo/id.{s})
                \\    ({s}.const 25)
                \\    (call $foo/id.{s})
                \\    {s}
                \\    (i32.const {s})
                \\    i32.and)
                \\
                \\  (func $foo/id.{s} (param $x {s}) (result {s})
                \\    (local.get $x))
                \\
                \\  (export "_start" (func $foo/start)))
            , .{
                wasm_types[i],
                wasm_types[i],
                type_,
                wasm_types[i],
                type_,
                instructions[op_index][i],
                constants[i],
                type_,
                wasm_types[i],
                wasm_types[i],
            }));
        }
    }
}

test "print wasm int binary op non constant" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const op_strings = [_][]const u8{ "%", "&", "|", "^", "<<", ">>" };
    const instructions = [_][8][]const u8{
        [_][]const u8{ "i64.rem_s", "i32.rem_s", "i32.rem_s", "i32.rem_s", "i64.rem_u", "i32.rem_u", "i32.rem_u", "i32.rem_u" },
        [_][]const u8{ "i64.and", "i32.and", "i32.and", "i32.and", "i64.and", "i32.and", "i32.and", "i32.and" },
        [_][]const u8{ "i64.or", "i32.or", "i32.or", "i32.or", "i64.or", "i32.or", "i32.or", "i32.or" },
        [_][]const u8{ "i64.xor", "i32.xor", "i32.xor", "i32.xor", "i64.xor", "i32.xor", "i32.xor", "i32.xor" },
        [_][]const u8{ "i64.shl", "i32.shl", "i32.shl", "i32.shl", "i64.shl", "i32.shl", "i32.shl", "i32.shl" },
        [_][]const u8{ "i64.shr_s", "i32.shr_s", "i32.shr_s", "i32.shr_s", "i64.shr_u", "i32.shr_u", "i32.shr_u", "i32.shr_u" },
    };
    const types = [_][]const u8{ "i64", "i32", "i16", "i8", "u64", "u32", "u16", "u8" };
    const wasm_types = [_][]const u8{ "i64", "i32", "i32", "i32", "i64", "i32", "i32", "i32" };
    for (op_strings) |op_string, op_index| {
        for (types) |type_, i| {
            var fs = try MockFileSystem.init(&arena);
            _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
                \\start(): {s} {{
                \\  id(10) {s} id(25)
                \\}}
                \\
                \\id(x: {s}): {s} {{
                \\  x
                \\}}
            , .{ type_, op_string, type_, type_ }));
            const module = try analyzeSemantics(codebase, fs, "foo.yeti");
            try codegen(module);
            const wasm = try printWasm(module);
            try expectEqualStrings(wasm, try std.fmt.allocPrint(arena.allocator(),
                \\(module
                \\
                \\  (func $foo/start (result {s})
                \\    ({s}.const 10)
                \\    (call $foo/id.{s})
                \\    ({s}.const 25)
                \\    (call $foo/id.{s})
                \\    {s})
                \\
                \\  (func $foo/id.{s} (param $x {s}) (result {s})
                \\    (local.get $x))
                \\
                \\  (export "_start" (func $foo/start)))
            , .{
                wasm_types[i],
                wasm_types[i],
                type_,
                wasm_types[i],
                type_,
                instructions[op_index][i],
                type_,
                wasm_types[i],
                wasm_types[i],
            }));
        }
    }
}

test "print wasm if then else where then branch taken statically" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "i64", "i32", "u64", "u32", "f64", "f32" };
    const wasm_types = [_][]const u8{ "i64", "i32", "i64", "i32", "f64", "f32" };
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start(): {s} {{
            \\  if 1 {{ 20 }} else {{ 30 }}
            \\}}
        , .{type_of}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        try codegen(module);
        const wasm = try printWasm(module);
        try expectEqualStrings(wasm, try std.fmt.allocPrint(arena.allocator(),
            \\(module
            \\
            \\  (func $foo/start (result {s})
            \\    ({s}.const 20))
            \\
            \\  (export "_start" (func $foo/start)))
        , .{ wasm_types[i], wasm_types[i] }));
    }
}

test "print wasm if then else where else branch taken statically" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "i64", "i32", "u64", "u32", "f64", "f32" };
    const wasm_types = [_][]const u8{ "i64", "i32", "i64", "i32", "f64", "f32" };
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start(): {s} {{
            \\  if 0 {{ 20 }} else {{ 30 }}
            \\}}
        , .{type_of}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        try codegen(module);
        const wasm = try printWasm(module);
        try expectEqualStrings(wasm, try std.fmt.allocPrint(arena.allocator(),
            \\(module
            \\
            \\  (func $foo/start (result {s})
            \\    ({s}.const 30))
            \\
            \\  (export "_start" (func $foo/start)))
        , .{ wasm_types[i], wasm_types[i] }));
    }
}

test "print wasm if then else non const conditional" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "i64", "i32", "u64", "u32", "f64", "f32" };
    const wasm_types = [_][]const u8{ "i64", "i32", "i64", "i32", "f64", "f32" };
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start(): {s} {{
            \\  if f() {{ 20 }} else {{ 30 }}
            \\}}
            \\
            \\f(): i32 {{ 1 }}
        , .{type_of}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        try codegen(module);
        const wasm = try printWasm(module);
        try expectEqualStrings(wasm, try std.fmt.allocPrint(arena.allocator(),
            \\(module
            \\
            \\  (func $foo/start (result {s})
            \\    (call $foo/f)
            \\    if (result {s})
            \\    ({s}.const 20)
            \\    else
            \\    ({s}.const 30)
            \\    end)
            \\
            \\  (func $foo/f (result i32)
            \\    (i32.const 1))
            \\
            \\  (export "_start" (func $foo/start)))
        , .{ wasm_types[i], wasm_types[i], wasm_types[i], wasm_types[i] }));
    }
}

test "print wasm assignment" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "i64", "i32", "u64", "u32", "f64", "f32" };
    const wasm_types = [_][]const u8{ "i64", "i32", "i64", "i32", "f64", "f32" };
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start(): {s} {{
            \\  x: {s} = 10
            \\  x = 3
            \\  x
            \\}}
        , .{ type_of, type_of }));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        try codegen(module);
        const wasm = try printWasm(module);
        try expectEqualStrings(wasm, try std.fmt.allocPrint(arena.allocator(),
            \\(module
            \\
            \\  (func $foo/start (result {s})
            \\    (local $x {s})
            \\    ({s}.const 10)
            \\    (local.set $x)
            \\    ({s}.const 3)
            \\    (local.set $x)
            \\    (local.get $x))
            \\
            \\  (export "_start" (func $foo/start)))
        , .{ wasm_types[i], wasm_types[i], wasm_types[i], wasm_types[i] }));
    }
}
