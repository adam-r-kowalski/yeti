const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const panic = std.debug.panic;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const List = @import("list.zig").List;
const Codebase = @import("codebase.zig").Codebase;
const Entity = @import("ecs.zig").Entity;
const InternedString = @import("strings.zig").InternedString;
const components = @import("components.zig");
const TokenKind = components.TokenKind;
const Literal = components.Literal;
const Span = components.Span;
const Position = components.Position;
const Name = components.Name;
const ReturnType = components.ReturnType;
const Body = components.Body;
const Kind = components.AstKind;
const BinaryOpKind = components.BinaryOpKind;
const BinaryOp = components.BinaryOp;
const tokenizer = @import("tokenizer.zig");
const Tokens = tokenizer.Tokens;
const tokenize = tokenizer.tokenize;
const literalOf = @import("test_utils.zig").literalOf;

fn parseExpression(codebase: *Codebase, tokens: *Tokens) error{OutOfMemory}!Entity {
    const token = tokens.next().?;
    const left = try prefixParser(codebase, token);
    return try infixParser(codebase, tokens, left);
}

fn prefixParser(codebase: *Codebase, token: Entity) !Entity {
    const kind = token.get(TokenKind).*;
    return try switch (kind) {
        TokenKind.Symbol => parseOne(codebase, token, Kind.Symbol),
        TokenKind.Int => parseOne(codebase, token, Kind.Int),
        TokenKind.Fn => parseOne(codebase, token, Kind.Function),
        else => panic("\nno prefix parser for = {}\n", .{kind}),
    };
}

fn parseOne(codebase: *Codebase, token: Entity, kind: Kind) !Entity {
    const expression = try codebase.ecs.createEntity(.{kind});
    try expression.share(token, .{ Literal, Span });
    return expression;
}

fn infixParser(codebase: *Codebase, tokens: *Tokens, left: Entity) !Entity {
    if (tokens.peek()) |token| {
        const kind = token.get(TokenKind).*;
        return try switch (kind) {
            TokenKind.Plus => parseBinaryOp(codebase, tokens, left, BinaryOpKind.Add),
            else => left,
        };
    }
    return left;
}

fn parseBinaryOp(codebase: *Codebase, tokens: *Tokens, left: Entity, kind: BinaryOpKind) !Entity {
    tokens.advance();
    const right = try parseExpression(codebase, tokens);
    const op = BinaryOp{ .kind = kind, .left = left, .right = right };
    const span = Span{
        .begin = left.get(Span).begin,
        .end = right.get(Span).end,
    };
    return try codebase.ecs.createEntity(.{ Kind.BinaryOp, op, span });
}

test "parse symbol" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch panic("MEMORY LEAK", .{});
    const allocator = &gpa.allocator;
    var codebase = try Codebase.init(allocator);
    defer codebase.deinit();
    const code = "foo";
    var tokens = try tokenize(&codebase, code);
    defer tokens.deinit();
    const expression = try parseExpression(&codebase, &tokens);
    try expectEqual(expression.get(Kind).*, Kind.Symbol);
    try expectEqualStrings(literalOf(codebase, expression), "foo");
    try expectEqual(expression.get(Span).*, Span{
        .begin = Position{ .column = 0, .row = 0 },
        .end = Position{ .column = 3, .row = 0 },
    });
}

test "parse int" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch panic("MEMORY LEAK", .{});
    const allocator = &gpa.allocator;
    var codebase = try Codebase.init(allocator);
    defer codebase.deinit();
    const code = "35";
    var tokens = try tokenize(&codebase, code);
    defer tokens.deinit();
    const expression = try parseExpression(&codebase, &tokens);
    try expectEqual(expression.get(Kind).*, Kind.Int);
    try expectEqualStrings(literalOf(codebase, expression), "35");
    try expectEqual(expression.get(Span).*, Span{
        .begin = Position{ .column = 0, .row = 0 },
        .end = Position{ .column = 2, .row = 0 },
    });
}

