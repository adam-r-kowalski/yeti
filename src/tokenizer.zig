const std = @import("std");
const Arena = std.heap.ArenaAllocator;
const assert = std.debug.assert;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
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
            '(' => try tokenizeOne(module, &source, .left_paren),
            ')' => try tokenizeOne(module, &source, .right_paren),
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

test "tokenize symbol" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code = "foo bar? _baz_";
    var tokens = try tokenize(module, code);
    {
        const token = tokens.peek().?;
        try expectEqual(token.get(components.TokenKind), .symbol);
        try expectEqualStrings(literalOf(token), "foo");
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 0, .row = 0 },
            .end = .{ .column = 3, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .symbol);
        try expectEqualStrings(literalOf(token), "foo");
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 0, .row = 0 },
            .end = .{ .column = 3, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .symbol);
        try expectEqualStrings(literalOf(token), "bar?");
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 4, .row = 0 },
            .end = .{ .column = 8, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .symbol);
        try expectEqualStrings(literalOf(token), "_baz_");
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 9, .row = 0 },
            .end = .{ .column = 14, .row = 0 },
        });
    }
    try expectEqual(tokens.next(), null);
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

test "tokenize number" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code = "100 -324 3.25 .73 5.3.2";
    var tokens = try tokenize(module, code);
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .int);
        try expectEqualStrings(literalOf(token), "100");
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 0, .row = 0 },
            .end = .{ .column = 3, .row = 0 },
        });
        try expectEqual(token.has(components.Error), null);
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .int);
        try expectEqualStrings(literalOf(token), "-324");
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 4, .row = 0 },
            .end = .{ .column = 8, .row = 0 },
        });
        try expectEqual(token.has(components.Error), null);
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .float);
        try expectEqualStrings(literalOf(token), "3.25");
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 9, .row = 0 },
            .end = .{ .column = 13, .row = 0 },
        });
        try expectEqual(token.has(components.Error), null);
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .float);
        try expectEqualStrings(literalOf(token), ".73");
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 14, .row = 0 },
            .end = .{ .column = 17, .row = 0 },
        });
        try expectEqual(token.has(components.Error), null);
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .float);
        try expectEqualStrings(literalOf(token), "5.3.2");
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 18, .row = 0 },
            .end = .{ .column = 23, .row = 0 },
        });
        const error_component = token.get(components.Error);
        try expectEqualStrings(error_component.header, "TOKENIZER ERROR");
        try expectEqualStrings(error_component.body, "Number should not have more than 1 decimal.");
        try expectEqual(error_component.span, .{
            .begin = .{ .column = 18, .row = 0 },
            .end = .{ .column = 23, .row = 0 },
        });
        try expectEqualStrings(error_component.hint, "Remove the additional decimals.");
    }
    try expectEqual(tokens.next(), null);
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
    return try module.ecs.createEntity(.{
        components.Literal.init(interned),
        components.TokenKind.string,
        span,
    });
}

test "tokenize string" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\"hello" "world"
    ;
    var tokens = try tokenize(module, code);
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .string);
        try expectEqualStrings(literalOf(token), "hello");
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 0, .row = 0 },
            .end = .{ .column = 7, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .string);
        try expectEqualStrings(literalOf(token), "world");
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 8, .row = 0 },
            .end = .{ .column = 15, .row = 0 },
        });
    }
    try expectEqual(tokens.next(), null);
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

test "tokenize function" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code = "start = fn(): u64 0 end";
    var tokens = try tokenize(module, code);
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .symbol);
        try expectEqualStrings(literalOf(token), "start");
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 0, .row = 0 },
            .end = .{ .column = 5, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .equal);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 6, .row = 0 },
            .end = .{ .column = 7, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .fn_);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 8, .row = 0 },
            .end = .{ .column = 10, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .left_paren);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 10, .row = 0 },
            .end = .{ .column = 11, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .right_paren);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 11, .row = 0 },
            .end = .{ .column = 12, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .colon);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 12, .row = 0 },
            .end = .{ .column = 13, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .symbol);
        try expectEqualStrings(literalOf(token), "u64");
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 14, .row = 0 },
            .end = .{ .column = 17, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .int);
        try expectEqualStrings(literalOf(token), "0");
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 18, .row = 0 },
            .end = .{ .column = 19, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .end);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 20, .row = 0 },
            .end = .{ .column = 23, .row = 0 },
        });
    }
    try expectEqual(tokens.next(), null);
}

test "tokenize multine function" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\f = fn(): u64
        \\  x = 5
        \\  y = 15
        \\  x + y
        \\end
    ;
    var tokens = try tokenize(module, code);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .equal);
    try expectEqual(tokens.next().?.get(components.TokenKind), .fn_);
    try expectEqual(tokens.next().?.get(components.TokenKind), .left_paren);
    try expectEqual(tokens.next().?.get(components.TokenKind), .right_paren);
    try expectEqual(tokens.next().?.get(components.TokenKind), .colon);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .new_line);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 13, .row = 0 },
            .end = .{ .column = 0, .row = 1 },
        });
    }
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .equal);
    try expectEqual(tokens.next().?.get(components.TokenKind), .int);
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .new_line);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 7, .row = 1 },
            .end = .{ .column = 0, .row = 2 },
        });
    }
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .equal);
    try expectEqual(tokens.next().?.get(components.TokenKind), .int);
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .new_line);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 8, .row = 2 },
            .end = .{ .column = 0, .row = 3 },
        });
    }
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .plus);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .new_line);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 7, .row = 3 },
            .end = .{ .column = 0, .row = 4 },
        });
    }
    try expectEqual(tokens.next().?.get(components.TokenKind), .end);
    try expectEqual(tokens.next(), null);
}

test "tokenize mulitine function with binary op" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\sum_of_squares = fn(x: u64, y: u64): u64
        \\  x2 = x * x
        \\  x2 = y * y
        \\  x2 + y2
        \\end
    ;
    var tokens = try tokenize(module, code);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .equal);
    try expectEqual(tokens.next().?.get(components.TokenKind), .fn_);
    try expectEqual(tokens.next().?.get(components.TokenKind), .left_paren);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .colon);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .comma);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .colon);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .right_paren);
    try expectEqual(tokens.next().?.get(components.TokenKind), .colon);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .new_line);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .equal);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .times);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .new_line);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .equal);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .times);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .new_line);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .plus);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .new_line);
    try expectEqual(tokens.next().?.get(components.TokenKind), .end);
    try expectEqual(tokens.next(), null);
}

test "greater operators" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code = "> >= = == : < <= >> <<";
    var tokens = try tokenize(module, code);
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .greater_than);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 0, .row = 0 },
            .end = .{ .column = 1, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .greater_equal);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 2, .row = 0 },
            .end = .{ .column = 4, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .equal);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 5, .row = 0 },
            .end = .{ .column = 6, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .equal_equal);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 7, .row = 0 },
            .end = .{ .column = 9, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .colon);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 10, .row = 0 },
            .end = .{ .column = 11, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .less_than);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 12, .row = 0 },
            .end = .{ .column = 13, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .less_equal);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 14, .row = 0 },
            .end = .{ .column = 16, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .greater_greater);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 17, .row = 0 },
            .end = .{ .column = 19, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .less_less);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 20, .row = 0 },
            .end = .{ .column = 22, .row = 0 },
        });
    }
    try expectEqual(tokens.next(), null);
}
