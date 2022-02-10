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
            \\start = fn(): {s}
            \\  5
            \\end
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
            \\start = fn(): {s}
            \\  5.3
            \\end
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
            \\start = fn(): {s}
            \\  baz()
            \\end
            \\
            \\baz = fn(): {s}
            \\  10
            \\end
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
            \\start = fn(): {s}
            \\  id(5)
            \\end
            \\
            \\id = fn(x: {s}): {s}
            \\  x
            \\end
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
            \\start = fn(): {s}
            \\  x = 10
            \\  x
            \\end
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
                \\start = fn(): {s}
                \\  x: {s} = 8
                \\  y: {s} = 2
                \\  x {s} y
                \\end
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
                \\start = fn(): {s}
                \\  x: {s} = 8
                \\  y: {s} = 2
                \\  x {s} y
                \\end
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
                \\start = fn(): {s}
                \\  id(10) {s} id(25)
                \\end
                \\
                \\id = fn(x: {s}): {s}
                \\  x
                \\end
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
                \\start = fn(): {s}
                \\  id(10) {s} id(25)
                \\end
                \\
                \\id = fn(x: {s}): {s}
                \\  x
                \\end
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
                \\start = fn(): {s}
                \\  id(10) {s} id(25)
                \\end
                \\
                \\id = fn(x: {s}): {s}
                \\  x
                \\end
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
            \\start = fn(): {s}
            \\  if 1 then 20 else 30 end
            \\end
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
            \\start = fn(): {s}
            \\  if 0 then 20 else 30 end
            \\end
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
            \\start = fn(): {s}
            \\  if f() then 20 else 30 end
            \\end
            \\
            \\f = fn(): i32 1 end
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
            \\start = fn(): {s}
            \\  x: {s} = 10
            \\  x = 3
            \\  x
            \\end
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

test "print wasm while loop" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = fn(): i32
        \\  i = 0
        \\  while i < 10 do
        \\      i = i + 1
        \\  end
        \\  i
        \\end
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/start (result i32)
        \\    (local $i i32)
        \\    (i32.const 0)
        \\    (local.set $i)
        \\    block $.label.0
        \\    loop $.label.1
        \\    (local.get $i)
        \\    (i32.const 10)
        \\    i32.lt_s
        \\    i32.eqz
        \\    br_if $.label.0
        \\    (local.get $i)
        \\    (i32.const 1)
        \\    i32.add
        \\    (local.set $i)
        \\    br $.label.1
        \\    end $.label.1
        \\    end $.label.0
        \\    (local.get $i))
        \\
        \\  (export "_start" (func $foo/start)))
    );
}

test "print wasm for loop" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = fn(): i32
        \\  sum = 0
        \\  for i in 0:10 do
        \\      sum = sum + i
        \\  end
        \\  sum
        \\end
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/start (result i32)
        \\    (local $sum i32)
        \\    (local $i i32)
        \\    (i32.const 0)
        \\    (local.set $sum)
        \\    (i32.const 0)
        \\    (local.set $i)
        \\    block $.label.0
        \\    loop $.label.1
        \\    (local.get $i)
        \\    (i32.const 10)
        \\    i32.ge_s
        \\    br_if $.label.0
        \\    (local.get $sum)
        \\    (local.get $i)
        \\    i32.add
        \\    (local.set $sum)
        \\    (i32.const 1)
        \\    (local.get $i)
        \\    i32.add
        \\    (local.set $i)
        \\    br $.label.1
        \\    end $.label.1
        \\    end $.label.0
        \\    (local.get $sum))
        \\
        \\  (export "_start" (func $foo/start)))
    );
}

