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
const parentType = yeti.query.parentType;
const valueType = yeti.query.valueType;
const Entity = yeti.ecs.Entity;
const MockFileSystem = yeti.FileSystem;

test "analyze semantics call local function" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start(): i64 {
        \\  id(x=5)
        \\}
        \\
        \\id(x: i64): i64 {
        \\  x
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.I64);
    const baz = blk: {
        const body = start.get(components.Body).slice();
        try expectEqual(body.len, 1);
        const call = body[0];
        try expectEqual(call.get(components.AstKind), .call);
        try expectEqual(call.get(components.Arguments).len(), 0);
        try expectEqual(typeOf(call), builtins.I64);
        break :blk call.get(components.Callable).entity;
    };
    try expectEqualStrings(literalOf(baz.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(baz.get(components.Name).entity), "baz");
    try expectEqual(baz.get(components.Parameters).len(), 0);
    try expectEqual(baz.get(components.ReturnType).entity, builtins.I64);
    const body = baz.get(components.Body).slice();
    try expectEqual(body.len, 1);
    const int_literal = body[0];
    try expectEqual(int_literal.get(components.AstKind), .int);
    try expectEqual(typeOf(int_literal), builtins.I64);
    try expectEqualStrings(literalOf(int_literal), "10");
}
