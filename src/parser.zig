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

const NEXT_PRECEDENCE: u64 = 10;
const LOWEST: u64 = 0;
const ADD: u64 = LOWEST + NEXT_PRECEDENCE;
const MULTIPLY: u64 = ADD + NEXT_PRECEDENCE;

fn parseExpression(codebase: *Codebase, tokens: *Tokens, precedence: u64) error{OutOfMemory}!Entity {
    const token = tokens.next().?;
    var left = try prefixParser(codebase, token);
    while (true) {
        if (InfixParser.init(tokens)) |parser| {
            if (precedence <= parser.precedence()) {
                left = try parser.run(codebase, tokens, left);
            } else break;
        } else break;
    }
    return left;
}

fn prefixParser(codebase: *Codebase, token: Entity) !Entity {
    const kind = token.get(TokenKind).*;
    return try switch (kind) {
        TokenKind.symbol => parseOne(codebase, token, Kind.symbol),
        TokenKind.int => parseOne(codebase, token, Kind.int),
        TokenKind.function => parseOne(codebase, token, Kind.function),
        else => panic("\nno prefix parser for = {}\n", .{kind}),
    };
}

fn parseOne(codebase: *Codebase, token: Entity, kind: Kind) !Entity {
    const expression = try codebase.ecs.createEntity(.{kind});
    try expression.share(token, .{ Literal, Span });
    return expression;
}

const InfixParser = union(enum) {
    binary_op: struct { kind: BinaryOpKind, precedence: u64 },

    fn init(tokens: *Tokens) ?InfixParser {
        if (tokens.peek()) |token| {
            const kind = token.get(TokenKind).*;
            return switch (kind) {
                TokenKind.plus => .{ .binary_op = .{ .kind = BinaryOpKind.add, .precedence = ADD } },
                TokenKind.times => .{ .binary_op = .{ .kind = BinaryOpKind.multiply, .precedence = MULTIPLY } },
                else => null,
            };
        } else {
            return null;
        }
    }

    fn precedence(self: InfixParser) u64 {
        return switch (self) {
            InfixParser.binary_op => |binary_op| binary_op.precedence,
        };
    }

    fn run(self: InfixParser, codebase: *Codebase, tokens: *Tokens, left: Entity) !Entity {
        tokens.advance();
        return switch (self) {
            InfixParser.binary_op => |binary_op| try parseBinaryOp(codebase, tokens, left, binary_op.kind, binary_op.precedence),
        };
    }
};

fn parseBinaryOp(codebase: *Codebase, tokens: *Tokens, left: Entity, kind: BinaryOpKind, precedence: u64) !Entity {
    const right = try parseExpression(codebase, tokens, precedence);
    const op = BinaryOp{ .kind = kind, .left = left, .right = right };
    const span = Span{
        .begin = left.get(Span).begin,
        .end = right.get(Span).end,
    };
    return try codebase.ecs.createEntity(.{ Kind.binary_op, op, span });
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
    const expression = try parseExpression(&codebase, &tokens, LOWEST);
    try expectEqual(expression.get(Kind).*, Kind.symbol);
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
    const expression = try parseExpression(&codebase, &tokens, LOWEST);
    try expectEqual(expression.get(Kind).*, Kind.int);
    try expectEqualStrings(literalOf(codebase, expression), "35");
    try expectEqual(expression.get(Span).*, Span{
        .begin = Position{ .column = 0, .row = 0 },
        .end = Position{ .column = 2, .row = 0 },
    });
}

fn consume(tokens: *Tokens, kind: TokenKind) Entity {
    const token = tokens.next().?;
    assert(token.get(TokenKind).* == kind);
    return token;
}

