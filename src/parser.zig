const std = @import("std");
const Arena = std.heap.ArenaAllocator;
const assert = std.debug.assert;
const panic = std.debug.panic;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const initCodebase = @import("init_codebase.zig").initCodebase;
const List = @import("list.zig").List;
const ecs = @import("ecs.zig");
const Entity = ecs.Entity;
const ECS = ecs.ECS;
const strings = @import("strings.zig");
const Strings = strings.Strings;
const InternedString = strings.InternedString;
const components = @import("components.zig");
const TokenKind = components.TokenKind;
const Literal = components.Literal;
const Span = components.Span;
const Position = components.Position;
const Kind = components.AstKind;
const BinaryOp = components.BinaryOp;
const Parameters = components.Parameters;
const Arguments = components.Arguments;
const Body = components.Body;
const Name = components.Name;
const ReturnType = components.ReturnType;
const Type = components.Type;
const Value = components.Value;
const Indent = components.Indent;
const Callable = components.Callable;
const Imports = components.Imports;
const TopLevel = components.TopLevel;
const Unqualified = components.Unqualified;
const Overloads = components.Overloads;
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
        else => panic("\nno prefix parser for = {}\n", .{kind}),
    };
}

const NEXT_PRECEDENCE: u64 = 10;
const LOWEST: u64 = 0;
const DEFINE: u64 = LOWEST;
const ADD: u64 = DEFINE + NEXT_PRECEDENCE;
const MULTIPLY: u64 = ADD + NEXT_PRECEDENCE;
const DOT: u64 = MULTIPLY + NEXT_PRECEDENCE;
const CALL: u64 = DOT + NEXT_PRECEDENCE;
const HIGHEST: u64 = CALL;

const InfixParser = union(enum) {
    binary_op: struct { op: BinaryOp, precedence: u64 },
    define,
    call,

    fn init(tokens: *Tokens) ?InfixParser {
        if (tokens.peek()) |token| {
            const kind = token.get(TokenKind);
            return switch (kind) {
                .plus => .{ .binary_op = .{ .op = .add, .precedence = ADD } },
                .times => .{ .binary_op = .{ .op = .multiply, .precedence = MULTIPLY } },
                .dot => .{ .binary_op = .{ .op = .dot, .precedence = DOT } },
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
                binary_op.op,
                parser_precedence,
            ),
            .define => parseDefine(codebase, tokens, left, parser_precedence),
            .call => parseCall(codebase, tokens, left),
        };
    }
};

fn parseBinaryOp(codebase: *ECS, tokens: *Tokens, left: Entity, op: BinaryOp, precedence: u64) !Entity {
    const right = try parseExpression(codebase, tokens, precedence);
    const entities = try codebase.arena.allocator.alloc(Entity, 2);
    entities[0] = left;
    entities[1] = right;
    const arguments = Arguments{ .entities = entities };
    return try codebase.createEntity(.{
        Kind.binary_op,
        op,
        Span.init(left.get(Span).begin, right.get(Span).end),
        arguments,
    });
}

fn parseDefine(codebase: *ECS, tokens: *Tokens, name: Entity, precedence: u64) !Entity {
    assert(name.get(Kind) == .symbol);
    const value = try parseExpression(codebase, tokens, precedence);
    return try codebase.createEntity(.{
        Kind.define,
        Name.init(name),
        Value.init(value),
        Span.init(name.get(Span).begin, value.get(Span).end),
    });
}

fn parseCall(codebase: *ECS, tokens: *Tokens, callable: Entity) !Entity {
    var arguments = List(Entity, .{}).init(&codebase.arena.allocator);
    while (tokens.peek()) |token| {
        switch (token.get(TokenKind)) {
            .right_paren => {
                return try codebase.createEntity(.{
                    Kind.call,
                    Callable.init(callable),
                    Arguments.init(arguments.slice()),
                    Span.init(callable.get(Span).begin, tokens.next().?.get(Span).end),
                });
            },
            .comma => _ = tokens.next(),
            else => try arguments.append(try parseExpression(codebase, tokens, LOWEST)),
        }
    }
    panic("compiler bug!!!", .{});
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
    var parameters = List(Entity, .{}).init(&codebase.arena.allocator);
    _ = tokens.consume(.left_paren);
    while (tokens.next()) |token| {
        const kind = token.get(TokenKind);
        switch (kind) {
            .right_paren => break,
            .comma => continue,
            .symbol => {
                _ = tokens.consume(.colon);
                _ = try token.set(.{
                    Type.init(try parseExpression(codebase, tokens, LOWEST)),
                });
                try parameters.append(token);
            },
            else => panic("\ninvalid token kind, {}\n", .{kind}),
        }
    }
    return Parameters.init(parameters.slice());
}

