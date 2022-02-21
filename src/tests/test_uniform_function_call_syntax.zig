const std = @import("std");
const Arena = std.heap.ArenaAllocator;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const yeti = @import("yeti");
const initCodebase = yeti.initCodebase;
const MockFileSystem = yeti.FileSystem;
const components = yeti.components;
const tokenize = yeti.tokenize;
const analyzeSemantics = yeti.analyzeSemantics;
const literalOf = yeti.query.literalOf;
const typeOf = yeti.query.typeOf;
const parentType = yeti.query.parentType;
const valueType = yeti.query.valueType;
const Entity = yeti.ecs.Entity;

test "tokenize uniform function call syntax" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code = "10.min(20)";
    var tokens = try tokenize(module, code);
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .int);
        try expectEqualStrings(literalOf(token), "10");
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 0, .row = 0 },
            .end = .{ .column = 2, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .dot);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 2, .row = 0 },
            .end = .{ .column = 3, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .symbol);
        try expectEqualStrings(literalOf(token), "min");
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 3, .row = 0 },
            .end = .{ .column = 6, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .left_paren);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 6, .row = 0 },
            .end = .{ .column = 7, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .int);
        try expectEqualStrings(literalOf(token), "20");
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 7, .row = 0 },
            .end = .{ .column = 9, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .right_paren);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 9, .row = 0 },
            .end = .{ .column = 10, .row = 0 },
        });
    }
    try expectEqual(tokens.next(), null);
}
test "analyze semantics of uniform function call syntax" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\min(x: i64, y: i64): i64 {
        \\  if x < y { x } else { y }
        \\}
        \\
        \\start(): i64 {
        \\  10.min(20)
        \\}
    );
    _ = try analyzeSemantics(codebase, fs, "foo.yeti");
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.I64);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 1);
    const call = body[0];
    try expectEqual(call.get(components.AstKind), .call);
    const arguments = call.get(components.Arguments).slice();
    try expectEqual(arguments.len, 2);
    try expectEqualStrings(literalOf(arguments[0]), "10");
    try expectEqualStrings(literalOf(arguments[1]), "20");
    try expectEqual(typeOf(call), builtins.I64);
    const min = call.get(components.Callable).entity;
    try expectEqualStrings(literalOf(min.get(components.Name).entity), "min");
}

test "analyze semantics of uniform function call syntax omit parenthesis" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\square(x: i64): i64 {
        \\  x * x
        \\}
        \\
        \\start(): i64 {
        \\  10.square
        \\}
    );
    _ = try analyzeSemantics(codebase, fs, "foo.yeti");
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.I64);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 1);
    const call = body[0];
    try expectEqual(call.get(components.AstKind), .call);
    const arguments = call.get(components.Arguments).slice();
    try expectEqual(arguments.len, 1);
    try expectEqualStrings(literalOf(arguments[0]), "10");
    try expectEqual(typeOf(call), builtins.I64);
    const square = call.get(components.Callable).entity;
    try expectEqualStrings(literalOf(square.get(components.Name).entity), "square");
}

test "analyze semantics of uniform function call syntax on locals" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\square(x: i64): i64 {
        \\  x * x
        \\}
        \\
        \\start(): i64 {
        \\  x = 10
        \\  x.square()
        \\}
    );
    _ = try analyzeSemantics(codebase, fs, "foo.yeti");
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.I64);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 2);
    const define = body[0];
    try expectEqual(define.get(components.AstKind), .define);
    try expectEqual(typeOf(define), builtins.Void);
    try expectEqualStrings(literalOf(define.get(components.Value).entity), "10");
    const x = define.get(components.Local).entity;
    try expectEqualStrings(literalOf(x.get(components.Name).entity), "x");
    try expectEqual(typeOf(x), builtins.I64);
    const call = body[1];
    try expectEqual(call.get(components.AstKind), .call);
    const arguments = call.get(components.Arguments).slice();
    try expectEqual(arguments.len, 1);
    try expectEqual(arguments[0], x);
    try expectEqual(typeOf(call), builtins.I64);
    const square = call.get(components.Callable).entity;
    try expectEqualStrings(literalOf(square.get(components.Name).entity), "square");
}

test "analyze semantics of uniform function call syntax on structs" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\struct Square {
        \\  length: f64
        \\}
        \\
        \\area(s: Square): f64 {
        \\  s.length * s.length
        \\}
        \\
        \\start(): f64 {
        \\  s = Square(10)
        \\  s.area()
        \\}
    );
    _ = try analyzeSemantics(codebase, fs, "foo.yeti");
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.F64);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 2);
    const define = body[0];
    try expectEqual(define.get(components.AstKind), .define);
    try expectEqual(typeOf(define), builtins.Void);
    const Square = typeOf(define.get(components.Value).entity);
    try expectEqualStrings(literalOf(Square), "Square");
    const s = define.get(components.Local).entity;
    try expectEqualStrings(literalOf(s.get(components.Name).entity), "s");
    try expectEqual(typeOf(s), Square);
    const call = body[1];
    try expectEqual(call.get(components.AstKind), .call);
    const arguments = call.get(components.Arguments).slice();
    try expectEqual(arguments.len, 1);
    try expectEqual(arguments[0], s);
    try expectEqual(typeOf(call), builtins.F64);
    const area = call.get(components.Callable).entity;
    try expectEqualStrings(literalOf(area.get(components.Name).entity), "area");
}

test "analyze semantics of uniform function call syntax on structs omit parenthesis" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\struct Square {
        \\  length: f64
        \\}
        \\
        \\area(s: Square): f64 {
        \\  s.length * s.length
        \\}
        \\
        \\start(): f64 {
        \\  s = Square(10)
        \\  s.area
        \\}
    );
    _ = try analyzeSemantics(codebase, fs, "foo.yeti");
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.F64);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 2);
    const define = body[0];
    try expectEqual(define.get(components.AstKind), .define);
    try expectEqual(typeOf(define), builtins.Void);
    const Square = typeOf(define.get(components.Value).entity);
    try expectEqualStrings(literalOf(Square), "Square");
    const s = define.get(components.Local).entity;
    try expectEqualStrings(literalOf(s.get(components.Name).entity), "s");
    try expectEqual(typeOf(s), Square);
    const call = body[1];
    try expectEqual(call.get(components.AstKind), .call);
    const arguments = call.get(components.Arguments).slice();
    try expectEqual(arguments.len, 1);
    try expectEqual(arguments[0], s);
    try expectEqual(typeOf(call), builtins.F64);
    const area = call.get(components.Callable).entity;
    try expectEqualStrings(literalOf(area.get(components.Name).entity), "area");
}