test "print wasm foreign export" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\square = fn(x: i64): i64
        \\  x * x
        \\end
        \\
        \\area = fn(width: f64, height: f64): f64
        \\  width * height
        \\end
        \\
        \\foreign_export(square)
        \\
        \\foreign_export(area)
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/square.i64 (param $x i64) (result i64)
        \\    (local.get $x)
        \\    (local.get $x)
        \\    i64.mul)
        \\
        \\  (func $foo/area.f64.f64 (param $width f64) (param $height f64) (result f64)
        \\    (local.get $width)
        \\    (local.get $height)
        \\    f64.mul)
        \\
        \\  (export "square" (func $foo/square.i64))
        \\
        \\  (export "area" (func $foo/area.f64.f64)))
    );
}

test "print wasm foreign import" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\log = foreign_import("console", "log", Fn(value: i64): void)
        \\
        \\start = fn(): void
        \\  log(10)
        \\end
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (import "console" "log" (func $foo/log.i64 (param $value i64)))
        \\
        \\  (func $foo/start
        \\    (i64.const 10)
        \\    (call $foo/log.i64))
        \\
        \\  (export "_start" (func $foo/start)))
    );
}

test "print wasm pointer" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = fn(): *i64
        \\  cast(*i64, 0)
        \\end
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/start (result i32)
        \\    (i32.const 0))
        \\
        \\  (export "_start" (func $foo/start)))
    );
}

test "print wasm pointer store" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = fn(): void
        \\  ptr = cast(*i64, 0)
        \\  *ptr = 10
        \\end
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/start
        \\    (local $ptr i32)
        \\    (i32.const 0)
        \\    (local.set $ptr)
        \\    (local.get $ptr)
        \\    (i64.const 10)
        \\    i64.store)
        \\
        \\  (export "_start" (func $foo/start))
        \\
        \\  (memory 1)
        \\  (export "memory" (memory 0)))
    );
}

test "print wasm pointer load" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = fn(): i64
        \\  ptr = cast(*i64, 0)
        \\  *ptr
        \\end
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/start (result i64)
        \\    (local $ptr i32)
        \\    (i32.const 0)
        \\    (local.set $ptr)
        \\    (local.get $ptr)
        \\    i64.load)
        \\
        \\  (export "_start" (func $foo/start))
        \\
        \\  (memory 1)
        \\  (export "memory" (memory 0)))
    );
}

test "print wasm pointer load u8" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = fn(): u8
        \\  ptr = cast(*u8, 0)
        \\  *ptr
        \\end
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/start (result i32)
        \\    (local $ptr i32)
        \\    (i32.const 0)
        \\    (local.set $ptr)
        \\    (local.get $ptr)
        \\    i32.load8_u)
        \\
        \\  (export "_start" (func $foo/start))
        \\
        \\  (memory 1)
        \\  (export "memory" (memory 0)))
    );
}

test "print wasm pointer as parameter" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\f = fn(ptr: *i32): i32
        \\  0
        \\end
        \\
        \\foreign_export(f)
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/f.ptr.i32 (param $ptr i32) (result i32)
        \\    (i32.const 0))
        \\
        \\  (export "f" (func $foo/f.ptr.i32)))
    );
}

test "print wasm adding pointer and int literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\f = fn(ptr: *i64): *i64
        \\  ptr + 1
        \\end
        \\
        \\foreign_export(f)
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/f.ptr.i64 (param $ptr i32) (result i32)
        \\    (local.get $ptr)
        \\    (i32.const 8)
        \\    i32.add)
        \\
        \\  (export "f" (func $foo/f.ptr.i64)))
    );
}

test "print wasm subtracting pointer and int literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\f = fn(ptr: *i64): *i64
        \\  ptr - 1
        \\end
        \\
        \\foreign_export(f)
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/f.ptr.i64 (param $ptr i32) (result i32)
        \\    (local.get $ptr)
        \\    (i32.const 8)
        \\    i32.sub)
        \\
        \\  (export "f" (func $foo/f.ptr.i64)))
    );
}

test "print wasm adding pointer and i32" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\f = fn(ptr: *i64, len: i32): *i64
        \\  ptr + len
        \\end
        \\
        \\foreign_export(f)
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/f.ptr.i64.i32 (param $ptr i32) (param $len i32) (result i32)
        \\    (local.get $ptr)
        \\    (local.get $len)
        \\    (i32.const 8)
        \\    i32.mul
        \\    i32.add)
        \\
        \\  (export "f" (func $foo/f.ptr.i64.i32)))
    );
}

