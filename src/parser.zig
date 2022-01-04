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
const tokenizer = @import("tokenizer.zig");
const Tokens = tokenizer.Tokens;
const tokenize = tokenizer.tokenize;
const literalOf = @import("test_utils.zig").literalOf;

fn parseExpression(codebase: *ECS, tokens: *Tokens, precedence: u64) error{OutOfMemory}!Entity {
    const token = tokens.next().?;
    var left = try prefixParser(tokens, token);
    while (true) {
        if (InfixParser.init(tokens, left)) |parser| {
            const parser_precedence = parser.precedence();
            if (precedence <= parser_precedence) {
                left = try parser.run(codebase, tokens, left, parser_precedence);
            } else return left;
        } else return left;
    }
}

fn parseGrouping(codebase: *ECS, tokens: *Tokens) !Entity {
    const expression = try parseExpression(codebase, tokens, LOWEST);
    _ = tokens.consume(.right_paren);
    return expression;
}

fn parseIf(codebase: *ECS, tokens: *Tokens, if_: Entity) !Entity {
    const allocator = codebase.arena.allocator();
    const begin = if_.get(components.Span).begin;
    const conditional = components.Conditional.init(try parseExpression(codebase, tokens, LOWEST));
    _ = tokens.consume(.then);
    var then = components.Then.init(allocator);
    while (true) {
        if (tokens.peek()) |token| {
            switch (token.get(components.TokenKind)) {
                .new_line => _ = tokens.next(),
                .else_ => {
                    _ = tokens.next();
                    break;
                },
                else => try then.append(try parseExpression(codebase, tokens, LOWEST)),
            }
        } else break;
    }
    var else_ = components.Else.init(allocator);
    const result = try codebase.createEntity(.{
        components.AstKind.if_,
        conditional,
        then,
    });
    while (true) {
        if (tokens.peek()) |token| {
            switch (token.get(components.TokenKind)) {
                .new_line => _ = tokens.next(),
                .end => {
                    const end = tokens.next().?.get(components.Span).end;
                    _ = try result.set(.{
                        else_,
                        components.Span.init(begin, end),
                    });
                    break;
                },
                else => try else_.append(try parseExpression(codebase, tokens, LOWEST)),
            }
        } else break;
    }
    return result;
}

fn parseWhile(codebase: *ECS, tokens: *Tokens, while_: Entity) !Entity {
    const begin = while_.get(components.Span).begin;
    const conditional = components.Conditional.init(try parseExpression(codebase, tokens, LOWEST));
    _ = tokens.consume(.then);
    var body = components.Body.init(codebase.arena.allocator());
    const result = try codebase.createEntity(.{
        components.AstKind.while_,
        conditional,
    });
    while (true) {
        if (tokens.peek()) |token| {
            switch (token.get(components.TokenKind)) {
                .new_line => _ = tokens.next(),
                .end => {
                    const end = tokens.next().?.get(components.Span).end;
                    _ = try result.set(.{
                        body,
                        components.Span.init(begin, end),
                    });
                    break;
                },
                else => try body.append(try parseExpression(codebase, tokens, LOWEST)),
            }
        } else break;
    }
    return result;
}

fn parsePointer(codebase: *ECS, tokens: *Tokens, star: Entity) !Entity {
    const begin = star.get(components.Span).begin;
    const value = try parseExpression(codebase, tokens, HIGHEST);
    const end = value.get(components.Span).end;
    const span = components.Span.init(begin, end);
    return try codebase.createEntity(.{
        components.AstKind.pointer,
        components.Value.init(value),
        span,
    });
}

fn prefixParser(tokens: *Tokens, token: Entity) !Entity {
    const kind = token.get(components.TokenKind);
    return try switch (kind) {
        .symbol => token.set(.{components.AstKind.symbol}),
        .int => token.set(.{
            components.AstKind.int,
            components.Type.init(token.ecs.get(components.Builtins).IntLiteral),
        }),
        .float => token.set(.{
            components.AstKind.float,
            components.Type.init(token.ecs.get(components.Builtins).FloatLiteral),
        }),
        .left_paren => parseGrouping(token.ecs, tokens),
        .if_ => parseIf(token.ecs, tokens, token),
        .while_ => parseWhile(token.ecs, tokens, token),
        .underscore => token.set(.{components.AstKind.underscore}),
        .times => parsePointer(token.ecs, tokens, token),
        else => panic("\nno prefix parser for = {}\n", .{kind}),
    };
}

const NEXT_PRECEDENCE: u64 = 10;
const LOWEST: u64 = 0;
const DEFINE: u64 = LOWEST;
const ASSIGN: u64 = DEFINE;
const PIPELINE: u64 = DEFINE + NEXT_PRECEDENCE;
const LESS_THAN: u64 = PIPELINE + NEXT_PRECEDENCE;
const LESS_EQUAL: u64 = LESS_THAN;
const GREATER_THAN: u64 = LESS_THAN;
const GREATER_EQUAL: u64 = LESS_THAN;
const EQUAL: u64 = LESS_THAN;
const NOT_EQUAL: u64 = LESS_THAN;
const BIT_OR: u64 = LESS_THAN + NEXT_PRECEDENCE;
const BIT_XOR: u64 = BIT_OR + NEXT_PRECEDENCE;
const BIT_AND: u64 = BIT_XOR + NEXT_PRECEDENCE;
const LEFT_SHIFT: u64 = BIT_AND + NEXT_PRECEDENCE;
const RIGHT_SHIFT: u64 = LEFT_SHIFT;
const ADD: u64 = LEFT_SHIFT + NEXT_PRECEDENCE;
const SUBTRACT: u64 = ADD;
const MULTIPLY: u64 = ADD + NEXT_PRECEDENCE;
const DIVIDE: u64 = MULTIPLY;
const REMAINDER: u64 = MULTIPLY;
const DOT: u64 = MULTIPLY + NEXT_PRECEDENCE;
const CALL: u64 = DOT + NEXT_PRECEDENCE;
const HIGHEST: u64 = CALL;