fn parseFunction(codebase: *Codebase, tokens: *Tokens) !Entity {
    const begin = blk: {
        const token = tokens.next().?;
        assert(token.get(TokenKind).* == TokenKind.Fn);
        break :blk token.get(Span).begin;
    };
    const name = blk: {
        const token = tokens.next().?;
        assert(token.get(TokenKind).* == TokenKind.Symbol);
        const interned = token.get(Literal).interned;
        break :blk Name{ .interned = interned };
    };
    assert(tokens.next().?.get(TokenKind).* == TokenKind.LeftParen);
    assert(tokens.next().?.get(TokenKind).* == TokenKind.RightParen);
    const return_type = blk: {
        const expression = try parseExpression(codebase, tokens);
        break :blk ReturnType{ .expression = expression };
    };
    assert(tokens.next().?.get(TokenKind).* == TokenKind.Colon);
    var body = Body.init(codebase.allocator);
    const expression = try parseExpression(codebase, tokens);
    try body.expressions.push(expression);
    const end = expression.get(Span).end;
    const span = components.Span{ .begin = begin, .end = end };
    return try codebase.ecs.createEntity(.{ Kind.Function, name, return_type, body, span });
}

fn nameOf(codebase: Codebase, entity: Entity) []const u8 {
    return codebase.strings.get(entity.get(Name).interned);
}

test "parse function with int literal" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch panic("MEMORY LEAK", .{});
    const allocator = &gpa.allocator;
    var codebase = try Codebase.init(allocator);
    defer codebase.deinit();
    const code = "fn start() u64: 0";
    var tokens = try tokenize(&codebase, code);
    defer tokens.deinit();
    const function = try parseFunction(&codebase, &tokens);
    try expectEqual(function.get(Kind).*, Kind.Function);
    try expectEqualStrings(nameOf(codebase, function), "start");
    try expectEqual(function.get(Span).*, Span{
        .begin = Position{ .column = 0, .row = 0 },
        .end = Position{ .column = 17, .row = 0 },
    });
    const return_type = function.get(ReturnType).expression;
    try expectEqual(return_type.get(Kind).*, Kind.Symbol);
    try expectEqualStrings(literalOf(codebase, return_type), "u64");
    try expectEqual(return_type.get(Span).*, Span{
        .begin = Position{ .column = 11, .row = 0 },
        .end = Position{ .column = 14, .row = 0 },
    });
    const body = function.get(Body).expressions;
    try expectEqual(body.len, 1);
    const expression = body.data[0];
    try expectEqual(expression.get(Kind).*, Kind.Int);
    try expectEqualStrings(literalOf(codebase, expression), "0");
    try expectEqual(expression.get(Span).*, Span{
        .begin = Position{ .column = 16, .row = 0 },
        .end = Position{ .column = 17, .row = 0 },
    });
}

test "parse function with binary expression" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch panic("MEMORY LEAK", .{});
    const allocator = &gpa.allocator;
    var codebase = try Codebase.init(allocator);
    defer codebase.deinit();
    const code = "fn start() u64: 5 + x";
    var tokens = try tokenize(&codebase, code);
    defer tokens.deinit();
    const function = try parseFunction(&codebase, &tokens);
    try expectEqual(function.get(Kind).*, Kind.Function);
    try expectEqualStrings(nameOf(codebase, function), "start");
    try expectEqual(function.get(Span).*, Span{
        .begin = Position{ .column = 0, .row = 0 },
        .end = Position{ .column = 21, .row = 0 },
    });
    const return_type = function.get(ReturnType).expression;
    try expectEqual(return_type.get(Kind).*, Kind.Symbol);
    try expectEqualStrings(literalOf(codebase, return_type), "u64");
    try expectEqual(return_type.get(Span).*, Span{
        .begin = Position{ .column = 11, .row = 0 },
        .end = Position{ .column = 14, .row = 0 },
    });
    const body = function.get(Body).expressions;
    try expectEqual(body.len, 1);
    const expression = body.data[0];
    try expectEqual(expression.get(Kind).*, Kind.BinaryOp);
    try expectEqual(expression.get(Span).*, Span{
        .begin = Position{ .column = 16, .row = 0 },
        .end = Position{ .column = 21, .row = 0 },
    });
    const binary_op = expression.get(BinaryOp);
    try expectEqual(binary_op.kind, BinaryOpKind.Add);
    const left = binary_op.left;
    try expectEqual(left.get(Kind).*, Kind.Int);
    try expectEqualStrings(literalOf(codebase, left), "5");
    try expectEqual(left.get(Span).*, Span{
        .begin = Position{ .column = 16, .row = 0 },
        .end = Position{ .column = 17, .row = 0 },
    });
    const right = binary_op.right;
    try expectEqual(right.get(Kind).*, Kind.Symbol);
    try expectEqualStrings(literalOf(codebase, right), "x");
    try expectEqual(right.get(Span).*, Span{
        .begin = Position{ .column = 20, .row = 0 },
        .end = Position{ .column = 21, .row = 0 },
    });
}
