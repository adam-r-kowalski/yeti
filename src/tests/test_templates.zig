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

test "parse explicit type variables" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\min[T](x: T, y: T) T {
        \\  if x < y { x } else { y }
        \\}
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const overloads = top_level.findString("min").get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const start = overloads[0];
    const type_variables = start.get(components.TypeVariables).slice();
    try expectEqualStrings(literalOf(type_variables[0]), "T");
    const parameters = start.get(components.Parameters).slice();
    try expectEqual(parameters.len, 2);
    try expectEqualStrings(literalOf(parameters[0]), "x");
    try expectEqualStrings(literalOf(parameters[0].get(components.TypeAst).entity), "T");
    try expectEqualStrings(literalOf(parameters[1]), "y");
    try expectEqualStrings(literalOf(parameters[1].get(components.TypeAst).entity), "T");
    const return_type = start.get(components.ReturnTypeAst).entity;
    try expectEqual(return_type.get(components.AstKind), .symbol);
    try expectEqualStrings(literalOf(return_type), "T");
    try expectEqual(overloads[0].get(components.Body).slice().len, 1);
}

test "parse implicit type variables" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\min(x, y) {
        \\  if x < y { x } else { y }
        \\}
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const overloads = top_level.findString("min").get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const start = overloads[0];
    try expect(!start.contains(components.TypeVariables));
    const parameters = start.get(components.Parameters).slice();
    try expectEqual(parameters.len, 2);
    try expectEqualStrings(literalOf(parameters[0]), "x");
    try expect(!parameters[0].contains(components.TypeAst));
    try expectEqualStrings(literalOf(parameters[1]), "y");
    try expect(!parameters[1].contains(components.TypeAst));
    try expect(!start.contains(components.ReturnTypeAst));
    try expectEqual(overloads[0].get(components.Body).slice().len, 1);
}