const InfixParser = union(enum) {
    binary_op: struct { op: components.BinaryOp, precedence: u64 },
    define_type_infer,
    define,
    call,
    assign,

    fn init(tokens: *Tokens, left: Entity) ?InfixParser {
        if (tokens.peek()) |token| {
            const kind = token.get(components.TokenKind);
            switch (kind) {
                .plus => return InfixParser{ .binary_op = .{ .op = .add, .precedence = ADD } },
                .minus => return InfixParser{ .binary_op = .{ .op = .subtract, .precedence = SUBTRACT } },
                .times => return InfixParser{ .binary_op = .{ .op = .multiply, .precedence = MULTIPLY } },
                .slash => return InfixParser{ .binary_op = .{ .op = .divide, .precedence = DIVIDE } },
                .percent => return InfixParser{ .binary_op = .{ .op = .remainder, .precedence = REMAINDER } },
                .dot => return InfixParser{ .binary_op = .{ .op = .dot, .precedence = DOT } },
                .less_than => return InfixParser{ .binary_op = .{ .op = .less_than, .precedence = LESS_THAN } },
                .less_equal => return InfixParser{ .binary_op = .{ .op = .less_equal, .precedence = LESS_EQUAL } },
                .less_less => return InfixParser{ .binary_op = .{ .op = .left_shift, .precedence = LEFT_SHIFT } },
                .greater_than => return InfixParser{ .binary_op = .{ .op = .greater_than, .precedence = GREATER_THAN } },
                .greater_equal => return InfixParser{ .binary_op = .{ .op = .greater_equal, .precedence = GREATER_EQUAL } },
                .greater_greater => return InfixParser{ .binary_op = .{ .op = .right_shift, .precedence = RIGHT_SHIFT } },
                .equal_equal => return InfixParser{ .binary_op = .{ .op = .equal, .precedence = EQUAL } },
                .bang_equal => return InfixParser{ .binary_op = .{ .op = .not_equal, .precedence = NOT_EQUAL } },
                .bar => return InfixParser{ .binary_op = .{ .op = .bit_or, .precedence = BIT_OR } },
                .bar_greater => return InfixParser{ .binary_op = .{ .op = .pipeline, .precedence = PIPELINE } },
                .caret => return InfixParser{ .binary_op = .{ .op = .bit_xor, .precedence = BIT_XOR } },
                .ampersand => return InfixParser{ .binary_op = .{ .op = .bit_and, .precedence = BIT_AND } },
                .equal => return InfixParser.define_type_infer,
                .colon => return InfixParser.define,
                .left_paren => {
                    const left_end = left.get(components.Span).end;
                    const paren_begin = token.get(components.Span).begin;
                    if (left_end.row != paren_begin.row or left_end.column != paren_begin.column)
                        return null;
                    return InfixParser.call;
                },
                .colon_equal => return InfixParser.assign,
                else => return null,
            }
        } else {
            return null;
        }
    }

    fn precedence(self: InfixParser) u64 {
        return switch (self) {
            .binary_op => |binary_op| binary_op.precedence,
            .define_type_infer => DEFINE,
            .define => DEFINE,
            .assign => ASSIGN,
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
            .define_type_infer => parseDefineTypeInfer(codebase, tokens, left, parser_precedence),
            .define => parseDefine(codebase, tokens, left, parser_precedence),
            .assign => parseAssign(codebase, tokens, left, parser_precedence),
            .call => parseCall(codebase, tokens, left),
        };
    }
};

fn parseBinaryOp(codebase: *ECS, tokens: *Tokens, left: Entity, op: components.BinaryOp, precedence: u64) !Entity {
    const right = try parseExpression(codebase, tokens, precedence + 1);
    const arguments = try components.Arguments.fromSlice(codebase.arena.allocator(), &.{ left, right });
    return try codebase.createEntity(.{
        components.AstKind.binary_op,
        op,
        components.Span.init(left.get(components.Span).begin, right.get(components.Span).end),
        arguments,
    });
}

fn parseDefineTypeInfer(codebase: *ECS, tokens: *Tokens, name: Entity, precedence: u64) !Entity {
    assert(name.get(components.AstKind) == .symbol);
    const value = try parseExpression(codebase, tokens, precedence);
    return try codebase.createEntity(.{
        components.AstKind.define,
        components.Name.init(name),
        components.Value.init(value),
        components.Span.init(name.get(components.Span).begin, value.get(components.Span).end),
    });
}

fn parseDefine(codebase: *ECS, tokens: *Tokens, name: Entity, precedence: u64) !Entity {
    assert(name.get(components.AstKind) == .symbol);
    const type_ast = try parseExpression(codebase, tokens, DEFINE + NEXT_PRECEDENCE);
    _ = tokens.consume(components.TokenKind.equal);
    const value = try parseExpression(codebase, tokens, precedence);
    return try codebase.createEntity(.{
        components.AstKind.define,
        components.Name.init(name),
        components.TypeAst.init(type_ast),
        components.Value.init(value),
        components.Span.init(name.get(components.Span).begin, value.get(components.Span).end),
    });
}

