const std = @import("std");
const Arena = std.heap.ArenaAllocator;
const assert = std.debug.assert;
const panic = std.debug.panic;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const initCodebase = @import("codebase.zig").initCodebase;
const List = @import("list.zig").List;
const ecs = @import("ecs.zig");
const Entity = ecs.Entity;
const ECS = ecs.ECS;
const Strings = @import("strings.zig").Strings;
const components = @import("components.zig");
const TokenKind = components.TokenKind;
const Literal = components.Literal;
const Span = components.Span;
const Position = components.Position;
const Kind = components.AstKind;
const BinaryOp = components.BinaryOp;
const Function = components.Function;
const Type = components.Type;
const Define = components.Define;
const Indent = components.Indent;
const Call = components.Call;
const tokenizer = @import("tokenizer.zig");
const Tokens = tokenizer.Tokens;
const tokenize = tokenizer.tokenize;
const literalOf = @import("test_utils.zig").literalOf;

fn parseExpression(codebase: *ECS, tokens: *Tokens, precedence: u64) error{OutOfMemory}!Entity {
    const token = tokens.next().?;
    var left = try prefixParser(token);
    while (true) {
        if (InfixParser.init(tokens)) |parser| {
            const parser_precedence = parser.precedence();
            if (precedence <= parser_precedence) {
                left = try parser.run(codebase, tokens, left, parser_precedence);
            } else return left;
        } else return left;
    }
}

fn prefixParser(token: Entity) !Entity {
    const kind = token.get(TokenKind);
    return try switch (kind) {
        .symbol => token.set(.{Kind.symbol}),
        .int => token.set(.{Kind.int}),
        .function => token.set(.{Kind.function}),
        else => panic("\nno prefix parser for = {}\n", .{kind}),
    };
}

const NEXT_PRECEDENCE: u64 = 10;
const LOWEST: u64 = 0;
const DEFINE: u64 = LOWEST;
const ADD: u64 = DEFINE + NEXT_PRECEDENCE;
const MULTIPLY: u64 = ADD + NEXT_PRECEDENCE;
const CALL: u64 = MULTIPLY + NEXT_PRECEDENCE;

