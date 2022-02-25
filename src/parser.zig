const std = @import("std");
const Arena = std.heap.ArenaAllocator;
const assert = std.debug.assert;
const panic = std.debug.panic;

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
const literalOf = @import("query.zig").literalOf;

pub fn parseExpression(codebase: *ECS, tokens: *Tokens, precedence: u64) error{OutOfMemory}!Entity {
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

fn parseArray(codebase: *ECS, tokens: *Tokens, left_bracket: Entity) !Entity {
    _ = tokens.consume(.right_bracket);
    const begin = left_bracket.get(components.Span).begin;
    const value = try parseExpression(codebase, tokens, HIGHEST);
    const end = value.get(components.Span).end;
    const span = components.Span.init(begin, end);
    return try codebase.createEntity(.{
        components.AstKind.array,
        components.Value.init(value),
        span,
    });
}

fn parseIf(codebase: *ECS, tokens: *Tokens, if_: Entity) !Entity {
    const conditional = components.Conditional.init(try parseExpression(codebase, tokens, LOWEST));
    assert(tokens.next().?.get(components.TokenKind) == .left_brace);
    const allocator = codebase.arena.allocator();
    const begin = if_.get(components.Span).begin;
    var then = components.Then.init(allocator);
    while (true) {
        if (tokens.peek()) |token| {
            switch (token.get(components.TokenKind)) {
                .new_line => _ = tokens.next(),
                .right_brace => {
                    _ = tokens.next();
                    break;
                },
                else => try then.append(try parseExpression(codebase, tokens, LOWEST)),
            }
        } else break;
    }
    _ = tokens.consume(.else_);
    _ = tokens.consume(.left_brace);
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
                .right_brace => {
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
    const conditional = components.Conditional.init(try parseExpression(codebase, tokens, LOWEST));
    assert(tokens.next().?.get(components.TokenKind) == .left_brace);
    const begin = while_.get(components.Span).begin;
    var body = components.Body.init(codebase.arena.allocator());
    const result = try codebase.createEntity(.{
        components.AstKind.while_,
        conditional,
    });
    while (true) {
        if (tokens.peek()) |token| {
            switch (token.get(components.TokenKind)) {
                .new_line => _ = tokens.next(),
                .right_brace => {
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

fn parseFor(codebase: *ECS, tokens: *Tokens, for_: Entity) !Entity {
    const loop_variable = tokens.consume(.symbol);
    _ = tokens.consume(.in);
    const iterator = try parseExpression(codebase, tokens, LOWEST);
    assert(iterator.get(components.AstKind) == .range);
    assert(tokens.next().?.get(components.TokenKind) == .left_brace);
    const begin = for_.get(components.Span).begin;
    var body = components.Body.init(codebase.arena.allocator());
    const result = try codebase.createEntity(.{
        components.AstKind.for_,
        components.LoopVariable.init(loop_variable),
        components.Iterator.init(iterator),
    });
    while (true) {
        if (tokens.peek()) |token| {
            switch (token.get(components.TokenKind)) {
                .new_line => _ = tokens.next(),
                .right_brace => {
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
    const value = try parseExpression(codebase, tokens, DOT);
    const end = value.get(components.Span).end;
    const span = components.Span.init(begin, end);
    return try codebase.createEntity(.{
        components.AstKind.pointer,
        components.Value.init(value),
        span,
    });
}

fn parseRange(codebase: *ECS, tokens: *Tokens, colon: Entity) !Entity {
    const last = try parseExpression(codebase, tokens, LOWEST);
    assert(last.get(components.AstKind) == .int);
    const range = components.Range{ .first = null, .last = last };
    const begin = colon.get(components.Span).begin;
    const end = last.get(components.Span).end;
    return try codebase.createEntity(.{
        components.AstKind.range,
        components.Span.init(begin, end),
        range,
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
        .string => token.set(.{components.AstKind.string}),
        .char => token.set(.{components.AstKind.char}),
        .left_paren => parseGrouping(token.ecs, tokens),
        .left_bracket => parseArray(token.ecs, tokens, token),
        .if_ => parseIf(token.ecs, tokens, token),
        .while_ => parseWhile(token.ecs, tokens, token),
        .for_ => parseFor(token.ecs, tokens, token),
        .underscore => token.set(.{components.AstKind.underscore}),
        .times => parsePointer(token.ecs, tokens, token),
        .colon => parseRange(token.ecs, tokens, token),
        else => panic("\nno prefix parser for {}\n", .{kind}),
    };
}

const NEXT_PRECEDENCE: u64 = 10;
pub const LOWEST: u64 = 0;
const DEFINE: u64 = LOWEST;
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
const INDEX: u64 = CALL;
const HIGHEST: u64 = CALL;

const InfixParser = union(enum) {
    binary_op: struct { op: components.BinaryOp, precedence: u64 },
    define_type_infer,
    define_or_range,
    call,
    plus_equal,
    times_equal,
    index,

    fn init(tokens: *Tokens, left: Entity) ?InfixParser {
        if (tokens.peek()) |token| {
            const kind = token.get(components.TokenKind);
            switch (kind) {
                .plus => return InfixParser{ .binary_op = .{ .op = .add, .precedence = ADD } },
                .plus_equal => return InfixParser.plus_equal,
                .times_equal => return InfixParser.times_equal,
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
                .caret => return InfixParser{ .binary_op = .{ .op = .bit_xor, .precedence = BIT_XOR } },
                .ampersand => return InfixParser{ .binary_op = .{ .op = .bit_and, .precedence = BIT_AND } },
                .equal => return InfixParser.define_type_infer,
                .colon => return InfixParser.define_or_range,
                .left_paren => {
                    const left_end = left.get(components.Span).end;
                    const paren_begin = token.get(components.Span).begin;
                    if (left_end.row != paren_begin.row or left_end.column != paren_begin.column)
                        return null;
                    return InfixParser.call;
                },
                .left_bracket => return InfixParser.index,
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
            .define_or_range => DEFINE,
            .plus_equal => DEFINE,
            .times_equal => DEFINE,
            .call => CALL,
            .index => INDEX,
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
            .define_or_range => parseDefineOrRange(codebase, tokens, left, parser_precedence),
            .call => parseCall(codebase, tokens, left),
            .plus_equal => parsePlusEqual(codebase, tokens, left, parser_precedence),
            .times_equal => parseTimesEqual(codebase, tokens, left, parser_precedence),
            .index => parseIndex(codebase, tokens, left),
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

fn parsePlusEqual(codebase: *ECS, tokens: *Tokens, left: Entity, precedence: u64) !Entity {
    const right = try parseExpression(codebase, tokens, precedence + 1);
    const arguments = try components.Arguments.fromSlice(codebase.arena.allocator(), &.{ left, right });
    return try codebase.createEntity(.{
        components.AstKind.plus_equal,
        components.Span.init(left.get(components.Span).begin, right.get(components.Span).end),
        arguments,
    });
}

fn parseTimesEqual(codebase: *ECS, tokens: *Tokens, left: Entity, precedence: u64) !Entity {
    const right = try parseExpression(codebase, tokens, precedence + 1);
    const arguments = try components.Arguments.fromSlice(codebase.arena.allocator(), &.{ left, right });
    return try codebase.createEntity(.{
        components.AstKind.times_equal,
        components.Span.init(left.get(components.Span).begin, right.get(components.Span).end),
        arguments,
    });
}

fn parseDefineTypeInfer(codebase: *ECS, tokens: *Tokens, name: Entity, precedence: u64) !Entity {
    const value = try parseExpression(codebase, tokens, precedence);
    return try codebase.createEntity(.{
        components.AstKind.define,
        components.Name.init(name),
        components.Value.init(value),
        components.Span.init(name.get(components.Span).begin, value.get(components.Span).end),
    });
}

fn parseDefineOrRange(codebase: *ECS, tokens: *Tokens, lhs: Entity, precedence: u64) !Entity {
    const kind = lhs.get(components.AstKind);
    switch (kind) {
        .symbol => {
            const type_ast = try parseExpression(codebase, tokens, DEFINE + NEXT_PRECEDENCE);
            _ = tokens.consume(.equal);
            const value = try parseExpression(codebase, tokens, precedence);
            return try codebase.createEntity(.{
                components.AstKind.define,
                components.Name.init(lhs),
                components.TypeAst.init(type_ast),
                components.Value.init(value),
                components.Span.init(lhs.get(components.Span).begin, value.get(components.Span).end),
            });
        },
        .int => {
            const last = try parseExpression(codebase, tokens, LOWEST);
            assert(last.get(components.AstKind) == .int);
            const range = components.Range{ .first = lhs, .last = last };
            return try codebase.createEntity(.{
                components.AstKind.range,
                components.Span.init(lhs.get(components.Span).begin, last.get(components.Span).end),
                range,
            });
        },
        else => panic("\nparsing define or range got kind {}\n", .{kind}),
    }
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

fn parseIndex(codebase: *ECS, tokens: *Tokens, array: Entity) !Entity {
    const index = try parseExpression(codebase, tokens, LOWEST);
    const end = tokens.consume(.right_bracket).get(components.Span).end;
    const arguments = try components.Arguments.fromSlice(codebase.arena.allocator(), &.{ array, index });
    return try codebase.createEntity(.{
        components.AstKind.index,
        arguments,
        components.Span.init(array.get(components.Span).begin, end),
    });
}

fn parseFunctionParameters(codebase: *ECS, tokens: *Tokens) !components.Parameters {
    var parameters = components.Parameters.init(codebase.arena.allocator());
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
                .right_brace => break,
                .new_line => _ = tokens.next(),
                else => try body.append(try parseExpression(codebase, tokens, LOWEST)),
            }
        } else break;
    }
    return body;
}

pub fn parseImport(codebase: *ECS, tokens: *Tokens) !Entity {
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

pub fn parseFunction(codebase: *ECS, tokens: *Tokens, name: Entity) !Entity {
    const function = try codebase.createEntity(.{components.AstKind.function});
    const begin = name.get(components.Span).begin;
    const parameters = try parseFunctionParameters(codebase, tokens);
    switch (tokens.next().?.get(components.TokenKind)) {
        .colon => {
            const return_type = components.ReturnTypeAst.init(try parseExpression(codebase, tokens, HIGHEST));
            _ = try function.set(.{return_type});
            _ = tokens.consume(.left_brace);
        },
        .left_brace => {},
        else => |k| panic("\nparse function invalid token {} \n", .{k}),
    }
    const body = try parseFunctionBody(codebase, tokens);
    const end = tokens.consume(.right_brace).get(components.Span).end;
    const span = components.Span.init(begin, end);
    return try function.set(.{
        parameters,
        body,
        span,
    });
}

fn parseTopLevel(tokens: *Tokens, top_level: *components.TopLevel, token: Entity) !void {
    const name = components.Name.init(token);
    switch (tokens.next().?.get(components.TokenKind)) {
        .equal => {
            switch (tokens.peek().?.get(components.TokenKind)) {
                .import => {
                    const import = try parseImport(token.ecs, tokens);
                    _ = try import.set(.{name});
                    try top_level.putName(name, import);
                },
                else => |k| panic("\ncannot parse top level expression {}\n", .{k}),
            }
        },
        .left_paren => {
            const function = try parseFunction(token.ecs, tokens, token);
            try overloadFunction(top_level, function, name);
        },
        else => |k| panic("\ncannot parse top level expression {}\n", .{k}),
    }
}

fn parseStruct(tokens: *Tokens, top_level: *components.TopLevel, struct_token: Entity) !void {
    const codebase = struct_token.ecs;
    const begin = struct_token.get(components.Span).begin;
    const name = tokens.consume(.symbol);
    _ = tokens.consume(.left_brace);
    var fields = components.Fields.init(codebase.arena.allocator());
    while (tokens.next()) |token| {
        const kind = token.get(components.TokenKind);
        switch (kind) {
            .right_brace => {
                const end = token.get(components.Span).end;
                const span = components.Span.init(begin, end);
                const struct_ = try codebase.createEntity(.{
                    components.AstKind.struct_,
                    fields,
                    span,
                    name.get(components.Literal),
                    components.Type.init(codebase.get(components.Builtins).Type),
                });
                try overloadFunction(top_level, struct_, components.Name.init(name));
                return;
            },
            .new_line => continue,
            .symbol => {
                _ = tokens.consume(.colon);
                _ = try token.set(.{
                    components.TypeAst.init(try parseExpression(codebase, tokens, LOWEST)),
                });
                try fields.append(token);
            },
            else => panic("\ninvalid token kind, {}\n", .{kind}),
        }
    }
    panic("\ncompiler bug in parse struct\n", .{});
}

fn parseAttributeExport(tokens: *Tokens, top_level: *components.TopLevel, foreign_exports: *components.ForeignExports) !void {
    _ = tokens.consume(.new_line);
    const name = tokens.consume(.symbol);
    _ = tokens.consume(.left_paren);
    const function = try parseFunction(name.ecs, tokens, name);
    try overloadFunction(top_level, function, components.Name.init(name));
    try foreign_exports.append(name);
}

fn parseAttributeImport(tokens: *Tokens, top_level: *components.TopLevel) !void {
    const begin = tokens.consume(.left_paren).get(components.Span).begin;
    const foreign_module = components.ForeignModule.init(tokens.consume(.string));
    _ = tokens.consume(.comma);
    const foreign_name = components.ForeignName.init(tokens.consume(.string));
    _ = tokens.consume(.right_paren);
    _ = tokens.consume(.new_line);
    const name = tokens.consume(.symbol);
    _ = tokens.consume(.left_paren);
    const codebase = name.ecs;
    const parameters = try parseFunctionParameters(codebase, tokens);
    _ = tokens.consume(.colon);
    const return_type = components.ReturnTypeAst.init(try parseExpression(codebase, tokens, HIGHEST));
    const end = return_type.entity.get(components.Span).end;
    const span = components.Span.init(begin, end);
    const function = try codebase.createEntity(.{
        components.AstKind.function,
        foreign_module,
        foreign_name,
        parameters,
        return_type,
        span,
    });
    try overloadFunction(top_level, function, components.Name.init(name));
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
            .new_line => continue,
            .struct_ => try parseStruct(tokens, &top_level, token),
            .attribute_export => try parseAttributeExport(tokens, &top_level, &foreign_exports),
            .attribute_import => try parseAttributeImport(tokens, &top_level),
            else => panic("\nparse unsupported kind {}\n", .{kind}),
        }
    }
    _ = try module.set(.{
        top_level,
        foreign_exports,
        components.Type.init(codebase.get(components.Builtins).Module),
    });
}
