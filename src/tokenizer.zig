const std = @import("std");
const Arena = std.heap.ArenaAllocator;
const assert = std.debug.assert;
const panic = std.debug.panic;

const initCodebase = @import("init_codebase.zig").initCodebase;
const ecs = @import("ecs.zig");
const Entity = ecs.Entity;
const ECS = ecs.ECS;
const List = @import("list.zig").List;
const Strings = @import("strings.zig").Strings;
const literalOf = @import("test_utils.zig").literalOf;
const components = @import("components.zig");

const Source = struct {
    code: []const u8,
    position: components.Position,

    fn init(code: []const u8) Source {
        return Source{
            .code = code,
            .position = .{
                .column = 0,
                .row = 0,
            },
        };
    }

    fn advance(self: *Source, columns: u64) []const u8 {
        const result = self.code[0..columns];
        self.code = self.code[columns..];
        self.position.column += columns;
        return result;
    }

    fn trimWhitespace(self: *Source) void {
        var i: u64 = 0;
        while (i < self.code.len) : (i += 1) {
            switch (self.code[i]) {
                '\r' => continue,
                ' ' => self.position.column += 1,
                else => break,
            }
        }
        self.code = self.code[i..];
    }
};

pub const Tokens = struct {
    entities: []const Entity,

    pub fn init(entities: []const Entity) Tokens {
        return Tokens{ .entities = entities };
    }

    pub fn next(self: *Tokens) ?Entity {
        if (self.entities.len == 0) return null;
        const entity = self.entities[0];
        self.entities = self.entities[1..];
        return entity;
    }

    pub fn peek(self: Tokens) ?Entity {
        if (self.entities.len == 0) return null;
        return self.entities[0];
    }

    pub fn consume(self: *Tokens, kind: components.TokenKind) Entity {
        const token = self.next().?;
        assert(token.get(components.TokenKind) == kind);
        return token;
    }
};

fn tokenizeNewLine(module: Entity, source: *Source) !Entity {
    const begin = source.position;
    source.position.column = 0;
    source.position.row += 1;
    source.code = source.code[1..];
    const end = source.position;
    const span = components.Span.init(begin, end);
    return try module.ecs.createEntity(.{
        components.TokenKind.new_line,
        span,
    });
}

pub fn tokenize(module: Entity, code: []const u8) !Tokens {
    var entities = List(Entity, .{ .initial_capacity = 1024 }).init(module.ecs.arena.allocator());
    var source = Source.init(code);
    while (true) {
        source.trimWhitespace();
        if (source.code.len == 0) return Tokens.init(entities.slice());
        const token = switch (source.code[0]) {
            '0'...'9', '-' => try tokenizeNumber(module, &source, false),
            '.' => try tokenizeNumber(module, &source, true),
            '"' => try tokenizeString(module, &source),
            '\'' => try tokenizeChar(module, &source),
            '(' => try tokenizeOne(module, &source, .left_paren),
            ')' => try tokenizeOne(module, &source, .right_paren),
            '[' => try tokenizeOne(module, &source, .left_bracket),
            ']' => try tokenizeOne(module, &source, .right_bracket),
            '/' => try tokenizeOne(module, &source, .slash),
            '%' => try tokenizeOne(module, &source, .percent),
            '&' => try tokenizeOne(module, &source, .ampersand),
            '^' => try tokenizeOne(module, &source, .caret),
            ',' => try tokenizeOne(module, &source, .comma),
            ':' => try tokenizeOne(module, &source, .colon),
            '+' => try tokenizeOneOrTwo(module, &source, .plus, &.{'='}, &.{.plus_equal}),
            '*' => try tokenizeOneOrTwo(module, &source, .times, &.{'='}, &.{.times_equal}),
            '|' => try tokenizeOneOrTwo(module, &source, .bar, &.{'>'}, &.{.bar_greater}),
            '=' => try tokenizeOneOrTwo(module, &source, .equal, &.{'='}, &.{.equal_equal}),
            '>' => try tokenizeOneOrTwo(module, &source, .greater_than, &.{ '=', '>' }, &.{ .greater_equal, .greater_greater }),
            '<' => try tokenizeOneOrTwo(module, &source, .less_than, &.{ '=', '<' }, &.{ .less_equal, .less_less }),
            '!' => try tokenizeTwo(module, &source, '=', .bang_equal),
            '\n' => try tokenizeNewLine(module, &source),
            else => try tokenizeSymbol(module, &source),
        };
        try entities.append(token);
    }
}