const InfixParser = union(enum) {
    binary_op: struct { kind: BinaryOp.Kind, precedence: u64 },
    define,
    call,

    fn init(tokens: *Tokens) ?InfixParser {
        if (tokens.peek()) |token| {
            const kind = token.get(TokenKind);
            return switch (kind) {
                .plus => .{ .binary_op = .{ .kind = .add, .precedence = ADD } },
                .times => .{ .binary_op = .{ .kind = .multiply, .precedence = MULTIPLY } },
                .equal => .define,
                .left_paren => .call,
                else => null,
            };
        } else {
            return null;
        }
    }

    fn precedence(self: InfixParser) u64 {
        return switch (self) {
            .binary_op => |binary_op| binary_op.precedence,
            .define => DEFINE,
            .call => CALL,
        };
    }

    fn run(self: InfixParser, codebase: *ECS, tokens: *Tokens, left: Entity, parser_precedence: u64) !Entity {
        _ = tokens.next();
        return try switch (self) {
            .binary_op => |binary_op| parseBinaryOp(
                codebase,
                tokens,
                left,
                binary_op.kind,
                parser_precedence,
            ),
            .define => parseDefine(codebase, tokens, left, parser_precedence),
            .call => parseCall(codebase, tokens, left, parser_precedence),
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

fn parseDefine(codebase: *ECS, tokens: *Tokens, name: Entity, precedence: u64) !Entity {
    assert(name.get(Kind) == .symbol);
    const value = try parseExpression(codebase, tokens, precedence);
    const define = Define{ .name = name, .value = value };
    const span = Span{
        .begin = name.get(Span).begin,
        .end = value.get(Span).end,
    };
    return try codebase.createEntity(.{ Kind.define, define, span });
}

fn parseCall(codebase: *ECS, tokens: *Tokens, name: Entity, precedence: u64) !Entity {
    assert(name.get(Kind) == .symbol);
    var arguments = List(Entity).init(codebase.arena);
    const argument = try parseExpression(codebase, tokens, precedence);
    try arguments.push(argument);
    const end = tokens.consume(.right_paren).get(Span).end;
    const call = Call{ .function = name, .arguments = arguments };
    const span = Span{
        .begin = name.get(Span).begin,
        .end = end,
    };
    return try codebase.createEntity(.{ Kind.call, call, span });
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

fn parseFunctionParameters(codebase: *ECS, tokens: *Tokens) !List(Entity) {
    var parameters = List(Entity).init(codebase.arena);
    _ = tokens.consume(.left_paren);
    while (tokens.next()) |token| {
        const kind = token.get(TokenKind);
        switch (kind) {
            .right_paren => break,
            .comma => continue,
            .symbol => {
                _ = tokens.consume(.colon);
                const type_ = Type{ .entity = try parseExpression(codebase, tokens, LOWEST) };
                _ = try token.set(.{type_});
                try parameters.push(token);
            },
            else => panic("\ninvalid token kind, {}\n", .{kind}),
        }
    }
    return parameters;
}

// TODO: [feature] support multiple expressions in a function body with a similar indent
fn parseFunctionBody(codebase: *ECS, tokens: *Tokens) !List(Entity) {
    var body = List(Entity).init(codebase.arena);
    if (tokens.peek().?.get(TokenKind) == .indent) {
        const spaces = tokens.next().?.get(Indent).spaces;
        while (true) {
            try body.push(try parseExpression(codebase, tokens, LOWEST));
            if (tokens.peek()) |token| {
                if (token.get(TokenKind) != .indent or token.get(Indent).spaces != spaces)
                    break;
                _ = tokens.next();
            } else break;
        }
    } else {
        try body.push(try parseExpression(codebase, tokens, LOWEST));
    }
    return body;
}

fn parseFunction(codebase: *ECS, tokens: *Tokens) !Entity {
    const begin = tokens.consume(.function).get(Span).begin;
    const name = try tokens.next().?.set(.{Kind.symbol});
    const parameters = try parseFunctionParameters(codebase, tokens);
    const return_type = try parseExpression(codebase, tokens, LOWEST);
    _ = tokens.consume(.colon);
    const body = try parseFunctionBody(codebase, tokens);
    const end = body.nth(body.len - 1).get(Span).end;
    const span = components.Span{ .begin = begin, .end = end };
    const function = Function{
        .name = name,
        .parameters = parameters,
        .return_type = return_type,
        .body = body,
    };
    return try codebase.createEntity(.{ Kind.function, function, span });
}

test "parse function with int literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const code = "fn start() u64: 0";
    var tokens = try tokenize(&codebase, code);
    const entity = try parseFunction(&codebase, &tokens);
    try expectEqual(entity.get(Kind), .function);
    const function = entity.get(Function);
    try expectEqualStrings(literalOf(function.name), "start");
    try expectEqual(entity.get(Span), Span{
        .begin = Position{ .column = 0, .row = 0 },
        .end = Position{ .column = 17, .row = 0 },
    });
    try expectEqual(function.parameters.len, 0);
    try expectEqual(function.return_type.get(Kind), .symbol);
    try expectEqualStrings(literalOf(function.return_type), "u64");
    try expectEqual(function.return_type.get(Span), Span{
        .begin = Position{ .column = 11, .row = 0 },
        .end = Position{ .column = 14, .row = 0 },
    });
    try expectEqual(function.body.len, 1);
    const zero = function.body.nth(0);
    try expectEqual(zero.get(Kind), .int);
    try expectEqualStrings(literalOf(zero), "0");
    try expectEqual(zero.get(Span), Span{
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
    const function = (try parseFunction(&codebase, &tokens)).get(Function);
    try expectEqualStrings(literalOf(function.name), "start");
    try expectEqual(function.parameters.len, 0);
    try expectEqualStrings(literalOf(function.return_type), "u64");
    try expectEqual(function.body.len, 1);
    const entity = function.body.nth(0);
    try expectEqual(entity.get(Kind), .binary_op);
    const add = entity.get(BinaryOp);
    try expectEqual(add.kind, .add);
    const left = add.left;
    try expectEqual(left.get(Kind), .int);
    try expectEqualStrings(literalOf(left), "5");
    const right = add.right;
    try expectEqual(right.get(Kind), .symbol);
    try expectEqualStrings(literalOf(right), "x");
}

test "parse function with compound binary entity" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const code = "fn line() u64: m * x + b";
    var tokens = try tokenize(&codebase, code);
    const function = (try parseFunction(&codebase, &tokens)).get(Function);
    try expectEqualStrings(literalOf(function.name), "line");
    try expectEqual(function.parameters.len, 0);
    try expectEqual(function.body.len, 1);
    const add = function.body.nth(0).get(BinaryOp);
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

test "parse function parameters" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const code = "fn add(x: u64, y: u64) u64: x + y";
    var tokens = try tokenize(&codebase, code);
    const function = (try parseFunction(&codebase, &tokens)).get(Function);
    try expectEqualStrings(literalOf(function.name), "add");
    try expectEqual(function.parameters.len, 2);
    const param0 = function.parameters.nth(0);
    try expectEqualStrings(literalOf(param0), "x");
    try expectEqualStrings(literalOf(param0.get(Type).entity), "u64");
    const param1 = function.parameters.nth(1);
    try expectEqualStrings(literalOf(param1), "y");
    try expectEqualStrings(literalOf(param1.get(Type).entity), "u64");
    try expectEqualStrings(literalOf(function.return_type), "u64");
    try expectEqual(function.body.len, 1);
    const add = function.body.nth(0).get(BinaryOp);
    try expectEqual(add.kind, .add);
    const x = add.left;
    try expectEqualStrings(literalOf(x), "x");
    const y = add.right;
    try expectEqual(y.get(Kind), .symbol);
    try expectEqualStrings(literalOf(y), "y");
}

test "parse function with newline" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const code =
        \\fn add(x: u64, y: u64) u64:
        \\  x + y
    ;
    var tokens = try tokenize(&codebase, code);
    const function = (try parseFunction(&codebase, &tokens)).get(Function);
    try expectEqualStrings(literalOf(function.name), "add");
    try expectEqual(function.parameters.len, 2);
    const param0 = function.parameters.nth(0);
    try expectEqualStrings(literalOf(param0), "x");
    try expectEqualStrings(literalOf(param0.get(Type).entity), "u64");
    const param1 = function.parameters.nth(1);
    try expectEqualStrings(literalOf(param1), "y");
    try expectEqualStrings(literalOf(param1.get(Type).entity), "u64");
    try expectEqual(function.body.len, 1);
    const add = function.body.nth(0).get(BinaryOp);
    try expectEqual(add.kind, .add);
    const x = add.left;
    try expectEqualStrings(literalOf(x), "x");
    const y = add.right;
    try expectEqual(y.get(Kind), .symbol);
    try expectEqualStrings(literalOf(y), "y");
}

test "parse constant definition" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const code =
        \\fn f() u64:
        \\  x = 5
        \\  y = 15
        \\  x + y
    ;
    var tokens = try tokenize(&codebase, code);
    const function = (try parseFunction(&codebase, &tokens)).get(Function);
    try expectEqualStrings(literalOf(function.name), "f");
    try expectEqualStrings(literalOf(function.return_type), "u64");
    try expectEqual(function.parameters.len, 0);
    try expectEqual(function.body.len, 3);
    const x = function.body.nth(0).get(Define);
    try expectEqualStrings(literalOf(x.name), "x");
    try expectEqualStrings(literalOf(x.value), "5");
    const y = function.body.nth(1).get(Define);
    try expectEqualStrings(literalOf(y.name), "y");
    try expectEqualStrings(literalOf(y.value), "15");
    const add = function.body.nth(2).get(BinaryOp);
    try expectEqual(add.kind, .add);
    try expectEqualStrings(literalOf(add.left), "x");
    try expectEqualStrings(literalOf(add.right), "y");
}

test "parse constant definition with binary op" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const code =
        \\fn sum_of_squares(x: u64, y: u64) u64:
        \\  x2 = x * x
        \\  y2 = y * y
        \\  x2 + y2
    ;
    var tokens = try tokenize(&codebase, code);
    const function = (try parseFunction(&codebase, &tokens)).get(Function);
    try expectEqualStrings(literalOf(function.name), "sum_of_squares");
    try expectEqualStrings(literalOf(function.return_type), "u64");
    try expectEqual(function.parameters.len, 2);
    const param0 = function.parameters.nth(0);
    try expectEqualStrings(literalOf(param0), "x");
    try expectEqualStrings(literalOf(param0.get(Type).entity), "u64");
    const param1 = function.parameters.nth(1);
    try expectEqualStrings(literalOf(param1), "y");
    try expectEqualStrings(literalOf(param1.get(Type).entity), "u64");
    try expectEqual(function.body.len, 3);
    {
        const x2 = function.body.nth(0).get(Define);
        try expectEqualStrings(literalOf(x2.name), "x2");
        const multiply = x2.value.get(BinaryOp);
        try expectEqual(multiply.kind, .multiply);
        try expectEqualStrings(literalOf(multiply.left), "x");
        try expectEqualStrings(literalOf(multiply.right), "x");
    }
    {
        const y2 = function.body.nth(1).get(Define);
        try expectEqualStrings(literalOf(y2.name), "y2");
        const multiply = y2.value.get(BinaryOp);
        try expectEqual(multiply.kind, .multiply);
        try expectEqualStrings(literalOf(multiply.left), "y");
        try expectEqualStrings(literalOf(multiply.right), "y");
    }
    const add = function.body.nth(2).get(BinaryOp);
    try expectEqual(add.kind, .add);
    try expectEqualStrings(literalOf(add.left), "x2");
    try expectEqualStrings(literalOf(add.right), "y2");
}

test "parse function call" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const code =
        \\fn sum_of_squares(x: u64, y: u64) u64:
        \\  square(x) + square(y)
    ;
    var tokens = try tokenize(&codebase, code);
    const function = (try parseFunction(&codebase, &tokens)).get(Function);
    try expectEqualStrings(literalOf(function.name), "sum_of_squares");
    try expectEqualStrings(literalOf(function.return_type), "u64");
    try expectEqual(function.parameters.len, 2);
    const param0 = function.parameters.nth(0);
    try expectEqualStrings(literalOf(param0), "x");
    try expectEqualStrings(literalOf(param0.get(Type).entity), "u64");
    const param1 = function.parameters.nth(1);
    try expectEqualStrings(literalOf(param1), "y");
    try expectEqualStrings(literalOf(param1.get(Type).entity), "u64");
    try expectEqual(function.body.len, 1);
    const add = function.body.nth(0).get(BinaryOp);
    try expectEqual(add.kind, .add);
    {
        try expectEqual(add.left.get(Kind), .call);
        const call = add.left.get(Call);
        try expectEqualStrings(literalOf(call.function), "square");
        try expectEqual(call.arguments.len, 1);
        try expectEqualStrings(literalOf(call.arguments.nth(0)), "x");
    }
    {
        try expectEqual(add.right.get(Kind), .call);
        const call = add.right.get(Call);
        try expectEqualStrings(literalOf(call.function), "square");
        try expectEqual(call.arguments.len, 1);
        try expectEqualStrings(literalOf(call.arguments.nth(0)), "y");
    }
}
