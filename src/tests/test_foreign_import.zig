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
const literalOf = yeti.query.literalOf;
const typeOf = yeti.query.typeOf;
const MockFileSystem = yeti.FileSystem;

test "tokenize foreign import" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code = "@import";
    var tokens = try tokenize(module, code);
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .attribute_import);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 0, .row = 0 },
            .end = .{ .column = 7, .row = 0 },
        });
    }
    try expectEqual(tokens.next(), null);
}

test "parse foreign import" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\@import("console", "log")
        \\log(value: i64) void
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const log = top_level.findString("log");
    const overloads = log.get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const function = overloads[0];
    try expectEqual(function.get(components.AstKind), .function);
    try expectEqualStrings(literalOf(function.get(components.ForeignModule).entity), "console");
    try expectEqualStrings(literalOf(function.get(components.ForeignName).entity), "log");
    const parameters = function.get(components.Parameters).slice();
    try expectEqual(parameters.len, 1);
    const parameter = parameters[0];
    try expectEqualStrings(literalOf(parameter), "value");
    try expectEqualStrings(literalOf(parameter.get(components.TypeAst).entity), "i64");
    try expectEqualStrings(literalOf(function.get(components.ReturnTypeAst).entity), "void");
}

test "parse foreign import with module and name inferred" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\@import
        \\log(value: i64) void
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const log = top_level.findString("log");
    const overloads = log.get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const function = overloads[0];
    try expectEqual(function.get(components.AstKind), .function);
    try expectEqualStrings(literalOf(function.get(components.ForeignModule).entity), "host");
    try expectEqualStrings(literalOf(function.get(components.ForeignName).entity), "log");
    const parameters = function.get(components.Parameters).slice();
    try expectEqual(parameters.len, 1);
    const parameter = parameters[0];
    try expectEqualStrings(literalOf(parameter), "value");
    try expectEqualStrings(literalOf(parameter.get(components.TypeAst).entity), "i64");
    try expectEqualStrings(literalOf(function.get(components.ReturnTypeAst).entity), "void");
}

test "analyze semantics of foreign import" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\@import("console", "log")
        \\log(value: i64) void
        \\
        \\start() void {
        \\  log(10)
        \\}
    );
    _ = try analyzeSemantics(codebase, fs, "foo.yeti");
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.Void);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 1);
    const log = body[0];
    try expectEqual(log.get(components.AstKind), .call);
    const arguments = log.get(components.Arguments).slice();
    try expectEqual(arguments.len, 1);
    const callable = log.get(components.Callable).entity;
    try expectEqualStrings(literalOf(callable.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(callable.get(components.Name).entity), "log");
    const parameters = callable.get(components.Parameters).slice();
    try expectEqual(parameters.len, 1);
    try expectEqual(callable.get(components.ReturnType).entity, builtins.Void);
    const parameter = parameters[0];
    try expectEqual(typeOf(parameter), builtins.I64);
    try expectEqualStrings(literalOf(parameter.get(components.Name).entity), "value");
}

test "print wasm foreign import" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\@import("console", "log")
        \\log(value: i64) void
        \\
        \\start() void {
        \\  log(10)
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (import "console" "log" (func $foo/log..value.i64 (param $value i64)))
        \\
        \\  (func $foo/start
        \\    (i64.const 10)
        \\    (call $foo/log..value.i64))
        \\
        \\  (export "_start" (func $foo/start)))
    );
}