test "print wasm pointer v128 load" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = fn(): i64x2
        \\  ptr = cast(*i64x2, 0)
        \\  *ptr
        \\end
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/start (result v128)
        \\    (local $ptr i32)
        \\    (i32.const 0)
        \\    (local.set $ptr)
        \\    (local.get $ptr)
        \\    v128.load)
        \\
        \\  (export "_start" (func $foo/start))
        \\
        \\  (memory 1)
        \\  (export "memory" (memory 0)))
    );
}

test "print wasm pointer v128 store" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = fn(): void
        \\  ptr = cast(*i64x2, 0)
        \\  *ptr = *ptr
        \\end
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/start
        \\    (local $ptr i32)
        \\    (i32.const 0)
        \\    (local.set $ptr)
        \\    (local.get $ptr)
        \\    (local.get $ptr)
        \\    v128.load
        \\    v128.store)
        \\
        \\  (export "_start" (func $foo/start))
        \\
        \\  (memory 1)
        \\  (export "memory" (memory 0)))
    );
}

test "print wasm binary op on two int vectors" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const type_strings = [_][]const u8{ "i64x2", "i32x4", "i16x8", "i8x16", "u64x2", "u32x4", "u16x8", "u8x16" };
    const op_strings = [_][]const u8{ "+", "-", "*" };
    const instructions = [_][3][]const u8{
        .{ "i64x2.add", "i64x2.sub", "i64x2.mul" },
        .{ "i32x4.add", "i32x4.sub", "i32x4.mul" },
        .{ "i16x8.add", "i16x8.sub", "i16x8.mul" },
        .{ "i8x16.add", "i8x16.sub", "i8x16.mul" },
        .{ "i64x2.add", "i64x2.sub", "i64x2.mul" },
        .{ "i32x4.add", "i32x4.sub", "i32x4.mul" },
        .{ "i16x8.add", "i16x8.sub", "i16x8.mul" },
        .{ "i8x16.add", "i8x16.sub", "i8x16.mul" },
    };
    for (type_strings) |type_string, type_index| {
        for (op_strings) |op_string, i| {
            var fs = try MockFileSystem.init(&arena);
            _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
                \\start = fn(): {s}
                \\  v = *cast(*{s}, 0)
                \\  v {s} v
                \\end
            , .{ type_string, type_string, op_string }));
            const module = try analyzeSemantics(codebase, fs, "foo.yeti");
            try codegen(module);
            const wasm = try printWasm(module);
            try expectEqualStrings(wasm, try std.fmt.allocPrint(arena.allocator(),
                \\(module
                \\
                \\  (func $foo/start (result v128)
                \\    (local $v v128)
                \\    (i32.const 0)
                \\    v128.load
                \\    (local.set $v)
                \\    (local.get $v)
                \\    (local.get $v)
                \\    {s})
                \\
                \\  (export "_start" (func $foo/start))
                \\
                \\  (memory 1)
                \\  (export "memory" (memory 0)))
            , .{instructions[type_index][i]}));
        }
    }
}

test "print wasm binary op on two float vectors" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const type_strings = [_][]const u8{ "f64x2", "f32x4" };
    const op_strings = [_][]const u8{ "+", "-", "*", "/" };
    const instructions = [_][4][]const u8{
        .{ "f64x2.add", "f64x2.sub", "f64x2.mul", "f64x2.div" },
        .{ "f32x4.add", "f32x4.sub", "f32x4.mul", "f32x4.div" },
    };
    for (type_strings) |type_string, type_index| {
        for (op_strings) |op_string, i| {
            var fs = try MockFileSystem.init(&arena);
            _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
                \\start = fn(): {s}
                \\  v = *cast(*{s}, 0)
                \\  v {s} v
                \\end
            , .{ type_string, type_string, op_string }));
            const module = try analyzeSemantics(codebase, fs, "foo.yeti");
            try codegen(module);
            const wasm = try printWasm(module);
            try expectEqualStrings(wasm, try std.fmt.allocPrint(arena.allocator(),
                \\(module
                \\
                \\  (func $foo/start (result v128)
                \\    (local $v v128)
                \\    (i32.const 0)
                \\    v128.load
                \\    (local.set $v)
                \\    (local.get $v)
                \\    (local.get $v)
                \\    {s})
                \\
                \\  (export "_start" (func $foo/start))
                \\
                \\  (memory 1)
                \\  (export "memory" (memory 0)))
            , .{instructions[type_index][i]}));
        }
    }
}