fn parseAssign(codebase: *ECS, tokens: *Tokens, name: Entity, precedence: u64) !Entity {
    assert(name.get(components.AstKind) == .symbol);
    const value = try parseExpression(codebase, tokens, precedence);
    return try codebase.createEntity(.{
        components.AstKind.assign,
        components.Name.init(name),
        components.Value.init(value),
        components.Span.init(name.get(components.Span).begin, value.get(components.Span).end),
    });
}

fn parseCall(codebase: *ECS, tokens: *Tokens, callable: Entity) !Entity {
    var arguments = components.Arguments.init(codebase.arena.allocator());
    while (tokens.peek()) |token| {
        switch (token.get(components.TokenKind)) {
            .right_paren => break,
            .comma => _ = tokens.next(),
            else => try arguments.append(try parseExpression(codebase, tokens, LOWEST)),
        }
    }
    return try codebase.createEntity(.{
        components.AstKind.call,
        components.Callable.init(callable),
        arguments,
        components.Span.init(callable.get(components.Span).begin, tokens.next().?.get(components.Span).end),
    });
}

test "parse symbol" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code = "foo";
    var tokens = try tokenize(module, code);
    const entity = try parseExpression(codebase, &tokens, LOWEST);
    try expectEqual(entity.get(components.AstKind), .symbol);
    try expectEqualStrings(literalOf(entity), "foo");
    try expectEqual(entity.get(components.Span), .{
        .begin = .{ .column = 0, .row = 0 },
        .end = .{ .column = 3, .row = 0 },
    });
}

test "parse int" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code = "35";
    var tokens = try tokenize(module, code);
    const entity = try parseExpression(codebase, &tokens, LOWEST);
    try expectEqual(entity.get(components.AstKind), .int);
    try expectEqualStrings(literalOf(entity), "35");
    try expectEqual(entity.get(components.Span), .{
        .begin = .{ .column = 0, .row = 0 },
        .end = .{ .column = 2, .row = 0 },
    });
}

test "parse float" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code = "35.3";
    var tokens = try tokenize(module, code);
    const entity = try parseExpression(codebase, &tokens, LOWEST);
    try expectEqual(entity.get(components.AstKind), .float);
    try expectEqualStrings(literalOf(entity), "35.3");
    try expectEqual(entity.get(components.Span), .{
        .begin = .{ .column = 0, .row = 0 },
        .end = .{ .column = 4, .row = 0 },
    });
}

fn parseFunctionParameters(codebase: *ECS, tokens: *Tokens) !components.Parameters {
    var parameters = components.Parameters.init(codebase.arena.allocator());
    _ = tokens.consume(.left_paren);
    while (tokens.next()) |token| {
        const kind = token.get(components.TokenKind);
        switch (kind) {
            .right_paren => break,
            .comma => continue,
            .symbol => {
                _ = tokens.consume(.colon);
                _ = try token.set(.{
                    components.TypeAst.init(try parseExpression(codebase, tokens, LOWEST)),
                });
                try parameters.append(token);
            },
            else => panic("\ninvalid token kind, {}\n", .{kind}),
        }
    }
    return parameters;
}

fn parseFunctionBody(codebase: *ECS, tokens: *Tokens) !components.Body {
    var body = components.Body.init(codebase.arena.allocator());
    while (true) {
        if (tokens.peek()) |token| {
            switch (token.get(components.TokenKind)) {
                .end => break,
                .new_line => _ = tokens.next(),
                else => try body.append(try parseExpression(codebase, tokens, LOWEST)),
            }
        } else break;
    }
    return body;
}

fn parseFunction(codebase: *ECS, tokens: *Tokens) !Entity {
    const begin = tokens.consume(.fn_).get(components.Span).begin;
    const parameters = try parseFunctionParameters(codebase, tokens);
    _ = tokens.consume(.colon);
    const return_type = components.ReturnTypeAst.init(try parseExpression(codebase, tokens, HIGHEST));
    const body = try parseFunctionBody(codebase, tokens);
    const end = tokens.consume(.end).get(components.Span).end;
    const span = components.Span.init(begin, end);
    return try codebase.createEntity(.{
        components.AstKind.function,
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
    const module = try codebase.createEntity(.{});
    const code = "fn(): u64 0 end";
    var tokens = try tokenize(module, code);
    const function = try parseFunction(codebase, &tokens);
    try expectEqual(function.get(components.AstKind), .function);
    try expectEqual(function.get(components.Span), .{
        .begin = .{ .row = 0, .column = 0 },
        .end = .{ .row = 0, .column = 15 },
    });
    try expectEqual(function.get(components.Parameters).slice().len, 0);
    const return_type = function.get(components.ReturnTypeAst).entity;
    try expectEqual(return_type.get(components.AstKind), .symbol);
    try expectEqualStrings(literalOf(return_type), "u64");
    try expectEqual(return_type.get(components.Span), .{
        .begin = .{ .row = 0, .column = 6 },
        .end = .{ .row = 0, .column = 9 },
    });
    const body = function.get(components.Body).slice();
    try expectEqual(body.len, 1);
    const zero = body[0];
    try expectEqual(zero.get(components.AstKind), .int);
    try expectEqualStrings(literalOf(zero), "0");
    try expectEqual(zero.get(components.Span), .{
        .begin = .{ .row = 0, .column = 10 },
        .end = .{ .row = 0, .column = 11 },
    });
}

test "parse function with binary entity" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code = "fn(): u64 5 + x end";
    var tokens = try tokenize(module, code);
    const function = try parseFunction(codebase, &tokens);
    try expectEqual(function.get(components.Parameters).slice().len, 0);
    try expectEqualStrings(literalOf(function.get(components.ReturnTypeAst).entity), "u64");
    const body = function.get(components.Body).slice();
    try expectEqual(body.len, 1);
    const add = body[0];
    try expectEqual(add.get(components.BinaryOp), .add);
    const arguments = add.get(components.Arguments).slice();
    try expectEqual(arguments.len, 2);
    try expectEqualStrings(literalOf(arguments[0]), "5");
    try expectEqualStrings(literalOf(arguments[1]), "x");
}

test "parse function with compound binary entity" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code = "fn(): u64 m * x + b end";
    var tokens = try tokenize(module, code);
    const function = try parseFunction(codebase, &tokens);
    try expectEqual(function.get(components.Parameters).slice().len, 0);
    const body = function.get(components.Body).slice();
    const add = body[0];
    try expectEqual(add.get(components.BinaryOp), .add);
    const add_arguments = add.get(components.Arguments).slice();
    try expectEqual(add_arguments.len, 2);
    const multiply = add_arguments[0];
    try expectEqual(multiply.get(components.BinaryOp), .multiply);
    const multiply_arguments = multiply.get(components.Arguments).slice();
    try expectEqual(multiply_arguments.len, 2);
    const m = multiply_arguments[0];
    try expectEqual(m.get(components.AstKind), .symbol);
    try expectEqualStrings(literalOf(m), "m");
    const x = multiply_arguments[1];
    try expectEqual(x.get(components.AstKind), .symbol);
    try expectEqualStrings(literalOf(x), "x");
    const b = add_arguments[1];
    try expectEqual(b.get(components.AstKind), .symbol);
    try expectEqualStrings(literalOf(b), "b");
}

