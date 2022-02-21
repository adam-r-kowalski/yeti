const std = @import("std");
const Arena = std.heap.ArenaAllocator;
const expect = std.testing.expect;
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

test "parse function with return type inference" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\start() {
        \\  0
        \\}
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const overloads = top_level.findString("start").get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const start = overloads[0];
    try expect(!start.contains(components.ReturnTypeAst));
    const body = overloads[0].get(components.Body).slice();
    try expectEqual(body.len, 1);
    const zero = body[0];
    try expectEqual(zero.get(components.AstKind), .int);
    try expectEqualStrings(literalOf(zero), "0");
}
