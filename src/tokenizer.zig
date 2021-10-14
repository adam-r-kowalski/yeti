const std = @import("std");
const Arena = std.heap.ArenaAllocator;
const assert = std.debug.assert;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const panic = std.debug.panic;

const initCodebase = @import("codebase.zig").initCodebase;
const ecs = @import("ecs.zig");
const Entity = ecs.Entity;
const ECS = ecs.ECS;
const List = @import("list.zig").List;
const Strings = @import("strings.zig").Strings;
const literalOf = @import("test_utils.zig").literalOf;
const components = @import("components.zig");
const Position = components.Position;
const Span = components.Span;
const Literal = components.Literal;
const Kind = components.TokenKind;
const Indent = components.Indent;

const Source = struct {
    code: []const u8,
    position: Position,

    fn init(code: []const u8) Source {
        return Source{
            .code = code,
            .position = Position{
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

    fn newline(self: *Source) void {
        self.code = self.code[1..];
        self.position.row += 1;
        self.position.column = 0;
    }
};

const TokenList = List(Entity, .{ .bucket_size = 1024 });

pub const Tokens = struct {
    iterator: TokenList.Iterator,

    pub fn next(self: *Tokens) ?Entity {
        return self.iterator.next();
    }

    pub fn peek(self: Tokens) ?Entity {
        return self.iterator.peek();
    }

    pub fn consume(self: *Tokens, kind: Kind) Entity {
        const token = self.next().?;
        assert(token.get(Kind) == kind);
        return token;
    }
};

pub fn tokenize(codebase: *ECS, code: []const u8) !Tokens {
    var tokens = TokenList.init(codebase.arena);
    var source = Source.init(code);
    while (true) {
        trimWhitespace(&source);
        if (source.code.len == 0) {
            return Tokens{ .iterator = tokens.iterate() };
        }
        const token = switch (source.code[0]) {
            '0'...'9', '-' => try tokenizeNumber(codebase, &source, false),
            '.' => try tokenizeNumber(codebase, &source, true),
            '(' => try tokenizeOne(codebase, &source, .left_paren),
            ')' => try tokenizeOne(codebase, &source, .right_paren),
            ':' => try tokenizeOne(codebase, &source, .colon),
            '+' => try tokenizeOne(codebase, &source, .plus),
            '*' => try tokenizeOne(codebase, &source, .times),
            ',' => try tokenizeOne(codebase, &source, .comma),
            '=' => try tokenizeOne(codebase, &source, .equal),
            '\n' => try tokenizeIndent(codebase, &source),
            else => try tokenizeSymbol(codebase, &source),
        };
        try tokens.push(token);
    }
}

fn trimWhitespace(source: *Source) void {
    var i: u64 = 0;
    while (i < source.code.len and source.code[i] == ' ') : (i += 1) {}
    _ = source.advance(i);
}

fn tokenizeSymbol(codebase: *ECS, source: *Source) !Entity {
    const begin = source.position;
    var i: u64 = 1;
    while (i < source.code.len) : (i += 1) {
        switch (source.code[i]) {
            '(',
            ')',
            '[',
            ']',
            '{',
            '}',
            ' ',
            ':',
            '+',
            '-',
            '*',
            '/',
            '&',
            '|',
            '<',
            '>',
            ',',
            '\n',
            => break,
            else => continue,
        }
    }
    const string = source.advance(i);
    const span = Span{ .begin = begin, .end = source.position };
    const interned = try codebase.getPtr(Strings).intern(string);
    const literal = Literal{ .interned = interned };
    return try codebase.createEntity(.{
        literal,
        Kind.symbol,
        span,
    });
}

test "tokenize symbol" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const code = "foo bar? _baz_";
    var tokens = try tokenize(&codebase, code);
    {
        const token = tokens.peek().?;
        try expectEqual(token.get(Kind), .symbol);
        try expectEqualStrings(literalOf(token), "foo");
        try expectEqual(token.get(Span), Span{
            .begin = Position{ .column = 0, .row = 0 },
            .end = Position{ .column = 3, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(Kind), .symbol);
        try expectEqualStrings(literalOf(token), "foo");
        try expectEqual(token.get(Span), Span{
            .begin = Position{ .column = 0, .row = 0 },
            .end = Position{ .column = 3, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(Kind), .symbol);
        try expectEqualStrings(literalOf(token), "bar?");
        try expectEqual(token.get(Span), Span{
            .begin = Position{ .column = 4, .row = 0 },
            .end = Position{ .column = 8, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(Kind), .symbol);
        try expectEqualStrings(literalOf(token), "_baz_");
        try expectEqual(token.get(Span), Span{
            .begin = Position{ .column = 9, .row = 0 },
            .end = Position{ .column = 14, .row = 0 },
        });
    }
    try expectEqual(tokens.next(), null);
}

fn tokenizeNumber(codebase: *ECS, source: *Source, starts_with_decimal: bool) !Entity {
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
    assert(decimals_seen <= 1);
    const string = source.advance(i);
    const interned = try codebase.getPtr(Strings).intern(string);
    const literal = Literal{ .interned = interned };
    const span = Span{ .begin = begin, .end = source.position };
    const kind: Kind = if (decimals_seen == 0) .int else .float;
    return try codebase.createEntity(.{
        literal,
        kind,
        span,
    });
}

test "tokenize number" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const code = "100 -324 3.25 .73";
    var tokens = try tokenize(&codebase, code);
    {
        const token = tokens.next().?;
        try expectEqual(token.get(Kind), .int);
        try expectEqualStrings(literalOf(token), "100");
        try expectEqual(token.get(Span), Span{
            .begin = Position{ .column = 0, .row = 0 },
            .end = Position{ .column = 3, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(Kind), .int);
        try expectEqualStrings(literalOf(token), "-324");
        try expectEqual(token.get(Span), Span{
            .begin = Position{ .column = 4, .row = 0 },
            .end = Position{ .column = 8, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(Kind), .float);
        try expectEqualStrings(literalOf(token), "3.25");
        try expectEqual(token.get(Span), Span{
            .begin = Position{ .column = 9, .row = 0 },
            .end = Position{ .column = 13, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(Kind), .float);
        try expectEqualStrings(literalOf(token), ".73");
        try expectEqual(token.get(Span), Span{
            .begin = Position{ .column = 14, .row = 0 },
            .end = Position{ .column = 17, .row = 0 },
        });
    }
    try expectEqual(tokens.next(), null);
}

fn tokenizeOne(codebase: *ECS, source: *Source, kind: Kind) !Entity {
    const begin = source.position;
    _ = source.advance(1);
    const span = Span{ .begin = begin, .end = source.position };
    return try codebase.createEntity(.{ kind, span });
}

test "tokenize function" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const code = "start() u64 = 0";
    var tokens = try tokenize(&codebase, code);
    {
        const token = tokens.next().?;
        try expectEqual(token.get(Kind), .symbol);
        try expectEqualStrings(literalOf(token), "start");
        try expectEqual(token.get(Span), Span{
            .begin = Position{ .column = 0, .row = 0 },
            .end = Position{ .column = 5, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(Kind), .left_paren);
        try expectEqual(token.get(Span), Span{
            .begin = Position{ .column = 5, .row = 0 },
            .end = Position{ .column = 6, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(Kind), .right_paren);
        try expectEqual(token.get(Span), Span{
            .begin = Position{ .column = 6, .row = 0 },
            .end = Position{ .column = 7, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(Kind), .symbol);
        try expectEqualStrings(literalOf(token), "u64");
        try expectEqual(token.get(Span), Span{
            .begin = Position{ .column = 8, .row = 0 },
            .end = Position{ .column = 11, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(Kind), .equal);
        try expectEqual(token.get(Span), Span{
            .begin = Position{ .column = 12, .row = 0 },
            .end = Position{ .column = 13, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(Kind), .int);
        try expectEqualStrings(literalOf(token), "0");
        try expectEqual(token.get(Span), Span{
            .begin = Position{ .column = 14, .row = 0 },
            .end = Position{ .column = 15, .row = 0 },
        });
    }
    try expectEqual(tokens.next(), null);
}

fn tokenizeIndent(codebase: *ECS, source: *Source) !Entity {
    const begin = source.position;
    source.newline();
    var i: u64 = 0;
    while (i < source.code.len and source.code[i] == ' ') : (i += 1) {}
    _ = source.advance(i);
    const span = Span{ .begin = begin, .end = source.position };
    const indent = Indent{ .spaces = i };
    return try codebase.createEntity(.{
        Kind.indent,
        indent,
        span,
    });
}

test "tokenize function with newline" {
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
    try expectEqual(tokens.next().?.get(Kind), .symbol);
    try expectEqual(tokens.next().?.get(Kind), .left_paren);
    try expectEqual(tokens.next().?.get(Kind), .right_paren);
    try expectEqual(tokens.next().?.get(Kind), .symbol);
    try expectEqual(tokens.next().?.get(Kind), .equal);
    {
        const token = tokens.next().?;
        try expectEqual(token.get(Kind), .indent);
        try expectEqual(token.get(Indent), Indent{ .spaces = 2 });
        try expectEqual(token.get(Span), Span{
            .begin = Position{ .row = 0, .column = 9 },
            .end = Position{ .row = 1, .column = 2 },
        });
    }
    try expectEqual(tokens.next().?.get(Kind), .symbol);
    try expectEqual(tokens.next().?.get(Kind), .equal);
    try expectEqual(tokens.next().?.get(Kind), .int);
    {
        const token = tokens.next().?;
        try expectEqual(token.get(Kind), .indent);
        try expectEqual(token.get(Indent), Indent{ .spaces = 2 });
        try expectEqual(token.get(Span), Span{
            .begin = Position{ .row = 1, .column = 7 },
            .end = Position{ .row = 2, .column = 2 },
        });
    }
    try expectEqual(tokens.next().?.get(Kind), .symbol);
    try expectEqual(tokens.next().?.get(Kind), .equal);
    try expectEqual(tokens.next().?.get(Kind), .int);
    {
        const token = tokens.next().?;
        try expectEqual(token.get(Kind), .indent);
        try expectEqual(token.get(Indent), Indent{ .spaces = 2 });
        try expectEqual(token.get(Span), Span{
            .begin = Position{ .row = 2, .column = 8 },
            .end = Position{ .row = 3, .column = 2 },
        });
    }
    try expectEqual(tokens.next().?.get(Kind), .symbol);
    try expectEqual(tokens.next().?.get(Kind), .plus);
    try expectEqual(tokens.next().?.get(Kind), .symbol);
    try expectEqual(tokens.next(), null);
}

test "tokenize function with newline with binary op" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const code =
        \\sum_of_squares(x: u64, y: u64) u64 =
        \\  x2 = x * x
        \\  x2 = y * y
        \\  x2 + y2
    ;
    var tokens = try tokenize(&codebase, code);
    try expectEqual(tokens.next().?.get(Kind), .symbol);
    try expectEqual(tokens.next().?.get(Kind), .left_paren);
    try expectEqual(tokens.next().?.get(Kind), .symbol);
    try expectEqual(tokens.next().?.get(Kind), .colon);
    try expectEqual(tokens.next().?.get(Kind), .symbol);
    try expectEqual(tokens.next().?.get(Kind), .comma);
    try expectEqual(tokens.next().?.get(Kind), .symbol);
    try expectEqual(tokens.next().?.get(Kind), .colon);
    try expectEqual(tokens.next().?.get(Kind), .symbol);
    try expectEqual(tokens.next().?.get(Kind), .right_paren);
    try expectEqual(tokens.next().?.get(Kind), .symbol);
    try expectEqual(tokens.next().?.get(Kind), .equal);
    try expectEqual(tokens.next().?.get(Kind), .indent);
    try expectEqual(tokens.next().?.get(Kind), .symbol);
    try expectEqual(tokens.next().?.get(Kind), .equal);
    try expectEqual(tokens.next().?.get(Kind), .symbol);
    try expectEqual(tokens.next().?.get(Kind), .times);
    try expectEqual(tokens.next().?.get(Kind), .symbol);
    try expectEqual(tokens.next().?.get(Kind), .indent);
    try expectEqual(tokens.next().?.get(Kind), .symbol);
    try expectEqual(tokens.next().?.get(Kind), .equal);
    try expectEqual(tokens.next().?.get(Kind), .symbol);
    try expectEqual(tokens.next().?.get(Kind), .times);
    try expectEqual(tokens.next().?.get(Kind), .symbol);
    try expectEqual(tokens.next().?.get(Kind), .indent);
    try expectEqual(tokens.next().?.get(Kind), .symbol);
    try expectEqual(tokens.next().?.get(Kind), .plus);
    try expectEqual(tokens.next().?.get(Kind), .symbol);
    try expectEqual(tokens.next(), null);
}