test "parse function parameters" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code = "fn(x: u64, y: u64): u64 x + y end";
    var tokens = try tokenize(module, code);
    const function = try parseFunction(codebase, &tokens);
    const parameters = function.get(components.Parameters).slice();
    try expectEqual(parameters.len, 2);
    const param0 = parameters[0];
    try expectEqualStrings(literalOf(param0), "x");
    try expectEqualStrings(literalOf(param0.get(components.TypeAst).entity), "u64");
    const param1 = parameters[1];
    try expectEqualStrings(literalOf(param1), "y");
    try expectEqualStrings(literalOf(param1.get(components.TypeAst).entity), "u64");
    try expectEqualStrings(literalOf(function.get(components.ReturnTypeAst).entity), "u64");
    const body = function.get(components.Body).slice();
    try expectEqual(body.len, 1);
    const add = body[0];
    try expectEqual(add.get(components.BinaryOp), .add);
    const arguments = add.get(components.Arguments).slice();
    try expectEqualStrings(literalOf(arguments[0]), "x");
    try expectEqualStrings(literalOf(arguments[1]), "y");
}

test "parse function with newline" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\fn(x: u64, y: u64): u64
        \\  x + y
        \\end
    ;
    var tokens = try tokenize(module, code);
    const function = try parseFunction(codebase, &tokens);
    const parameters = function.get(components.Parameters).slice();
    try expectEqual(parameters.len, 2);
    const param0 = parameters[0];
    try expectEqualStrings(literalOf(param0), "x");
    try expectEqualStrings(literalOf(param0.get(components.TypeAst).entity), "u64");
    const param1 = parameters[1];
    try expectEqualStrings(literalOf(param1), "y");
    try expectEqualStrings(literalOf(param1.get(components.TypeAst).entity), "u64");
    const body = function.get(components.Body).slice();
    try expectEqual(body.len, 1);
    const add = body[0];
    try expectEqual(add.get(components.BinaryOp), .add);
    const arguments = add.get(components.Arguments).slice();
    try expectEqualStrings(literalOf(arguments[0]), "x");
    try expectEqualStrings(literalOf(arguments[1]), "y");
}

test "parse constant definition" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\fn(): u64
        \\  x = 5
        \\  y = 15
        \\  x + y
        \\end
    ;
    var tokens = try tokenize(module, code);
    const function = try parseFunction(codebase, &tokens);
    try expectEqualStrings(literalOf(function.get(components.ReturnTypeAst).entity), "u64");
    try expectEqual(function.get(components.Parameters).slice().len, 0);
    const body = function.get(components.Body).slice();
    try expectEqual(body.len, 3);
    const x = body[0];
    try expectEqual(x.get(components.AstKind), .define);
    try expectEqualStrings(literalOf(x.get(components.Name).entity), "x");
    try expectEqualStrings(literalOf(x.get(components.Value).entity), "5");
    const y = body[1];
    try expectEqual(y.get(components.AstKind), .define);
    try expectEqualStrings(literalOf(y.get(components.Name).entity), "y");
    try expectEqualStrings(literalOf(y.get(components.Value).entity), "15");
    const add = body[2];
    try expectEqual(add.get(components.BinaryOp), .add);
    const arguments = add.get(components.Arguments).slice();
    try expectEqual(arguments.len, 2);
    try expectEqualStrings(literalOf(arguments[0]), "x");
    try expectEqualStrings(literalOf(arguments[1]), "y");
}

