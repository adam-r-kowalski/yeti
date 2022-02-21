const std = @import("std");
const Arena = std.heap.ArenaAllocator;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const yeti = @import("yeti");
const initCodebase = yeti.initCodebase;
const tokenize = yeti.tokenize;
const parseExpression = yeti.parser.parseExpression;
const parseFunction = yeti.parser.parseFunction;
const parseImport = yeti.parser.parseImport;
const parse = yeti.parse;
const LOWEST = yeti.parser.LOWEST;
const components = yeti.components;
const literalOf = yeti.test_utils.literalOf;

test "parse import and function" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\math = import("math.yeti")
        \\
        \\start(): u64 {
        \\  math.sum_of_squares(10, 56 * 3)
        \\}
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const math = top_level.findString("math");
    try expectEqual(math.get(components.AstKind), .import);
    try expectEqualStrings(literalOf(math.get(components.Path).entity), "math.yeti");
    const start = top_level.findString("start");
    const overloads = start.get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const body = overloads[0].get(components.Body).slice();
    try expectEqual(body.len, 1);
    const dot = body[0];
    try expectEqual(dot.get(components.AstKind), .binary_op);
    const dot_arguments = dot.get(components.Arguments).slice();
    try expectEqualStrings(literalOf(dot_arguments[0]), "math");
    const sum_of_squares = dot_arguments[1];
    const callable = sum_of_squares.get(components.Callable).entity;
    try expectEqualStrings(literalOf(callable), "sum_of_squares");
    const sum_of_squares_arguments = sum_of_squares.get(components.Arguments).slice();
    try expectEqualStrings(literalOf(sum_of_squares_arguments[0]), "10");
    const multiply = sum_of_squares_arguments[1];
    try expectEqual(multiply.get(components.BinaryOp), .multiply);
    const arguments = multiply.get(components.Arguments).slice();
    try expectEqualStrings(literalOf(arguments[0]), "56");
    try expectEqualStrings(literalOf(arguments[1]), "3");
}