fn tokenizeSymbol(module: Entity, source: *Source) !Entity {
    const begin = source.position;
    var i: u64 = 1;
    while (i < source.code.len) : (i += 1) {
        switch (source.code[i]) {
            '(', ')', '[', ']', '{', '}', ' ', ':', '+', '-', '*', '/', '&', '|', '<', '>', ',', '\n', '\r', '.' => break,
            else => continue,
        }
    }
    const string = source.advance(i);
    const span = components.Span{ .begin = begin, .end = source.position };
    const symbols = [_][]const u8{
        "import", "fn", "end", "if", "then", "else", "while", "for", "in", "do", "foreign_export", "foreign_import", "struct", "_",
    };
    const tokens = [_]components.TokenKind{
        .import, .fn_, .end, .if_, .then, .else_, .while_, .for_, .in, .do, .foreign_export, .foreign_import, .struct_, .underscore,
    };
    for (symbols) |symbol, j| {
        if (std.mem.eql(u8, string, symbol)) {
            return try module.ecs.createEntity(.{ tokens[j], span });
        }
    }
    const interned = try module.ecs.getPtr(Strings).intern(string);
    return try module.ecs.createEntity(.{
        components.Literal.init(interned),
        components.TokenKind.symbol,
        span,
    });
}

fn tokenizeNumber(module: Entity, source: *Source, starts_with_decimal: bool) !Entity {
    var decimals_seen: u64 = if (starts_with_decimal) 1 else 0;
    const begin = source.position;
    var i: u64 = 1;
    while (i < source.code.len) : (i += 1) {
        switch (source.code[i]) {
            '0'...'9' => continue,
            '.' => decimals_seen += 1,
            else => break,
        }
    }
    const string = source.advance(i);
    const span = components.Span{ .begin = begin, .end = source.position };
    if (i == 1) {
        if (starts_with_decimal) return try module.ecs.createEntity(.{ components.TokenKind.dot, span });
        if (string[0] == '-') return try module.ecs.createEntity(.{ components.TokenKind.minus, span });
    }
    const interned = try module.ecs.getPtr(Strings).intern(string);
    const kind: components.TokenKind = if (decimals_seen == 0) .int else .float;
    const entity = try module.ecs.createEntity(.{
        components.Literal.init(interned),
        kind,
        span,
    });
    if (decimals_seen > 1) {
        const error_component = components.Error{
            .header = "TOKENIZER ERROR",
            .body = "Number should not have more than 1 decimal.",
            .span = span,
            .hint = "Remove the additional decimals.",
            .module = module,
        };
        _ = try entity.set(.{error_component});
    }
    return entity;
}

fn tokenizeString(module: Entity, source: *Source) !Entity {
    const begin = source.position;
    var i: u64 = 1;
    while (i < source.code.len) : (i += 1) {
        switch (source.code[i]) {
            '"' => {
                i += 1;
                break;
            },
            else => continue,
        }
    }
    const string = source.advance(i);
    const span = components.Span{ .begin = begin, .end = source.position };
    const interned = try module.ecs.getPtr(Strings).intern(string[1 .. i - 1]);
    const length = components.Length{ .value = @intCast(i32, string.len - 2) };
    return try module.ecs.createEntity(.{
        components.Literal.init(interned),
        components.TokenKind.string,
        length,
        span,
    });
}

fn tokenizeChar(module: Entity, source: *Source) !Entity {
    const begin = source.position;
    var i: u64 = 1;
    while (i < source.code.len) : (i += 1) {
        switch (source.code[i]) {
            '\'' => {
                i += 1;
                break;
            },
            else => continue,
        }
    }
    const string = source.advance(i);
    const span = components.Span{ .begin = begin, .end = source.position };
    const interned = try module.ecs.getPtr(Strings).intern(string[1 .. i - 1]);
    assert(string.len == 3);
    return try module.ecs.createEntity(.{
        components.Literal.init(interned),
        components.TokenKind.char,
        span,
    });
}
fn tokenizeOne(module: Entity, source: *Source, kind: components.TokenKind) !Entity {
    const begin = source.position;
    _ = source.advance(1);
    const span = components.Span{ .begin = begin, .end = source.position };
    return try module.ecs.createEntity(.{ kind, span });
}

fn tokenizeOneOrTwo(module: Entity, source: *Source, first: components.TokenKind, chars: []const u8, second: []const components.TokenKind) !Entity {
    const begin = source.position;
    if (source.code.len > 1) {
        const actual = source.code[1];
        for (chars) |expected, i| {
            if (actual == expected) {
                _ = source.advance(2);
                const span = components.Span{ .begin = begin, .end = source.position };
                return try module.ecs.createEntity(.{ second[i], span });
            }
        }
    }
    _ = source.advance(1);
    const span = components.Span{ .begin = begin, .end = source.position };
    return try module.ecs.createEntity(.{ first, span });
}

fn tokenizeTwo(module: Entity, source: *Source, char: u8, kind: components.TokenKind) !Entity {
    const begin = source.position;
    assert(source.code.len > 1 and source.code[1] == char);
    _ = source.advance(2);
    const span = components.Span{ .begin = begin, .end = source.position };
    return try module.ecs.createEntity(.{ kind, span });
}