fn parseFunction(codebase: *Codebase, tokens: *Tokens) !Entity {
    const begin = consume(tokens, TokenKind.function).get(Span).begin;
    const name = Name.init(consume(tokens, TokenKind.symbol));
    _ = consume(tokens, TokenKind.left_paren);
    _ = consume(tokens, TokenKind.right_paren);
    const return_type = ReturnType.init(try parseExpression(codebase, tokens, LOWEST));
    _ = consume(tokens, TokenKind.colon);
    var body = Body.init(codebase.allocator);
    const expression = try parseExpression(codebase, tokens, LOWEST);
    try body.expressions.push(expression);
    const end = expression.get(Span).end;
    const span = components.Span{ .begin = begin, .end = end };
    return try codebase.ecs.createEntity(.{ Kind.function, name, return_type, body, span });
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
    try expectEqual(function.get(Kind).*, Kind.function);
    try expectEqualStrings(nameOf(codebase, function), "start");
    try expectEqual(function.get(Span).*, Span{
        .begin = Position{ .column = 0, .row = 0 },
        .end = Position{ .column = 17, .row = 0 },
    });
    const return_type = function.get(ReturnType).expression;
    try expectEqual(return_type.get(Kind).*, Kind.symbol);
    try expectEqualStrings(literalOf(codebase, return_type), "u64");
    try expectEqual(return_type.get(Span).*, Span{
        .begin = Position{ .column = 11, .row = 0 },
        .end = Position{ .column = 14, .row = 0 },
    });
    const body = function.get(Body).expressions;
    try expectEqual(body.len, 1);
    const expression = body.data[0];
    try expectEqual(expression.get(Kind).*, Kind.int);
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
    try expectEqual(function.get(Kind).*, Kind.function);
    try expectEqualStrings(nameOf(codebase, function), "start");
    try expectEqual(function.get(Span).*, Span{
        .begin = Position{ .column = 0, .row = 0 },
        .end = Position{ .column = 21, .row = 0 },
    });
    const return_type = function.get(ReturnType).expression;
    try expectEqual(return_type.get(Kind).*, Kind.symbol);
    try expectEqualStrings(literalOf(codebase, return_type), "u64");
    try expectEqual(return_type.get(Span).*, Span{
        .begin = Position{ .column = 11, .row = 0 },
        .end = Position{ .column = 14, .row = 0 },
    });
    const body = function.get(Body).expressions;
    try expectEqual(body.len, 1);
    const expression = body.data[0];
    try expectEqual(expression.get(Kind).*, Kind.binary_op);
    try expectEqual(expression.get(Span).*, Span{
        .begin = Position{ .column = 16, .row = 0 },
        .end = Position{ .column = 21, .row = 0 },
    });
    const binary_op = expression.get(BinaryOp);
    try expectEqual(binary_op.kind, BinaryOpKind.add);
    const left = binary_op.left;
    try expectEqual(left.get(Kind).*, Kind.int);
    try expectEqualStrings(literalOf(codebase, left), "5");
    try expectEqual(left.get(Span).*, Span{
        .begin = Position{ .column = 16, .row = 0 },
        .end = Position{ .column = 17, .row = 0 },
    });
    const right = binary_op.right;
    try expectEqual(right.get(Kind).*, Kind.symbol);
    try expectEqualStrings(literalOf(codebase, right), "x");
    try expectEqual(right.get(Span).*, Span{
        .begin = Position{ .column = 20, .row = 0 },
        .end = Position{ .column = 21, .row = 0 },
    });
}

test "parse function with compound binary expression" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch panic("MEMORY LEAK", .{});
    const allocator = &gpa.allocator;
    var codebase = try Codebase.init(allocator);
    defer codebase.deinit();
    const code = "fn line() u64: m * x + b";
    var tokens = try tokenize(&codebase, code);
    defer tokens.deinit();
    const function = try parseFunction(&codebase, &tokens);
    try expectEqual(function.get(Kind).*, Kind.function);
    try expectEqualStrings(nameOf(codebase, function), "line");
    const body = function.get(Body).expressions;
    try expectEqual(body.len, 1);
    const add = body.data[0].get(BinaryOp);
    try expectEqual(add.kind, BinaryOpKind.add);
    const multiply = add.left.get(BinaryOp);
    try expectEqual(multiply.kind, BinaryOpKind.multiply);
    const m = multiply.left;
    try expectEqual(m.get(Kind).*, Kind.symbol);
    try expectEqualStrings(literalOf(codebase, m), "m");
    const x = multiply.right;
    try expectEqual(x.get(Kind).*, Kind.symbol);
    try expectEqualStrings(literalOf(codebase, x), "x");
    const b = add.right;
    try expectEqual(b.get(Kind).*, Kind.symbol);
    try expectEqualStrings(literalOf(codebase, b), "b");
}