test "parse constant definition with binary op" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\fn(x: u64, y: u64): u64
        \\  x2 = x * x
        \\  y2 = y * y
        \\  x2 + y2
        \\end
    ;
    var tokens = try tokenize(module, code);
    const function = try parseFunction(codebase, &tokens);
    try expectEqualStrings(literalOf(function.get(components.ReturnTypeAst).entity), "u64");
    const parameters = function.get(components.Parameters).slice();
    try expectEqual(parameters.len, 2);
    const param0 = parameters[0];
    try expectEqualStrings(literalOf(param0), "x");
    try expectEqualStrings(literalOf(param0.get(components.TypeAst).entity), "u64");
    const param1 = parameters[1];
    try expectEqualStrings(literalOf(param1), "y");
    try expectEqualStrings(literalOf(param1.get(components.TypeAst).entity), "u64");
    const body = function.get(components.Body).slice();
    try expectEqual(body.len, 3);
    {
        const x2 = body[0];
        try expectEqualStrings(literalOf(x2.get(components.Name).entity), "x2");
        const multiply = x2.get(components.Value).entity;
        try expectEqual(multiply.get(components.BinaryOp), .multiply);
        const arguments = multiply.get(components.Arguments).slice();
        try expectEqualStrings(literalOf(arguments[0]), "x");
        try expectEqualStrings(literalOf(arguments[1]), "x");
    }
    {
        const y2 = body[1];
        try expectEqualStrings(literalOf(y2.get(components.Name).entity), "y2");
        const multiply = y2.get(components.Value).entity;
        try expectEqual(multiply.get(components.BinaryOp), .multiply);
        const arguments = multiply.get(components.Arguments).slice();
        try expectEqualStrings(literalOf(arguments[0]), "y");
        try expectEqualStrings(literalOf(arguments[1]), "y");
    }
    const add = body[2];
    try expectEqual(add.get(components.BinaryOp), .add);
    const arguments = add.get(components.Arguments).slice();
    try expectEqualStrings(literalOf(arguments[0]), "x2");
    try expectEqualStrings(literalOf(arguments[1]), "y2");
}

test "parse function call" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\fn(x: u64, y: u64): u64
        \\  square(x) + square(y)
        \\end
    ;
    var tokens = try tokenize(module, code);
    const function = try parseFunction(codebase, &tokens);
    try expectEqualStrings(literalOf(function.get(components.ReturnTypeAst).entity), "u64");
    const parameters = function.get(components.Parameters).slice();
    try expectEqual(parameters.len, 2);
    const param0 = parameters[0];
    try expectEqualStrings(literalOf(param0), "x");
    try expectEqualStrings(literalOf(param0.get(components.TypeAst).entity), "u64");
    const param1 = parameters[1];
    try expectEqualStrings(literalOf(param1), "y");
    try expectEqualStrings(literalOf(param1.get(components.TypeAst).entity), "u64");
    const body = function.get(components.Body).slice();
    try expectEqual(body.len, 1);
    const add = body[0];
    try expectEqual(add.get(components.BinaryOp), .add);
    const add_arguments = add.get(components.Arguments).slice();
    {
        const call = add_arguments[0];
        try expectEqual(call.get(components.AstKind), .call);
        try expectEqualStrings(literalOf(call.get(components.Callable).entity), "square");
        const arguments = call.get(components.Arguments).slice();
        try expectEqual(arguments.len, 1);
        try expectEqualStrings(literalOf(arguments[0]), "x");
    }
    {
        const call = add_arguments[1];
        try expectEqual(call.get(components.AstKind), .call);
        try expectEqualStrings(literalOf(call.get(components.Callable).entity), "square");
        const arguments = call.get(components.Arguments).slice();
        try expectEqual(arguments.len, 1);
        try expectEqualStrings(literalOf(arguments[0]), "y");
    }
}

test "parse function call with multiple arguments" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\fn(): u64
        \\  sum_of_squares(10, 56 * 3)
        \\end
    ;
    var tokens = try tokenize(module, code);
    const function = try parseFunction(codebase, &tokens);
    try expectEqualStrings(literalOf(function.get(components.ReturnTypeAst).entity), "u64");
    try expectEqual(function.get(components.Parameters).slice().len, 0);
    const body = function.get(components.Body).slice();
    try expectEqual(body.len, 1);
    const call = body[0];
    try expectEqualStrings(literalOf(call.get(components.Callable).entity), "sum_of_squares");
    const call_arguments = call.get(components.Arguments).slice();
    try expectEqual(call_arguments.len, 2);
    try expectEqualStrings(literalOf(call_arguments[0]), "10");
    const multiply = call_arguments[1];
    try expectEqual(multiply.get(components.BinaryOp), .multiply);
    const arguments = multiply.get(components.Arguments).slice();
    try expectEqualStrings(literalOf(arguments[0]), "56");
    try expectEqualStrings(literalOf(arguments[1]), "3");
}

fn parseImport(codebase: *ECS, tokens: *Tokens) !Entity {
    const begin = tokens.consume(.import).get(components.Span).begin;
    _ = tokens.consume(.left_paren);
    const path = components.Path.init(tokens.consume(.string));
    const end = tokens.consume(.right_paren).get(components.Span).end;
    const span = components.Span.init(begin, end);
    return try codebase.createEntity(.{
        components.AstKind.import,
        path,
        span,
    });
}

test "parse import module" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\import("foo.yeti")
    ;
    var tokens = try tokenize(module, code);
    const import = try parseImport(codebase, &tokens);
    try expectEqualStrings(literalOf(import.get(components.Path).entity), "foo.yeti");
}

fn parseForeignImport(codebase: *ECS, tokens: *Tokens) !Entity {
    const begin = tokens.consume(.foreign_import).get(components.Span).begin;
    _ = tokens.consume(.left_paren);
    const foreign_module = components.ForeignModule.init(tokens.consume(.string));
    _ = tokens.consume(.comma);
    const foreign_name = components.ForeignName.init(tokens.consume(.string));
    _ = tokens.consume(.comma);
    _ = tokens.consume(.symbol);
    const parameters = try parseFunctionParameters(codebase, tokens);
    _ = tokens.consume(.colon);
    const return_type = components.ReturnTypeAst.init(try parseExpression(codebase, tokens, HIGHEST));
    const end = tokens.consume(.right_paren).get(components.Span).end;
    const span = components.Span.init(begin, end);
    return try codebase.createEntity(.{
        components.AstKind.function,
        foreign_module,
        foreign_name,
        parameters,
        return_type,
        span,
    });
}