fn parseFunctionBody(codebase: *ECS, tokens: *Tokens) !Body {
    var body = List(Entity, .{}).init(&codebase.arena.allocator);
    if (tokens.peek().?.get(TokenKind) == .indent) {
        const spaces = tokens.next().?.get(Indent).spaces;
        while (true) {
            try body.append(try parseExpression(codebase, tokens, LOWEST));
            if (tokens.peek()) |token| {
                if (token.get(TokenKind) != .indent or token.get(Indent).spaces != spaces)
                    break;
                _ = tokens.next();
            } else break;
        }
    } else try body.append(try parseExpression(codebase, tokens, LOWEST));
    return Body.init(body.slice());
}

fn parseFunction(codebase: *ECS, tokens: *Tokens) !Entity {
    const name = Name.init(try tokens.next().?.set(.{Kind.symbol}));
    const begin = name.entity.get(Span).begin;
    const parameters = try parseFunctionParameters(codebase, tokens);
    const return_type = ReturnType.init(try parseExpression(codebase, tokens, HIGHEST));
    _ = tokens.consume(.equal);
    const body = try parseFunctionBody(codebase, tokens);
    const end = body.entities[body.entities.len - 1].get(Span).end;
    const span = components.Span.init(begin, end);
    return try codebase.createEntity(.{
        Kind.function,
        name,
        parameters,
        return_type,
        body,
        span,
    });
}

test "parse function with int literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const code = "start() u64 = 0";
    var tokens = try tokenize(&codebase, code);
    const function = try parseFunction(&codebase, &tokens);
    try expectEqual(function.get(Kind), .function);
    try expectEqualStrings(literalOf(function.get(Name).entity), "start");
    try expectEqual(function.get(Span), Span.init(Position.init(0, 0), Position.init(15, 0)));
    try expectEqual(function.get(Parameters).entities.len, 0);
    const return_type = function.get(ReturnType).entity;
    try expectEqual(return_type.get(Kind), .symbol);
    try expectEqualStrings(literalOf(return_type), "u64");
    try expectEqual(return_type.get(Span), Span.init(Position.init(8, 0), Position.init(11, 0)));
    const body = function.get(Body).entities;
    try expectEqual(body.len, 1);
    const zero = body[0];
    try expectEqual(zero.get(Kind), .int);
    try expectEqualStrings(literalOf(zero), "0");
    try expectEqual(zero.get(Span), Span.init(Position.init(14, 0), Position.init(15, 0)));
}

test "parse function with binary entity" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const code = "start() u64 = 5 + x";
    var tokens = try tokenize(&codebase, code);
    const function = try parseFunction(&codebase, &tokens);
    try expectEqualStrings(literalOf(function.get(Name).entity), "start");
    try expectEqual(function.get(Parameters).entities.len, 0);
    try expectEqualStrings(literalOf(function.get(ReturnType).entity), "u64");
    const body = function.get(Body).entities;
    try expectEqual(body.len, 1);
    const add = body[0];
    try expectEqual(add.get(BinaryOp), .add);
    const arguments = add.get(Arguments).entities;
    try expectEqual(arguments.len, 2);
    try expectEqualStrings(literalOf(arguments[0]), "5");
    try expectEqualStrings(literalOf(arguments[1]), "x");
}

