const std = @import("std");
const Arena = std.heap.ArenaAllocator;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const yeti = @import("yeti");
const initCodebase = yeti.initCodebase;
const tokenize = yeti.tokenize;
const parse = yeti.parse;
const analyzeSemantics = yeti.analyzeSemantics;
const codegen = yeti.codegen;
const printWasm = yeti.printWasm;
const components = yeti.components;
const literalOf = yeti.test_utils.literalOf;
const MockFileSystem = yeti.FileSystem;

test "tokenize foreign export" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code = "@export";
    var tokens = try tokenize(module, code);
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .attribute_export);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 0, .row = 0 },
            .end = .{ .column = 7, .row = 0 },
        });
    }
    try expectEqual(tokens.next(), null);
}

test "parse function with int literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\@export
        \\start(): u64 {
        \\  0
        \\}
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start");
    const overloads = start.get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const body = overloads[0].get(components.Body).slice();
    try expectEqual(body.len, 1);
    const zero = body[0];
    try expectEqual(zero.get(components.AstKind), .int);
    try expectEqualStrings(literalOf(zero), "0");
    const foreign_exports = module.get(components.ForeignExports).slice();
    try expectEqual(foreign_exports.len, 1);
    try expectEqualStrings(literalOf(foreign_exports[0]), "start");
}

test "analyze semantics of foreign export" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\@export
        \\square(x: i64): i64 {
        \\  x * x
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const square = top_level.findString("square").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(square.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(square.get(components.Name).entity), "square");
    try expectEqual(square.get(components.Parameters).len(), 1);
    try expectEqual(square.get(components.ReturnType).entity, builtins.I64);
    const body = square.get(components.Body).slice();
    try expectEqual(body.len, 1);
}

test "print wasm foreign export" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\@export
        \\square(x: i64): i64 {
        \\  x * x
        \\}
        \\
        \\@export
        \\area(width: f64, height: f64): f64 {
        \\  width * height
        \\}
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