fn overloadFunction(top_level: *components.TopLevel, function: Entity, name: components.Name) !void {
    const codebase = function.ecs;
    _ = try function.set(.{name});
    if (top_level.hasName(name)) |overload_set| {
        try overload_set.getPtr(components.Overloads).append(function);
    } else {
        var overloads = components.Overloads.init(codebase.arena.allocator());
        try overloads.append(function);
        const overload_set = try codebase.createEntity(.{
            components.AstKind.overload_set,
            overloads,
        });
        try top_level.putName(name, overload_set);
    }
}

fn parseTopLevel(tokens: *Tokens, top_level: *components.TopLevel, token: Entity) !void {
    const name = components.Name.init(token);
    _ = tokens.consume(.equal);
    const kind = tokens.peek().?.get(components.TokenKind);
    switch (kind) {
        .fn_ => {
            const function = try parseFunction(token.ecs, tokens);
            try overloadFunction(top_level, function, name);
        },
        .import => {
            const import = try parseImport(token.ecs, tokens);
            _ = try import.set(.{name});
            try top_level.putName(name, import);
        },
        .foreign_import => {
            const function = try parseForeignImport(token.ecs, tokens);
            try overloadFunction(top_level, function, name);
        },
        else => panic("\ncannot parse top level expression {}\n", .{kind}),
    }
}

fn parseForeignExport(tokens: *Tokens, foreign_exports: *components.ForeignExports) !void {
    _ = tokens.consume(.left_paren);
    const foreign_export = tokens.consume(.symbol);
    _ = tokens.consume(.right_paren);
    try foreign_exports.append(foreign_export);
}

pub fn parse(module: Entity, tokens: *Tokens) !void {
    const codebase = module.ecs;
    const allocator = codebase.arena.allocator();
    var top_level = components.TopLevel.init(allocator, codebase.getPtr(Strings));
    var foreign_exports = components.ForeignExports.init(allocator);
    while (tokens.next()) |token| {
        const kind = token.get(components.TokenKind);
        switch (kind) {
            .symbol => try parseTopLevel(tokens, &top_level, token),
            .foreign_export => try parseForeignExport(tokens, &foreign_exports),
            .new_line => continue,
            else => panic("\nparse unsupported kind {}\n", .{kind}),
        }
    }
    _ = try module.set(.{
        top_level,
        foreign_exports,
        components.Type.init(codebase.get(components.Builtins).Module),
    });
}

test "parse two functions" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\sum_of_squares = fn(x: u64, y: u64): u64
        \\  x*2 + y*2
        \\end
        \\
        \\start = fn(): u64
        \\  sum_of_squares(10, 56 * 3)
        \\end
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    {
        const sum_of_squares = module.get(components.TopLevel).findString("sum_of_squares");
        const overloads = sum_of_squares.get(components.Overloads).slice();
        try expectEqual(overloads.len, 1);
        try expectEqual(overloads[0].get(components.Parameters).slice().len, 2);
    }
    {
        const start = module.get(components.TopLevel).findString("start");
        const overloads = start.get(components.Overloads).slice();
        try expectEqual(overloads.len, 1);
        try expectEqual(overloads[0].get(components.Parameters).slice().len, 0);
    }
}

test "parse overload" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\id = fn(x: u64): u64 x end
        \\
        \\id = fn(x: f64): f64 x end
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const id = module.get(components.TopLevel).findString("id");
    const overloads = id.get(components.Overloads).slice();
    try expectEqual(overloads.len, 2);
    {
        const id_u64 = overloads[0];
        const parameters = id_u64.get(components.Parameters).slice();
        try expectEqual(parameters.len, 1);
        const x = parameters[0];
        try expectEqualStrings(literalOf(x), "x");
        try expectEqualStrings(literalOf(x.get(components.TypeAst).entity), "u64");
        try expectEqualStrings(literalOf(id_u64.get(components.ReturnTypeAst).entity), "u64");
    }
    {
        const id_f64 = overloads[1];
        const parameters = id_f64.get(components.Parameters).slice();
        try expectEqual(parameters.len, 1);
        const x = parameters[0];
        try expectEqualStrings(literalOf(x), "x");
        try expectEqualStrings(literalOf(x.get(components.TypeAst).entity), "f64");
        try expectEqualStrings(literalOf(id_f64.get(components.ReturnTypeAst).entity), "f64");
    }
}

test "parse import and function" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\math = import("math.yeti")
        \\
        \\start = fn(): u64
        \\  math.sum_of_squares(10, 56 * 3)
        \\end
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

test "parse define int literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\start = fn(): u64
        \\  x = 10
        \\  x
        \\end
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start");
    const overloads = start.get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const body = overloads[0].get(components.Body).slice();
    try expectEqual(body.len, 2);
    const define = body[0];
    try expectEqual(define.get(components.AstKind), .define);
    try expectEqualStrings(literalOf(define.get(components.Name).entity), "x");
    try expectEqualStrings(literalOf(define.get(components.Value).entity), "10");
    const x = body[1];
    try expectEqual(x.get(components.AstKind), .symbol);
    try expectEqualStrings(literalOf(x), "x");
}