test "print wasm struct" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\Rectangle = struct
        \\  width: f64
        \\  height: f64
        \\end
        \\
        \\start = fn(): Rectangle
        \\  Rectangle(10, 30)
        \\end
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/start (result f64 f64)
        \\    (f64.const 10)
        \\    (f64.const 30))
        \\
        \\  (export "_start" (func $foo/start)))
    );
}

test "print wasm assign struct to variable" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\Rectangle = struct
        \\  width: f64
        \\  height: f64
        \\end
        \\
        \\start = fn(): Rectangle
        \\  r = Rectangle(10, 30)
        \\  r
        \\end
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/start (result f64 f64)
        \\    (local $r.width f64)
        \\    (local $r.height f64)
        \\    (f64.const 10)
        \\    (f64.const 30)
        \\    (local.set $r.height)
        \\    (local.set $r.width)
        \\    (local.get $r.width)
        \\    (local.get $r.height))
        \\
        \\  (export "_start" (func $foo/start)))
    );
}

test "print wasm pass struct to function" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\Rectangle = struct
        \\  width: f64
        \\  height: f64
        \\end
        \\
        \\id = fn(r: Rectangle): Rectangle
        \\  r
        \\end
        \\
        \\start = fn(): Rectangle
        \\  id(Rectangle(10, 30))
        \\end
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/start (result f64 f64)
        \\    (f64.const 10)
        \\    (f64.const 30)
        \\    (call $foo/id.Rectangle))
        \\
        \\  (func $foo/id.Rectangle (param $r.width f64) (param $r.height f64) (result f64 f64)
        \\    (local.get $r.width)
        \\    (local.get $r.height))
        \\
        \\  (export "_start" (func $foo/start)))
    );
}

test "print wasm struct field access" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\Rectangle = struct
        \\  width: f64
        \\  height: f64
        \\end
        \\
        \\start = fn(): f64
        \\  r = Rectangle(10, 30)
        \\  r.width
        \\end
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/start (result f64)
        \\    (local $r.width f64)
        \\    (local $r.height f64)
        \\    (f64.const 10)
        \\    (f64.const 30)
        \\    (local.set $r.height)
        \\    (local.set $r.width)
        \\    (local.get $r.width))
        \\
        \\  (export "_start" (func $foo/start)))
    );
}

test "print wasm struct field write" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\Rectangle = struct
        \\  width: f64
        \\  height: f64
        \\end
        \\
        \\start = fn(): Rectangle
        \\  r = Rectangle(10, 30)
        \\  r.width = 45
        \\  r
        \\end
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/start (result f64 f64)
        \\    (local $r.width f64)
        \\    (local $r.height f64)
        \\    (f64.const 10)
        \\    (f64.const 30)
        \\    (local.set $r.height)
        \\    (local.set $r.width)
        \\    (f64.const 45)
        \\    (local.set $r.width)
        \\    (local.get $r.width)
        \\    (local.get $r.height))
        \\
        \\  (export "_start" (func $foo/start)))
    );
}

test "print wasm string literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = fn(): []u8
        \\  "hello world"
        \\end
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/start (result i32 i32)
        \\    (i32.const 0)
        \\    (i32.const 11))
        \\
        \\  (export "_start" (func $foo/start))
        \\
        \\  (data (i32.const 0) "hello world")
        \\
        \\  (memory 1)
        \\  (export "memory" (memory 0)))
    );
}

