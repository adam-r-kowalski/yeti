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
    const kind = token.get(components.TokenKind);
    return try switch (kind) {
        .symbol => token.set(.{components.AstKind.symbol}),
        .int => token.set(.{
            components.AstKind.int,
            components.Type.init(token.ecs.get(components.Builtins).IntLiteral),
        }),
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
    binary_op: struct { op: components.BinaryOp, precedence: u64 },
    define_type_infer,
    define,
    call,

    fn init(tokens: *Tokens) ?InfixParser {
        if (tokens.peek()) |token| {
            const kind = token.get(components.TokenKind);
            return switch (kind) {
                .plus => .{ .binary_op = .{ .op = .add, .precedence = ADD } },
                .times => .{ .binary_op = .{ .op = .multiply, .precedence = MULTIPLY } },
                .dot => .{ .binary_op = .{ .op = .dot, .precedence = DOT } },
                .equal => .define_type_infer,
                .colon => .define,
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
            .define_type_infer => DEFINE,
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
            .define_type_infer => parseDefineTypeInfer(codebase, tokens, left, parser_precedence),
            .define => parseDefine(codebase, tokens, left, parser_precedence),
            .call => parseCall(codebase, tokens, left),
        };
    }
};

fn parseBinaryOp(codebase: *ECS, tokens: *Tokens, left: Entity, op: components.BinaryOp, precedence: u64) !Entity {
    const right = try parseExpression(codebase, tokens, precedence);
    const arguments = try components.Arguments.fromSlice(&codebase.arena.allocator, &.{ left, right });
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

fn parseCall(codebase: *ECS, tokens: *Tokens, callable: Entity) !Entity {
    var arguments = components.Arguments.init(&codebase.arena.allocator);
    while (tokens.peek()) |token| {
        switch (token.get(components.TokenKind)) {
            .right_paren => {
                return try codebase.createEntity(.{
                    components.AstKind.call,
                    components.Callable.init(callable),
                    arguments,
                    components.Span.init(callable.get(components.Span).begin, tokens.next().?.get(components.Span).end),
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

fn parseFunctionParameters(codebase: *ECS, tokens: *Tokens) !components.Parameters {
    var parameters = components.Parameters.init(&codebase.arena.allocator);
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
    var body = components.Body.init(&codebase.arena.allocator);
    while (true) {
        try body.append(try parseExpression(codebase, tokens, LOWEST));
        if (tokens.peek()) |token| {
            if (token.get(components.TokenKind) == .end) {
                _ = tokens.next();
                break;
            }
        } else break;
    }
    return body;
}

fn parseFunction(codebase: *ECS, tokens: *Tokens) !Entity {
    const begin = tokens.consume(.function).get(components.Span).begin;
    const parameters = try parseFunctionParameters(codebase, tokens);
    _ = tokens.consume(.colon);
    const return_type = components.ReturnTypeAst.init(try parseExpression(codebase, tokens, HIGHEST));
    const body = try parseFunctionBody(codebase, tokens);
    const end = body.last().get(components.Span).end;
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
    const code = "function(): U64 0 end";
    var tokens = try tokenize(module, code);
    const function = try parseFunction(codebase, &tokens);
    try expectEqual(function.get(components.AstKind), .function);
    try expectEqual(function.get(components.Span), .{
        .begin = .{ .row = 0, .column = 0 },
        .end = .{ .row = 0, .column = 17 },
    });
    try expectEqual(function.get(components.Parameters).slice().len, 0);
    const return_type = function.get(components.ReturnTypeAst).entity;
    try expectEqual(return_type.get(components.AstKind), .symbol);
    try expectEqualStrings(literalOf(return_type), "U64");
    try expectEqual(return_type.get(components.Span), .{
        .begin = .{ .row = 0, .column = 12 },
        .end = .{ .row = 0, .column = 15 },
    });
    const body = function.get(components.Body).slice();
    try expectEqual(body.len, 1);
    const zero = body[0];
    try expectEqual(zero.get(components.AstKind), .int);
    try expectEqualStrings(literalOf(zero), "0");
    try expectEqual(zero.get(components.Span), .{
        .begin = .{ .row = 0, .column = 16 },
        .end = .{ .row = 0, .column = 17 },
    });
}

test "parse function with binary entity" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code = "function(): U64 5 + x end";
    var tokens = try tokenize(module, code);
    const function = try parseFunction(codebase, &tokens);
    try expectEqual(function.get(components.Parameters).slice().len, 0);
    try expectEqualStrings(literalOf(function.get(components.ReturnTypeAst).entity), "U64");
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
    const code = "function(): U64 m * x + b end";
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
    const code = "function(x: U64, y: U64): U64 x + y end";
    var tokens = try tokenize(module, code);
    const function = try parseFunction(codebase, &tokens);
    const parameters = function.get(components.Parameters).slice();
    try expectEqual(parameters.len, 2);
    const param0 = parameters[0];
    try expectEqualStrings(literalOf(param0), "x");
    try expectEqualStrings(literalOf(param0.get(components.TypeAst).entity), "U64");
    const param1 = parameters[1];
    try expectEqualStrings(literalOf(param1), "y");
    try expectEqualStrings(literalOf(param1.get(components.TypeAst).entity), "U64");
    try expectEqualStrings(literalOf(function.get(components.ReturnTypeAst).entity), "U64");
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
        \\function(x: U64, y: U64): U64
        \\  x + y
        \\end
    ;
    var tokens = try tokenize(module, code);
    const function = try parseFunction(codebase, &tokens);
    const parameters = function.get(components.Parameters).slice();
    try expectEqual(parameters.len, 2);
    const param0 = parameters[0];
    try expectEqualStrings(literalOf(param0), "x");
    try expectEqualStrings(literalOf(param0.get(components.TypeAst).entity), "U64");
    const param1 = parameters[1];
    try expectEqualStrings(literalOf(param1), "y");
    try expectEqualStrings(literalOf(param1.get(components.TypeAst).entity), "U64");
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
        \\function(): U64
        \\  x = 5
        \\  y = 15
        \\  x + y
        \\end
    ;
    var tokens = try tokenize(module, code);
    const function = try parseFunction(codebase, &tokens);
    try expectEqualStrings(literalOf(function.get(components.ReturnTypeAst).entity), "U64");
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
        \\function(x: U64, y: U64): U64
        \\  x2 = x * x
        \\  y2 = y * y
        \\  x2 + y2
        \\end
    ;
    var tokens = try tokenize(module, code);
    const function = try parseFunction(codebase, &tokens);
    try expectEqualStrings(literalOf(function.get(components.ReturnTypeAst).entity), "U64");
    const parameters = function.get(components.Parameters).slice();
    try expectEqual(parameters.len, 2);
    const param0 = parameters[0];
    try expectEqualStrings(literalOf(param0), "x");
    try expectEqualStrings(literalOf(param0.get(components.TypeAst).entity), "U64");
    const param1 = parameters[1];
    try expectEqualStrings(literalOf(param1), "y");
    try expectEqualStrings(literalOf(param1.get(components.TypeAst).entity), "U64");
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
        \\function(x: U64, y: U64): U64
        \\  square(x) + square(y)
        \\end
    ;
    var tokens = try tokenize(module, code);
    const function = try parseFunction(codebase, &tokens);
    try expectEqualStrings(literalOf(function.get(components.ReturnTypeAst).entity), "U64");
    const parameters = function.get(components.Parameters).slice();
    try expectEqual(parameters.len, 2);
    const param0 = parameters[0];
    try expectEqualStrings(literalOf(param0), "x");
    try expectEqualStrings(literalOf(param0.get(components.TypeAst).entity), "U64");
    const param1 = parameters[1];
    try expectEqualStrings(literalOf(param1), "y");
    try expectEqualStrings(literalOf(param1.get(components.TypeAst).entity), "U64");
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
        \\function(): U64
        \\  sum_of_squares(10, 56 * 3)
        \\end
    ;
    var tokens = try tokenize(module, code);
    const function = try parseFunction(codebase, &tokens);
    try expectEqualStrings(literalOf(function.get(components.ReturnTypeAst).entity), "U64");
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

pub fn parse(module: Entity, tokens: *Tokens) !void {
    const codebase = module.ecs;
    var top_level = components.TopLevel.init(&codebase.arena.allocator, codebase.getPtr(Strings));
    while (tokens.next()) |token| {
        const name = components.Name.init(token);
        _ = tokens.consume(.equal);
        const kind = tokens.peek().?.get(components.TokenKind);
        switch (kind) {
            .function => {
                const function = try parseFunction(codebase, tokens);
                _ = try function.set(.{name});
                if (top_level.hasName(name)) |overload_set| {
                    try overload_set.getPtr(components.Overloads).append(function);
                } else {
                    var overloads = components.Overloads.init(&codebase.arena.allocator);
                    try overloads.append(function);
                    const overload_set = try codebase.createEntity(.{
                        components.AstKind.overload_set,
                        overloads,
                    });
                    try top_level.putName(name, overload_set);
                }
            },
            .import => {
                const import = try parseImport(codebase, tokens);
                _ = try import.set(.{name});
                try top_level.putName(name, import);
            },
            else => panic("\ncannot parse top level expression {}\n", .{kind}),
        }
    }
    _ = try module.set(.{
        top_level,
        components.Type.init(codebase.get(components.Builtins).Module),
    });
}

test "parse two functions" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\sum_of_squares = function(x: U64, y: U64): U64
        \\  x*2 + y*2
        \\end
        \\
        \\start = function(): U64
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
        \\id = function(x: U64): U64 x end
        \\
        \\id = function(x: F64): F64 x end
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
        try expectEqualStrings(literalOf(x.get(components.TypeAst).entity), "U64");
        try expectEqualStrings(literalOf(id_u64.get(components.ReturnTypeAst).entity), "U64");
    }
    {
        const id_f64 = overloads[1];
        const parameters = id_f64.get(components.Parameters).slice();
        try expectEqual(parameters.len, 1);
        const x = parameters[0];
        try expectEqualStrings(literalOf(x), "x");
        try expectEqualStrings(literalOf(x.get(components.TypeAst).entity), "F64");
        try expectEqualStrings(literalOf(id_f64.get(components.ReturnTypeAst).entity), "F64");
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
        \\start = function(): U64
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

test "parse assignment" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\start = function(): U64
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

test "parse assignment with explicit type" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\start = function(): U64
        \\  x: U64 = 10
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
    try expectEqualStrings(literalOf(define.get(components.TypeAst).entity), "U64");
    const x = body[1];
    try expectEqual(x.get(components.AstKind), .symbol);
    try expectEqualStrings(literalOf(x), "x");
}