test "parse function with compound binary entity" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const code = "line() u64 = m * x + b";
    var tokens = try tokenize(&codebase, code);
    const function = try parseFunction(&codebase, &tokens);
    try expectEqualStrings(literalOf(function.get(Name).entity), "line");
    try expectEqual(function.get(Parameters).entities.len, 0);
    const body = function.get(Body).entities;
    const add = body[0];
    try expectEqual(add.get(BinaryOp), .add);
    const add_arguments = add.get(Arguments).entities;
    try expectEqual(add_arguments.len, 2);
    const multiply = add_arguments[0];
    try expectEqual(multiply.get(BinaryOp), .multiply);
    const multiply_arguments = multiply.get(Arguments).entities;
    try expectEqual(multiply_arguments.len, 2);
    const m = multiply_arguments[0];
    try expectEqual(m.get(Kind), .symbol);
    try expectEqualStrings(literalOf(m), "m");
    const x = multiply_arguments[1];
    try expectEqual(x.get(Kind), .symbol);
    try expectEqualStrings(literalOf(x), "x");
    const b = add_arguments[1];
    try expectEqual(b.get(Kind), .symbol);
    try expectEqualStrings(literalOf(b), "b");
}

test "parse function parameters" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const code = "add(x: u64, y: u64) u64 = x + y";
    var tokens = try tokenize(&codebase, code);
    const function = try parseFunction(&codebase, &tokens);
    try expectEqualStrings(literalOf(function.get(Name).entity), "add");
    const parameters = function.get(Parameters).entities;
    try expectEqual(parameters.len, 2);
    const param0 = parameters[0];
    try expectEqualStrings(literalOf(param0), "x");
    try expectEqualStrings(literalOf(param0.get(Type).entity), "u64");
    const param1 = parameters[1];
    try expectEqualStrings(literalOf(param1), "y");
    try expectEqualStrings(literalOf(param1.get(Type).entity), "u64");
    try expectEqualStrings(literalOf(function.get(ReturnType).entity), "u64");
    const body = function.get(Body).entities;
    try expectEqual(body.len, 1);
    const add = body[0];
    try expectEqual(add.get(BinaryOp), .add);
    const arguments = add.get(Arguments).entities;
    try expectEqualStrings(literalOf(arguments[0]), "x");
    try expectEqualStrings(literalOf(arguments[1]), "y");
}

test "parse function with newline" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const code =
        \\add(x: u64, y: u64) u64 =
        \\  x + y
    ;
    var tokens = try tokenize(&codebase, code);
    const function = try parseFunction(&codebase, &tokens);
    try expectEqualStrings(literalOf(function.get(Name).entity), "add");
    const parameters = function.get(Parameters).entities;
    try expectEqual(parameters.len, 2);
    const param0 = parameters[0];
    try expectEqualStrings(literalOf(param0), "x");
    try expectEqualStrings(literalOf(param0.get(Type).entity), "u64");
    const param1 = parameters[1];
    try expectEqualStrings(literalOf(param1), "y");
    try expectEqualStrings(literalOf(param1.get(Type).entity), "u64");
    const body = function.get(Body).entities;
    try expectEqual(body.len, 1);
    const add = body[0];
    try expectEqual(add.get(BinaryOp), .add);
    const arguments = add.get(Arguments).entities;
    try expectEqualStrings(literalOf(arguments[0]), "x");
    try expectEqualStrings(literalOf(arguments[1]), "y");
}

test "parse constant definition" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const code =
        \\f() u64 =
        \\  x = 5
        \\  y = 15
        \\  x + y
    ;
    var tokens = try tokenize(&codebase, code);
    const function = try parseFunction(&codebase, &tokens);
    try expectEqualStrings(literalOf(function.get(Name).entity), "f");
    try expectEqualStrings(literalOf(function.get(ReturnType).entity), "u64");
    try expectEqual(function.get(Parameters).entities.len, 0);
    const body = function.get(Body).entities;
    try expectEqual(body.len, 3);
    const x = body[0];
    try expectEqual(x.get(Kind), .define);
    try expectEqualStrings(literalOf(x.get(Name).entity), "x");
    try expectEqualStrings(literalOf(x.get(Value).entity), "5");
    const y = body[1];
    try expectEqual(y.get(Kind), .define);
    try expectEqualStrings(literalOf(y.get(Name).entity), "y");
    try expectEqualStrings(literalOf(y.get(Value).entity), "15");
    const add = body[2];
    try expectEqual(add.get(BinaryOp), .add);
    const arguments = add.get(Arguments).entities;
    try expectEqual(arguments.len, 2);
    try expectEqualStrings(literalOf(arguments[0]), "x");
    try expectEqualStrings(literalOf(arguments[1]), "y");
}