test "print wasm assign string literal to variable" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = fn(): []u8
        \\  text = "hello world"
        \\  text
        \\end
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/start (result i32 i32)
        \\    (local $text.ptr i32)
        \\    (local $text.len i32)
        \\    (i32.const 0)
        \\    (i32.const 11)
        \\    (local.set $text.len)
        \\    (local.set $text.ptr)
        \\    (local.get $text.ptr)
        \\    (local.get $text.len))
        \\
        \\  (export "_start" (func $foo/start))
        \\
        \\  (data (i32.const 0) "hello world")
        \\
        \\  (memory 1)
        \\  (export "memory" (memory 0)))
    );
}

test "print wasm pass string literal as argument" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\first = fn(text: []u8): u8
        \\  *(text.ptr)
        \\end
        \\
        \\start = fn(): u8
        \\  first("hello world")
        \\end
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/start (result i32)
        \\    (i32.const 0)
        \\    (i32.const 11)
        \\    (call $foo/first.array.u8))
        \\
        \\  (func $foo/first.array.u8 (param $text.ptr i32) (param $text.len i32) (result i32)
        \\    (local.get $text.ptr)
        \\    i32.load8_u)
        \\
        \\  (export "_start" (func $foo/start))
        \\
        \\  (data (i32.const 0) "hello world")
        \\
        \\  (memory 1)
        \\  (export "memory" (memory 0)))
    );
}

test "print wasm dereference string literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = fn(): u8
        \\  text = "hello world"
        \\  *text.ptr
        \\end
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/start (result i32)
        \\    (local $text.ptr i32)
        \\    (local $text.len i32)
        \\    (i32.const 0)
        \\    (i32.const 11)
        \\    (local.set $text.len)
        \\    (local.set $text.ptr)
        \\    (local.get $text.ptr)
        \\    i32.load8_u)
        \\
        \\  (export "_start" (func $foo/start))
        \\
        \\  (data (i32.const 0) "hello world")
        \\
        \\  (memory 1)
        \\  (export "memory" (memory 0)))
    );
}

test "print wasm write through **u8" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = fn(): void
        \\  text = "hello world"
        \\  ptr = cast(**u8, 100)
        \\  *ptr = text.ptr
        \\end
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/start
        \\    (local $text.ptr i32)
        \\    (local $text.len i32)
        \\    (local $ptr i32)
        \\    (i32.const 0)
        \\    (i32.const 11)
        \\    (local.set $text.len)
        \\    (local.set $text.ptr)
        \\    (i32.const 100)
        \\    (local.set $ptr)
        \\    (local.get $ptr)
        \\    (local.get $text.ptr)
        \\    i32.store)
        \\
        \\  (export "_start" (func $foo/start))
        \\
        \\  (data (i32.const 0) "hello world")
        \\
        \\  (memory 1)
        \\  (export "memory" (memory 0)))
    );
}

test "print wasm properly infer type for for loop" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = fn(): i64
        \\  sum = 0
        \\  for i in 0:10 do
        \\    sum += 1
        \\  end
        \\  sum
        \\end
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/start (result i64)
        \\    (local $sum i64)
        \\    (local $i i32)
        \\    (i64.const 0)
        \\    (local.set $sum)
        \\    (i32.const 0)
        \\    (local.set $i)
        \\    block $.label.0
        \\    loop $.label.1
        \\    (local.get $i)
        \\    (i32.const 10)
        \\    i32.ge_s
        \\    br_if $.label.0
        \\    (local.get $sum)
        \\    (i64.const 1)
        \\    i64.add
        \\    (local.set $sum)
        \\    (i32.const 1)
        \\    (local.get $i)
        \\    i32.add
        \\    (local.set $i)
        \\    br $.label.1
        \\    end $.label.1
        \\    end $.label.0
        \\    (local.get $sum))
        \\
        \\  (export "_start" (func $foo/start)))
    );
}
