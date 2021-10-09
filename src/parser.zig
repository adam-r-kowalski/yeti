const std = @import("std");
const Arena = std.heap.ArenaAllocator;
const assert = std.debug.assert;
const panic = std.debug.panic;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const initCodebase = @import("codebase.zig").initCodebase;
const ecs = @import("ecs.zig");
const Entity = ecs.Entity;
const ECS = ecs.ECS;
const Strings = @import("strings.zig").Strings;
const components = @import("components.zig");
const TokenKind = components.TokenKind;
const Literal = components.Literal;
const Span = components.Span;
const Position = components.Position;
const Name = components.Name;
const ReturnType = components.ReturnType;
const Body = components.Body;
const Kind = components.AstKind;
const BinaryOp = components.BinaryOp;
const Parameters = components.Parameters;
const tokenizer = @import("tokenizer.zig");
const Tokens = tokenizer.Tokens;
const tokenize = tokenizer.tokenize;
const literalOf = @import("test_utils.zig").literalOf;

const NEXT_PRECEDENCE: u64 = 10;
const LOWEST: u64 = 0;
const ADD: u64 = LOWEST + NEXT_PRECEDENCE;
const MULTIPLY: u64 = ADD + NEXT_PRECEDENCE;

fn parseExpression(codebase: *ECS, tokens: *Tokens, precedence: u64) error{OutOfMemory}!Entity {
    const token = tokens.next().?;
    var left = try prefixParser(codebase, token);
    while (true) {
        if (InfixParser.init(tokens)) |parser| {
            if (precedence <= parser.precedence()) {
                left = try parser.run(codebase, tokens, left);
            } else return left;
        } else return left;
    }
}

fn prefixParser(codebase: *ECS, token: Entity) !Entity {
    const kind = token.get(TokenKind);
    return try switch (kind) {
        .symbol => parseOne(codebase, token, .symbol),
        .int => parseOne(codebase, token, .int),
        .function => parseOne(codebase, token, .function),
        else => panic("\nno prefix parser for = {}\n", .{kind}),
    };
}

fn parseOne(codebase: *ECS, token: Entity, kind: Kind) !Entity {
    return try codebase.createEntity(.{
        kind,
        token.get(Literal),
        token.get(Span),
    });
}

const InfixParser = union(enum) {
    binary_op: struct { kind: BinaryOp.Kind, precedence: u64 },

    fn init(tokens: *Tokens) ?InfixParser {
        if (tokens.peek()) |token| {
            const kind = token.get(TokenKind);
            return switch (kind) {
                .plus => .{ .binary_op = .{ .kind = .add, .precedence = ADD } },
                .times => .{ .binary_op = .{ .kind = .multiply, .precedence = MULTIPLY } },
                else => null,
            };
        } else {
            return null;
        }
    }

    fn precedence(self: InfixParser) u64 {
        return switch (self) {
            .binary_op => |binary_op| binary_op.precedence,
        };
    }

    fn run(self: InfixParser, codebase: *ECS, tokens: *Tokens, left: Entity) !Entity {
        tokens.advance();
        return switch (self) {
            .binary_op => |binary_op| try parseBinaryOp(codebase, tokens, left, binary_op.kind, binary_op.precedence),
        };
    }
};

fn parseBinaryOp(codebase: *ECS, tokens: *Tokens, left: Entity, kind: BinaryOp.Kind, precedence: u64) !Entity {
    const right = try parseExpression(codebase, tokens, precedence);
    const op = BinaryOp{ .kind = kind, .left = left, .right = right };
    const span = Span{
        .begin = left.get(Span).begin,
        .end = right.get(Span).end,
    };
    return try codebase.createEntity(.{ Kind.binary_op, op, span });
}

test "parse symbol" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const code = "foo";
    var tokens = try tokenize(&codebase, code);
    const entity = try parseExpression(&codebase, &tokens, LOWEST);
    try expectEqual(entity.get(Kind), .symbol);
    try expectEqualStrings(literalOf(entity), "foo");
    try expectEqual(entity.get(Span), Span{
        .begin = Position{ .column = 0, .row = 0 },
        .end = Position{ .column = 3, .row = 0 },
    });
}

test "parse int" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const code = "35";
    var tokens = try tokenize(&codebase, code);
    const entity = try parseExpression(&codebase, &tokens, LOWEST);
    try expectEqual(entity.get(Kind), .int);
    try expectEqualStrings(literalOf(entity), "35");
    try expectEqual(entity.get(Span), Span{
        .begin = Position{ .column = 0, .row = 0 },
        .end = Position{ .column = 2, .row = 0 },
    });
}

fn parseFunctionParameters(codebase: *ECS, tokens: *Tokens) !Parameters {
    var parameters = Parameters.init(codebase.arena);
    _ = tokens.consume(.left_paren);
    while (tokens.next()) |token| {
        const kind = token.get(TokenKind);
        switch (kind) {
            .right_paren => return parameters,
            .symbol => {
                const parameter = try codebase.createEntity(.{});
                try parameters.entities.push(parameter);
                _ = tokens.consume(.colon);
                _ = tokens.consume(.symbol);
            },
            else => panic("\ninvalid token kind, {}\n", .{kind}),
        }
    }
    return parameters;
}

fn parseFunctionName(codebase: *ECS, tokens: *Tokens) !Name {
    const token = tokens.next().?;
    return Name.init(try parseOne(codebase, token, .symbol));
}