test "parse define with explicit type" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\start = fn(): u64
        \\  x: u64 = 10
        \\  x
        \\end
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start");
    const overloads = start.get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const body = overloads[0].get(components.Body).slice();
    try expectEqual(body.len, 2);
    const define = body[0];
    try expectEqual(define.get(components.AstKind), .define);
    try expectEqualStrings(literalOf(define.get(components.Name).entity), "x");
    try expectEqualStrings(literalOf(define.get(components.Value).entity), "10");
    try expectEqualStrings(literalOf(define.get(components.TypeAst).entity), "u64");
    const x = body[1];
    try expectEqual(x.get(components.AstKind), .symbol);
    try expectEqualStrings(literalOf(x), "x");
}

test "parse grouping with parenthesis" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\start = fn(): u64
        \\  (5 + 10) * 3
        \\end
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start");
    const overloads = start.get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const body = overloads[0].get(components.Body).slice();
    try expectEqual(body.len, 1);
    const multiply = body[0];
    try expectEqual(multiply.get(components.AstKind), .binary_op);
    try expectEqual(multiply.get(components.BinaryOp), .multiply);
    const multiply_arguments = multiply.get(components.Arguments).slice();
    const add = multiply_arguments[0];
    try expectEqual(add.get(components.AstKind), .binary_op);
    try expectEqual(add.get(components.BinaryOp), .add);
    const add_arguments = add.get(components.Arguments).slice();
    try expectEqualStrings(literalOf(add_arguments[0]), "5");
    try expectEqualStrings(literalOf(add_arguments[1]), "10");
    try expectEqualStrings(literalOf(multiply_arguments[1]), "3");
}

test "parse if then else" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\start = fn(): u64
        \\  if 10 > 5 then 20 else 30 end
        \\end
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start");
    const overloads = start.get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const body = overloads[0].get(components.Body).slice();
    try expectEqual(body.len, 1);
    const if_ = body[0];
    try expectEqual(if_.get(components.AstKind), .if_);
    const conditional = if_.get(components.Conditional).entity;
    try expectEqual(conditional.get(components.AstKind), .binary_op);
    try expectEqual(conditional.get(components.BinaryOp), .greater_than);
    const then = if_.get(components.Then).slice();
    try expectEqual(then.len, 1);
    try expectEqualStrings(literalOf(then[0]), "20");
    const else_ = if_.get(components.Else).slice();
    try expectEqual(else_.len, 1);
    try expectEqualStrings(literalOf(else_[0]), "30");
}

test "parse multiline if then else" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\start = fn(): u64
        \\  if 10 > 5 then
        \\    x = 20
        \\    x
        \\  else
        \\    y = 30
        \\    y
        \\  end
        \\end
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start");
    const overloads = start.get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const body = overloads[0].get(components.Body).slice();
    try expectEqual(body.len, 1);
    const if_ = body[0];
    try expectEqual(if_.get(components.AstKind), .if_);
    const conditional = if_.get(components.Conditional).entity;
    try expectEqual(conditional.get(components.AstKind), .binary_op);
    try expectEqual(conditional.get(components.BinaryOp), .greater_than);
    const then = if_.get(components.Then).slice();
    try expectEqual(then.len, 2);
    {
        const define = then[0];
        try expectEqual(define.get(components.AstKind), .define);
        try expectEqualStrings(literalOf(define.get(components.Name).entity), "x");
        try expectEqualStrings(literalOf(define.get(components.Value).entity), "20");
        const x = then[1];
        try expectEqual(x.get(components.AstKind), .symbol);
        try expectEqualStrings(literalOf(x), "x");
    }
    const else_ = if_.get(components.Else).slice();
    try expectEqual(else_.len, 2);
    {
        const define = else_[0];
        try expectEqual(define.get(components.AstKind), .define);
        try expectEqualStrings(literalOf(define.get(components.Name).entity), "y");
        try expectEqualStrings(literalOf(define.get(components.Value).entity), "30");
        const y = else_[1];
        try expectEqual(y.get(components.AstKind), .symbol);
        try expectEqualStrings(literalOf(y), "y");
    }
}

test "parse assignment" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\start = fn(): u64
        \\  x: u64 = 10
        \\  x := 3
        \\  x
        \\end
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start");
    const overloads = start.get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const body = overloads[0].get(components.Body).slice();
    try expectEqual(body.len, 3);
    const define = body[0];
    try expectEqual(define.get(components.AstKind), .define);
    try expectEqualStrings(literalOf(define.get(components.Name).entity), "x");
    try expectEqualStrings(literalOf(define.get(components.Value).entity), "10");
    try expectEqualStrings(literalOf(define.get(components.TypeAst).entity), "u64");
    const assign = body[1];
    try expectEqual(assign.get(components.AstKind), .assign);
    try expectEqualStrings(literalOf(assign.get(components.Name).entity), "x");
    try expectEqualStrings(literalOf(assign.get(components.Value).entity), "3");
    const x = body[2];
    try expectEqual(x.get(components.AstKind), .symbol);
    try expectEqualStrings(literalOf(x), "x");
}

