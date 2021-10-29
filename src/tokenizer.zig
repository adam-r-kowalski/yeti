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
const Position = components.token.Position;
const Span = components.token.Span;
const Literal = components.token.Literal;
const Kind = components.token.Kind;
const Indent = components.token.Indent;

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

    fn trimWhitespace(self: *Source) void {
        var i: u64 = 0;
        while (i < self.code.len) : (i += 1) {
            switch (self.code[i]) {
                ' ' => self.position.column += 1,
                '\n' => {
                    self.position.column = 0;
                    self.position.row += 1;
                },
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

    pub fn consume(self: *Tokens, kind: Kind) Entity {
        const token = self.next().?;
        assert(token.get(Kind) == kind);
        return token;
    }
};

pub fn tokenize(codebase: *ECS, code: []const u8) !Tokens {
    var entities = List(Entity, .{ .initial_capacity = 1024 }).init(&codebase.arena.allocator);
    var source = Source.init(code);
    while (true) {
        source.trimWhitespace();
        if (source.code.len == 0) return Tokens.init(entities.slice());
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
            else => try tokenizeSymbol(codebase, &source),
        };
        try entities.append(token);
    }
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
            '.',
            => break,
            else => continue,
        }
    }
    const string = source.advance(i);
    const span = Span{ .begin = begin, .end = source.position };
    if (std.mem.eql(u8, string, "import")) {
        return try codebase.createEntity(.{ Kind.import, span });
    } else if (std.mem.eql(u8, string, "function")) {
        return try codebase.createEntity(.{ Kind.function, span });
    } else if (std.mem.eql(u8, string, "end")) {
        return try codebase.createEntity(.{ Kind.end, span });
    } else {
        const interned = try codebase.getPtr(Strings).intern(string);
        return try codebase.createEntity(.{
            Literal.init(interned),
            Kind.symbol,
            span,
        });
    }
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
    var right_arrow = false;
    while (i < source.code.len) : (i += 1) {
        switch (source.code[i]) {
            '0'...'9' => continue,
            '.' => decimals_seen += 1,
            '>' => {
                assert(i == 1);
                right_arrow = true;
                i += 1;
                break;
            },
            else => break,
        }
    }
    assert(decimals_seen <= 1);
    const string = source.advance(i);
    const span = Span{ .begin = begin, .end = source.position };
    if (right_arrow) {
        return try codebase.createEntity(.{ Kind.right_arrow, span });
    } else if (i == 1 and starts_with_decimal) {
        return try codebase.createEntity(.{ Kind.dot, span });
    } else {
        const interned = try codebase.getPtr(Strings).intern(string);
        const kind: Kind = if (decimals_seen == 0) .int else .float;
        return try codebase.createEntity(.{
            Literal.init(interned),
            kind,
            span,
        });
    }
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
    const code = "start = function() -> U64 0 end";
    var tokens = try tokenize(&codebase, code);
    {
        const token = tokens.next().?;
        try expectEqual(token.get(Kind), .symbol);
        try expectEqualStrings(literalOf(token), "start");
        try expectEqual(token.get(Span), .{
            .begin = .{ .column = 0, .row = 0 },
            .end = .{ .column = 5, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(Kind), .equal);
        try expectEqual(token.get(Span), .{
            .begin = .{ .column = 6, .row = 0 },
            .end = .{ .column = 7, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(Kind), .function);
        try expectEqual(token.get(Span), .{
            .begin = .{ .column = 8, .row = 0 },
            .end = .{ .column = 16, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(Kind), .left_paren);
        try expectEqual(token.get(Span), .{
            .begin = .{ .column = 16, .row = 0 },
            .end = .{ .column = 17, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(Kind), .right_paren);
        try expectEqual(token.get(Span), .{
            .begin = .{ .column = 17, .row = 0 },
            .end = .{ .column = 18, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(Kind), .right_arrow);
        try expectEqual(token.get(Span), Span{
            .begin = Position{ .column = 19, .row = 0 },
            .end = Position{ .column = 21, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(Kind), .symbol);
        try expectEqualStrings(literalOf(token), "U64");
        try expectEqual(token.get(Span), Span{
            .begin = Position{ .column = 22, .row = 0 },
            .end = Position{ .column = 25, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(Kind), .int);
        try expectEqualStrings(literalOf(token), "0");
        try expectEqual(token.get(Span), Span{
            .begin = Position{ .column = 26, .row = 0 },
            .end = Position{ .column = 27, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(Kind), .end);
        try expectEqual(token.get(Span), Span{
            .begin = Position{ .column = 28, .row = 0 },
            .end = Position{ .column = 31, .row = 0 },
        });
    }
    try expectEqual(tokens.next(), null);
}

test "tokenize multine function" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const code =
        \\f = function() -> U64
        \\  x = 5
        \\  y = 15
        \\  x + y
        \\end
    ;
    var tokens = try tokenize(&codebase, code);
    try expectEqual(tokens.next().?.get(Kind), .symbol);
    try expectEqual(tokens.next().?.get(Kind), .equal);
    try expectEqual(tokens.next().?.get(Kind), .function);
    try expectEqual(tokens.next().?.get(Kind), .left_paren);
    try expectEqual(tokens.next().?.get(Kind), .right_paren);
    try expectEqual(tokens.next().?.get(Kind), .right_arrow);
    try expectEqual(tokens.next().?.get(Kind), .symbol);
    {
        const token = tokens.next().?;
        try expectEqual(token.get(Kind), .symbol);
        try expectEqual(token.get(Span), Span{
            .begin = Position{ .column = 2, .row = 1 },
            .end = Position{ .column = 3, .row = 1 },
        });
    }
    try expectEqual(tokens.next().?.get(Kind), .equal);
    try expectEqual(tokens.next().?.get(Kind), .int);
    {
        const token = tokens.next().?;
        try expectEqual(token.get(Kind), .symbol);
        try expectEqual(token.get(Span), Span{
            .begin = Position{ .column = 2, .row = 2 },
            .end = Position{ .column = 3, .row = 2 },
        });
    }
    try expectEqual(tokens.next().?.get(Kind), .equal);
    try expectEqual(tokens.next().?.get(Kind), .int);
    {
        const token = tokens.next().?;
        try expectEqual(token.get(Kind), .symbol);
        try expectEqual(token.get(Span), Span{
            .begin = Position{ .column = 2, .row = 3 },
            .end = Position{ .column = 3, .row = 3 },
        });
    }
    try expectEqual(tokens.next().?.get(Kind), .plus);
    try expectEqual(tokens.next().?.get(Kind), .symbol);
    try expectEqual(tokens.next().?.get(Kind), .end);
    try expectEqual(tokens.next(), null);
}

test "tokenize mulitine function with binary op" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const code =
        \\sum_of_squares = function(x: U64, y: U64) -> U64
        \\  x2 = x * x
        \\  x2 = y * y
        \\  x2 + y2
        \\end
    ;
    var tokens = try tokenize(&codebase, code);
    try expectEqual(tokens.next().?.get(Kind), .symbol);
    try expectEqual(tokens.next().?.get(Kind), .equal);
    try expectEqual(tokens.next().?.get(Kind), .function);
    try expectEqual(tokens.next().?.get(Kind), .left_paren);
    try expectEqual(tokens.next().?.get(Kind), .symbol);
    try expectEqual(tokens.next().?.get(Kind), .colon);
    try expectEqual(tokens.next().?.get(Kind), .symbol);
    try expectEqual(tokens.next().?.get(Kind), .comma);
    try expectEqual(tokens.next().?.get(Kind), .symbol);
    try expectEqual(tokens.next().?.get(Kind), .colon);
    try expectEqual(tokens.next().?.get(Kind), .symbol);
    try expectEqual(tokens.next().?.get(Kind), .right_paren);
    try expectEqual(tokens.next().?.get(Kind), .right_arrow);
    try expectEqual(tokens.next().?.get(Kind), .symbol);
    try expectEqual(tokens.next().?.get(Kind), .symbol);
    try expectEqual(tokens.next().?.get(Kind), .equal);
    try expectEqual(tokens.next().?.get(Kind), .symbol);
    try expectEqual(tokens.next().?.get(Kind), .times);
    try expectEqual(tokens.next().?.get(Kind), .symbol);
    try expectEqual(tokens.next().?.get(Kind), .symbol);
    try expectEqual(tokens.next().?.get(Kind), .equal);
    try expectEqual(tokens.next().?.get(Kind), .symbol);
    try expectEqual(tokens.next().?.get(Kind), .times);
    try expectEqual(tokens.next().?.get(Kind), .symbol);
    try expectEqual(tokens.next().?.get(Kind), .symbol);
    try expectEqual(tokens.next().?.get(Kind), .plus);
    try expectEqual(tokens.next().?.get(Kind), .symbol);
    try expectEqual(tokens.next().?.get(Kind), .end);
    try expectEqual(tokens.next(), null);
}