test "parse constant definition with binary op" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const code =
        \\sum_of_squares(x: u64, y: u64) u64 =
        \\  x2 = x * x
        \\  y2 = y * y
        \\  x2 + y2
    ;
    var tokens = try tokenize(&codebase, code);
    const function = try parseFunction(&codebase, &tokens);
    try expectEqualStrings(literalOf(function.get(Name).entity), "sum_of_squares");
    try expectEqualStrings(literalOf(function.get(ReturnType).entity), "u64");
    const parameters = function.get(Parameters).entities;
    try expectEqual(parameters.len, 2);
    const param0 = parameters[0];
    try expectEqualStrings(literalOf(param0), "x");
    try expectEqualStrings(literalOf(param0.get(Type).entity), "u64");
    const param1 = parameters[1];
    try expectEqualStrings(literalOf(param1), "y");
    try expectEqualStrings(literalOf(param1.get(Type).entity), "u64");
    const body = function.get(Body).entities;
    try expectEqual(body.len, 3);
    {
        const x2 = body[0];
        try expectEqualStrings(literalOf(x2.get(Name).entity), "x2");
        const multiply = x2.get(Value).entity;
        try expectEqual(multiply.get(BinaryOp), .multiply);
        const arguments = multiply.get(Arguments).entities;
        try expectEqualStrings(literalOf(arguments[0]), "x");
        try expectEqualStrings(literalOf(arguments[1]), "x");
    }
    {
        const y2 = body[1];
        try expectEqualStrings(literalOf(y2.get(Name).entity), "y2");
        const multiply = y2.get(Value).entity;
        try expectEqual(multiply.get(BinaryOp), .multiply);
        const arguments = multiply.get(Arguments).entities;
        try expectEqualStrings(literalOf(arguments[0]), "y");
        try expectEqualStrings(literalOf(arguments[1]), "y");
    }
    const add = body[2];
    try expectEqual(add.get(BinaryOp), .add);
    const arguments = add.get(Arguments).entities;
    try expectEqualStrings(literalOf(arguments[0]), "x2");
    try expectEqualStrings(literalOf(arguments[1]), "y2");
}

test "parse function call" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const code =
        \\sum_of_squares(x: u64, y: u64) u64 =
        \\  square(x) + square(y)
    ;
    var tokens = try tokenize(&codebase, code);
    const function = try parseFunction(&codebase, &tokens);
    try expectEqualStrings(literalOf(function.get(Name).entity), "sum_of_squares");
    try expectEqualStrings(literalOf(function.get(ReturnType).entity), "u64");
    const parameters = function.get(Parameters).entities;
    try expectEqual(parameters.len, 2);
    const param0 = parameters[0];
    try expectEqualStrings(literalOf(param0), "x");
    try expectEqualStrings(literalOf(param0.get(Type).entity), "u64");
    const param1 = parameters[1];
    try expectEqualStrings(literalOf(param1), "y");
    try expectEqualStrings(literalOf(param1.get(Type).entity), "u64");
    const body = function.get(Body).entities;
    try expectEqual(body.len, 1);
    const add = body[0];
    try expectEqual(add.get(BinaryOp), .add);
    const add_arguments = add.get(Arguments).entities;
    {
        const call = add_arguments[0];
        try expectEqual(call.get(Kind), .call);
        try expectEqualStrings(literalOf(call.get(Callable).entity), "square");
        const arguments = call.get(Arguments).entities;
        try expectEqual(arguments.len, 1);
        try expectEqualStrings(literalOf(arguments[0]), "x");
    }
    {
        const call = add_arguments[1];
        try expectEqual(call.get(Kind), .call);
        try expectEqualStrings(literalOf(call.get(Callable).entity), "square");
        const arguments = call.get(Arguments).entities;
        try expectEqual(arguments.len, 1);
        try expectEqualStrings(literalOf(arguments[0]), "y");
    }
}