fn parseFunction(codebase: *ECS, tokens: *Tokens) !Entity {
    const begin = tokens.consume(.function).get(Span).begin;
    const name = try parseFunctionName(codebase, tokens);
    const parameters = try parseFunctionParameters(codebase, tokens);
    const return_type = ReturnType.init(try parseExpression(codebase, tokens, LOWEST));
    _ = tokens.consume(.colon);
    var body = Body.init(codebase.arena);
    const entity = try parseExpression(codebase, tokens, LOWEST);
    try body.entities.push(entity);
    const end = entity.get(Span).end;
    const span = components.Span{ .begin = begin, .end = end };
    return try codebase.createEntity(.{ Kind.function, name, parameters, return_type, body, span });
}

test "parse function with int literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const code = "fn start() u64: 0";
    var tokens = try tokenize(&codebase, code);
    const function = try parseFunction(&codebase, &tokens);
    try expectEqual(function.get(Kind), .function);
    const name = function.get(Name).entity;
    try expectEqualStrings(literalOf(name), "start");
    try expectEqual(function.get(Span), Span{
        .begin = Position{ .column = 0, .row = 0 },
        .end = Position{ .column = 17, .row = 0 },
    });
    const return_type = function.get(ReturnType).entity;
    try expectEqual(return_type.get(Kind), .symbol);
    try expectEqualStrings(literalOf(return_type), "u64");
    try expectEqual(return_type.get(Span), Span{
        .begin = Position{ .column = 11, .row = 0 },
        .end = Position{ .column = 14, .row = 0 },
    });
    const body = function.get(Body).entities;
    try expectEqual(body.len, 1);
    const entity = body.nth(0);
    try expectEqual(entity.get(Kind), .int);
    try expectEqualStrings(literalOf(entity), "0");
    try expectEqual(entity.get(Span), Span{
        .begin = Position{ .column = 16, .row = 0 },
        .end = Position{ .column = 17, .row = 0 },
    });
}

test "parse function with binary entity" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const code = "fn start() u64: 5 + x";
    var tokens = try tokenize(&codebase, code);
    const function = try parseFunction(&codebase, &tokens);
    try expectEqual(function.get(Kind), .function);
    const name = function.get(Name).entity;
    try expectEqualStrings(literalOf(name), "start");
    try expectEqual(function.get(Span), Span{
        .begin = Position{ .column = 0, .row = 0 },
        .end = Position{ .column = 21, .row = 0 },
    });
    const return_type = function.get(ReturnType).entity;
    try expectEqual(return_type.get(Kind), .symbol);
    try expectEqualStrings(literalOf(return_type), "u64");
    try expectEqual(return_type.get(Span), Span{
        .begin = Position{ .column = 11, .row = 0 },
        .end = Position{ .column = 14, .row = 0 },
    });
    const body = function.get(Body).entities;
    try expectEqual(body.len, 1);
    const entity = body.nth(0);
    try expectEqual(entity.get(Kind), .binary_op);
    try expectEqual(entity.get(Span), Span{
        .begin = Position{ .column = 16, .row = 0 },
        .end = Position{ .column = 21, .row = 0 },
    });
    const binary_op = entity.get(BinaryOp);
    try expectEqual(binary_op.kind, .add);
    const left = binary_op.left;
    try expectEqual(left.get(Kind), .int);
    try expectEqualStrings(literalOf(left), "5");
    try expectEqual(left.get(Span), Span{
        .begin = Position{ .column = 16, .row = 0 },
        .end = Position{ .column = 17, .row = 0 },
    });
    const right = binary_op.right;
    try expectEqual(right.get(Kind), .symbol);
    try expectEqualStrings(literalOf(right), "x");
    try expectEqual(right.get(Span), Span{
        .begin = Position{ .column = 20, .row = 0 },
        .end = Position{ .column = 21, .row = 0 },
    });
}

test "parse function with compound binary entity" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const code = "fn line() u64: m * x + b";
    var tokens = try tokenize(&codebase, code);
    const function = try parseFunction(&codebase, &tokens);
    try expectEqual(function.get(Kind), .function);
    const name = function.get(Name).entity;
    try expectEqualStrings(literalOf(name), "line");
    const body = function.get(Body).entities;
    try expectEqual(body.len, 1);
    const add = body.nth(0).get(BinaryOp);
    try expectEqual(add.kind, .add);
    const multiply = add.left.get(BinaryOp);
    try expectEqual(multiply.kind, .multiply);
    const m = multiply.left;
    try expectEqual(m.get(Kind), .symbol);
    try expectEqualStrings(literalOf(m), "m");
    const x = multiply.right;
    try expectEqual(x.get(Kind), .symbol);
    try expectEqualStrings(literalOf(x), "x");
    const b = add.right;
    try expectEqual(b.get(Kind), .symbol);
    try expectEqualStrings(literalOf(b), "b");
}

test "parse function argument" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const code = "fn identity(x: u64) u64: x";
    var tokens = try tokenize(&codebase, code);
    const function = try parseFunction(&codebase, &tokens);
    try expectEqual(function.get(Kind), .function);
    const name = function.get(Name).entity;
    try expectEqualStrings(literalOf(name), "identity");
    const body = function.get(Body).entities;
    try expectEqual(body.len, 1);
}