test "parse while" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\start = fn(): i32
        \\  i = 0
        \\  while i < 10 then
        \\      i := i + 1
        \\  end
        \\  i
        \\end
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start");
    const overloads = start.get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const body = overloads[0].get(components.Body).slice();
    try expectEqual(body.len, 3);
    const define = body[0];
    try expectEqual(define.get(components.AstKind), .define);
    try expectEqualStrings(literalOf(define.get(components.Name).entity), "i");
    try expectEqualStrings(literalOf(define.get(components.Value).entity), "0");
    const while_ = body[1];
    try expectEqual(while_.get(components.AstKind), .while_);
    const conditional = while_.get(components.Conditional).entity;
    try expectEqual(conditional.get(components.AstKind), .binary_op);
    try expectEqual(conditional.get(components.BinaryOp), .less_than);
    const while_body = while_.get(components.Body).slice();
    try expectEqual(while_body.len, 1);
    const assign = while_body[0];
    try expectEqual(assign.get(components.AstKind), .assign);
    try expectEqualStrings(literalOf(assign.get(components.Name).entity), "i");
    const value = assign.get(components.Value).entity;
    try expectEqual(value.get(components.AstKind), .binary_op);
    try expectEqual(value.get(components.BinaryOp), .add);
    const i = body[2];
    try expectEqual(i.get(components.AstKind), .symbol);
    try expectEqualStrings(literalOf(i), "i");
}

test "parse pipeline" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\start = fn(): i32
        \\  5 |> square()
        \\end
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start");
    const overloads = start.get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const body = overloads[0].get(components.Body).slice();
    try expectEqual(body.len, 1);
    const pipeline = body[0];
    try expectEqual(pipeline.get(components.AstKind), .binary_op);
    try expectEqual(pipeline.get(components.BinaryOp), .pipeline);
    const pipeline_arguments = pipeline.get(components.Arguments).slice();
    try expectEqual(pipeline_arguments.len, 2);
    const five = pipeline_arguments[0];
    try expectEqualStrings(literalOf(five), "5");
    const square = pipeline_arguments[1];
    try expectEqual(square.get(components.AstKind), .call);
    try expectEqualStrings(literalOf(square.get(components.Callable).entity), "square");
    const square_arguments = square.get(components.Arguments).slice();
    try expectEqual(square_arguments.len, 0);
}

test "parse foreign export" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code = "foreign_export(start)";
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const foreign_exports = module.get(components.ForeignExports).slice();
    try expectEqual(foreign_exports.len, 1);
    try expectEqualStrings(literalOf(foreign_exports[0]), "start");
}

test "parse foreign import" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\log = foreign_import("console", "log", Function(value: i64): void)
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const log = top_level.findString("log");
    const overloads = log.get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const function = overloads[0];
    try expectEqual(function.get(components.AstKind), .function);
    try expectEqualStrings(literalOf(function.get(components.ForeignModule).entity), "console");
    try expectEqualStrings(literalOf(function.get(components.ForeignName).entity), "log");
    const parameters = function.get(components.Parameters).slice();
    try expectEqual(parameters.len, 1);
    const parameter = parameters[0];
    try expectEqualStrings(literalOf(parameter), "value");
    try expectEqualStrings(literalOf(parameter.get(components.TypeAst).entity), "i64");
    try expectEqualStrings(literalOf(function.get(components.ReturnTypeAst).entity), "void");
}

test "parse pointer" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\start = fn(ptr: *i32): i32
        \\  0
        \\end
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start");
    const overloads = start.get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const overload = overloads[0];
    const parameters = overload.get(components.Parameters).slice();
    try expectEqual(parameters.len, 1);
    const ptr = parameters[0];
    try expectEqualStrings(literalOf(ptr), "ptr");
    const type_of = ptr.get(components.TypeAst).entity;
    try expectEqual(type_of.get(components.AstKind), .pointer);
    try expectEqualStrings(literalOf(type_of.get(components.Value).entity), "i32");
    const body = overload.get(components.Body).slice();
    try expectEqual(body.len, 1);
    const zero = body[0];
    try expectEqual(zero.get(components.AstKind), .int);
    try expectEqualStrings(literalOf(zero), "0");
}

test "parse pointer load" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\start = fn(ptr: *i32): i32
        \\  *ptr
        \\end
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start");
    const overloads = start.get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const overload = overloads[0];
    const parameters = overload.get(components.Parameters).slice();
    try expectEqual(parameters.len, 1);
    const ptr = parameters[0];
    try expectEqualStrings(literalOf(ptr), "ptr");
    const type_of = ptr.get(components.TypeAst).entity;
    try expectEqual(type_of.get(components.AstKind), .pointer);
    try expectEqualStrings(literalOf(type_of.get(components.Value).entity), "i32");
    const body = overload.get(components.Body).slice();
    try expectEqual(body.len, 1);
    const load = body[0];
    try expectEqual(load.get(components.AstKind), .pointer);
    const value = load.get(components.Value).entity;
    try expectEqual(value.get(components.AstKind), .symbol);
    try expectEqualStrings(literalOf(value), "ptr");
}

// test "parse pointer load after new line" {
//     var arena = Arena.init(std.heap.page_allocator);
//     defer arena.deinit();
//     var codebase = try initCodebase(&arena);
//     const module = try codebase.createEntity(.{});
//     const code =
//         \\start = fn(): i32
//         \\  ptr = cast(*i32, 0)
//         \\  *ptr
//         \\end
//     ;
//     var tokens = try tokenize(module, code);
//     try parse(module, &tokens);
//     const top_level = module.get(components.TopLevel);
//     const start = top_level.findString("start");
//     const overloads = start.get(components.Overloads).slice();
//     try expectEqual(overloads.len, 1);
//     const overload = overloads[0];
//     const parameters = overload.get(components.Parameters).slice();
//     try expectEqual(parameters.len, 0);
//     const body = overload.get(components.Body).slice();
//     try expectEqual(body.len, 2);
//     const load = body[0];
//     try expectEqual(load.get(components.AstKind), .pointer);
//     const value = load.get(components.Value).entity;
//     try expectEqual(value.get(components.AstKind), .symbol);
//     try expectEqualStrings(literalOf(value), "ptr");
// }