test "parse function call with multiple arguments" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const code =
        \\start() u64 =
        \\  sum_of_squares(10, 56 * 3)
    ;
    var tokens = try tokenize(&codebase, code);
    const function = try parseFunction(&codebase, &tokens);
    try expectEqualStrings(literalOf(function.get(Name).entity), "start");
    try expectEqualStrings(literalOf(function.get(ReturnType).entity), "u64");
    try expectEqual(function.get(Parameters).entities.len, 0);
    const body = function.get(Body).entities;
    try expectEqual(body.len, 1);
    const call = body[0];
    try expectEqualStrings(literalOf(call.get(Callable).entity), "sum_of_squares");
    const call_arguments = call.get(Arguments).entities;
    try expectEqual(call_arguments.len, 2);
    try expectEqualStrings(literalOf(call_arguments[0]), "10");
    const multiply = call_arguments[1];
    try expectEqual(multiply.get(BinaryOp), .multiply);
    const arguments = multiply.get(Arguments).entities;
    try expectEqualStrings(literalOf(arguments[0]), "56");
    try expectEqualStrings(literalOf(arguments[1]), "3");
}

fn parseUnqualifiedImports(codebase: *ECS, tokens: *Tokens) !Unqualified {
    var unqualified = List(Entity, .{}).init(&codebase.arena.allocator);
    while (true) {
        try unqualified.append(tokens.consume(.symbol));
        if (tokens.peek()) |token| {
            const kind = token.get(TokenKind);
            switch (kind) {
                .comma => _ = tokens.next(),
                .indent => break,
                else => panic("\nexpected comma, found {}\n", .{kind}),
            }
        } else break;
    }
    return Unqualified.init(unqualified.slice());
}

fn parseImport(codebase: *ECS, tokens: *Tokens) !Entity {
    const import = tokens.consume(.import);
    const begin = import.get(Span).begin;
    const name = Name.init(try tokens.next().?.set(.{Kind.symbol}));
    if (tokens.peek()) |token| {
        const kind = token.get(TokenKind);
        switch (kind) {
            .colon => {
                _ = tokens.next();
                const unqualified = try parseUnqualifiedImports(codebase, tokens);
                const end = unqualified.entities[unqualified.entities.len - 1].get(Span).end;
                return try codebase.createEntity(.{
                    Kind.import,
                    name,
                    Span.init(begin, end),
                    unqualified,
                });
            },
            .indent => {
                const end = name.entity.get(Span).end;
                return try codebase.createEntity(.{
                    Kind.import,
                    name,
                    Span.init(begin, end),
                    Unqualified.init(&.{}),
                });
            },
            else => panic("\nexpected colon got {}\n", .{kind}),
        }
    } else {
        const end = name.entity.get(Span).end;
        return try codebase.createEntity(.{
            Kind.import,
            name,
            Span.init(begin, end),
            Unqualified.init(&.{}),
        });
    }
}

test "parse import module" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const code = "import foo";
    var tokens = try tokenize(&codebase, code);
    const import = try parseImport(&codebase, &tokens);
    try expectEqualStrings(literalOf(import.get(Name).entity), "foo");
}

test "parse import unqualified" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const code = "import foo: bar, baz";
    var tokens = try tokenize(&codebase, code);
    const import = try parseImport(&codebase, &tokens);
    try expectEqualStrings(literalOf(import.get(Name).entity), "foo");
    const unqualified = import.get(Unqualified).entities;
    try expectEqual(unqualified.len, 2);
    try expectEqualStrings(literalOf(unqualified[0]), "bar");
    try expectEqualStrings(literalOf(unqualified[1]), "baz");
}

pub fn parse(codebase: *ECS, tokens: *Tokens) !Entity {
    var top_level = std.AutoHashMap(InternedString, Entity).init(&codebase.arena.allocator);
    while (tokens.peek()) |token| {
        const kind = token.get(TokenKind);
        switch (kind) {
            .symbol => {
                const function = try parseFunction(codebase, tokens);
                const name = function.get(Name).entity.get(Literal).interned;
                if (top_level.get(name)) |overload_set| {
                    try overload_set.getPtr(Overloads).entities.append(function);
                } else {
                    var overloads = Overloads.init(&codebase.arena.allocator);
                    try overloads.entities.append(function);
                    const overload_set = try codebase.createEntity(.{
                        Kind.overload_set,
                        overloads,
                    });
                    try top_level.putNoClobber(name, overload_set);
                }
            },
            .indent => _ = tokens.next(),
            .import => {
                const import = try parseImport(codebase, tokens);
                const name = import.get(Name).entity.get(Literal).interned;
                try top_level.putNoClobber(name, import);
            },
            else => panic("\ncannot parse top level expression {}\n", .{kind}),
        }
    }
    return try codebase.createEntity(.{
        TopLevel.init(top_level, codebase.getPtr(Strings)),
    });
}

test "parse two functions" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const code =
        \\sum_of_squares(x: u64, y: u64) u64 =
        \\  x*2 + y*2
        \\
        \\start() u64 =
        \\  sum_of_squares(10, 56 * 3)
    ;
    var tokens = try tokenize(&codebase, code);
    const module = try parse(&codebase, &tokens);
    {
        const sum_of_squares = module.get(TopLevel).literal("sum_of_squares");
        const overloads = sum_of_squares.get(Overloads).entities.slice();
        try expectEqual(overloads.len, 1);
        try expectEqual(overloads[0].get(Parameters).entities.len, 2);
    }
    {
        const start = module.get(TopLevel).literal("start");
        const overloads = start.get(Overloads).entities.slice();
        try expectEqual(overloads.len, 1);
        try expectEqual(overloads[0].get(Parameters).entities.len, 0);
    }
}

test "parse overload" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const code =
        \\f(x: u64) u64 = x
        \\
        \\f(x: f64) f64 = x
    ;
    var tokens = try tokenize(&codebase, code);
    const module = try parse(&codebase, &tokens);
    const f = module.get(TopLevel).literal("f");
    const overloads = f.get(Overloads).entities.slice();
    try expectEqual(overloads.len, 2);
    {
        const f_u64 = overloads[0];
        const parameters = f_u64.get(Parameters).entities;
        try expectEqual(parameters.len, 1);
        const x = parameters[0];
        try expectEqualStrings(literalOf(x), "x");
        try expectEqualStrings(literalOf(x.get(Type).entity), "u64");
        try expectEqualStrings(literalOf(f_u64.get(ReturnType).entity), "u64");
    }
    {
        const f_f64 = overloads[1];
        const parameters = f_f64.get(Parameters).entities;
        try expectEqual(parameters.len, 1);
        const x = parameters[0];
        try expectEqualStrings(literalOf(x), "x");
        try expectEqualStrings(literalOf(x.get(Type).entity), "f64");
        try expectEqualStrings(literalOf(f_f64.get(ReturnType).entity), "f64");
    }
}

test "parse unqualified import and function" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const code =
        \\import math: sum_of_squares
        \\
        \\start() u64 =
        \\  sum_of_squares(10, 56 * 3)
    ;
    var tokens = try tokenize(&codebase, code);
    const module = try parse(&codebase, &tokens);
    const top_level = module.get(TopLevel);
    const math = top_level.literal("math");
    const unqualified = math.get(Unqualified).entities;
    try expectEqual(unqualified.len, 1);
    try expectEqualStrings(literalOf(unqualified[0]), "sum_of_squares");
    const start = top_level.literal("start");
    const overloads = start.get(Overloads).entities.slice();
    try expectEqual(overloads.len, 1);
    try expectEqual(overloads[0].get(Parameters).entities.len, 0);
}

test "parse import and function" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const code =
        \\import math
        \\
        \\start() u64 =
        \\  math.sum_of_squares(10, 56 * 3)
    ;
    var tokens = try tokenize(&codebase, code);
    const module = try parse(&codebase, &tokens);
    const top_level = module.get(TopLevel);
    const math = top_level.literal("math");
    try expectEqual(math.get(Unqualified).entities.len, 0);
    const start = top_level.literal("start");
    const overloads = start.get(Overloads).entities.slice();
    const body = overloads[0].get(Body).entities;
    try expectEqual(body.len, 1);
    const dot = body[0];
    try expectEqual(dot.get(Kind), .binary_op);
    const dot_arguments = dot.get(Arguments).entities;
    try expectEqualStrings(literalOf(dot_arguments[0]), "math");
    const sum_of_squares = dot_arguments[1];
    const callable = sum_of_squares.get(Callable).entity;
    try expectEqualStrings(literalOf(callable), "sum_of_squares");
    const sum_of_squares_arguments = sum_of_squares.get(Arguments).entities;
    try expectEqualStrings(literalOf(sum_of_squares_arguments[0]), "10");
    const multiply = sum_of_squares_arguments[1];
    try expectEqual(multiply.get(BinaryOp), .multiply);
    const arguments = multiply.get(Arguments).entities;
    try expectEqualStrings(literalOf(arguments[0]), "56");
    try expectEqualStrings(literalOf(arguments[1]), "3");
}
