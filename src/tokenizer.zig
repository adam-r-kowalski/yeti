const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const panic = std.debug.panic;

const Codebase = @import("codebase.zig").Codebase;
const Entity = @import("ecs.zig").Entity;
const List = @import("list.zig").List;
const InternedString = @import("strings.zig").InternedString;
const literalOf = @import("test_utils.zig").literalOf;
const components = @import("components.zig");
const Position = components.Position;
const Span = components.Span;
const Literal = components.Literal;
const Kind = components.TokenKind;

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
};

pub const Tokens = struct {
    list: List(Entity),
    index: u64,

    pub fn init(allocator: *Allocator) Tokens {
        return Tokens{
            .list = List(Entity).init(allocator),
            .index = 0,
        };
    }

    pub fn deinit(self: *Tokens) void {
        self.list.deinit();
    }

    fn push(self: *Tokens, token: Entity) !void {
        try self.list.push(token);
    }

    pub fn next(self: *Tokens) ?Entity {
        if (self.index == self.list.len) {
            return null;
        }
        const index = self.index;
        self.index += 1;
        return self.list.data[index];
    }

    pub fn peek(self: Tokens) ?Entity {
        if (self.index == self.list.len) {
            return null;
        }
        return self.list.data[self.index];
    }

    pub fn advance(self: *Tokens) void {
        self.index += 1;
    }
};

pub fn tokenize(codebase: *Codebase, code: []const u8) !Tokens {
    var tokens = Tokens.init(codebase.allocator);
    var source = Source.init(code);
    while (true) {
        trimWhitespace(&source);
        if (source.code.len == 0) {
            return tokens;
        }
        const token = switch (source.code[0]) {
            '0'...'9', '-' => try tokenizeNumber(codebase, &source, false),
            '.' => try tokenizeNumber(codebase, &source, true),
            '(' => try tokenizeOne(codebase, &source, Kind.left_paren),
            ')' => try tokenizeOne(codebase, &source, Kind.right_paren),
            ':' => try tokenizeOne(codebase, &source, Kind.colon),
            '+' => try tokenizeOne(codebase, &source, Kind.plus),
            '*' => try tokenizeOne(codebase, &source, Kind.times),
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

fn tokenizeSymbol(codebase: *Codebase, source: *Source) !Entity {
    const begin = source.position;
    var i: u64 = 1;
    while (i < source.code.len) : (i += 1) {
        switch (source.code[i]) {
            '(', ')', '[', ']', '{', '}', ' ', ':', '+', '-', '*', '/', '&', '|', '<', '>' => break,
            else => continue,
        }
    }
    const string = source.advance(i);
    const span = Span{ .begin = begin, .end = source.position };
    if (std.mem.eql(u8, string, "fn")) {
        return try codebase.ecs.createEntity(.{ Kind.function, span });
    }
    const interned = try codebase.strings.intern(string);
    const literal = Literal{ .interned = interned };
    return try codebase.ecs.createEntity(.{
        literal,
        Kind.symbol,
        span,
    });
}

test "tokenize symbol" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch panic("MEMORY LEAK", .{});
    const allocator = &gpa.allocator;
    var codebase = try Codebase.init(allocator);
    defer codebase.deinit();
    const code = "foo bar? _baz_";
    var tokens = try tokenize(&codebase, code);
    defer tokens.deinit();
    {
        const token = tokens.peek().?;
        try expectEqual(token.get(Kind).*, Kind.symbol);
        try expectEqualStrings(literalOf(codebase, token), "foo");
        try expectEqual(token.get(Span).*, Span{
            .begin = Position{ .column = 0, .row = 0 },
            .end = Position{ .column = 3, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(Kind).*, Kind.symbol);
        try expectEqualStrings(literalOf(codebase, token), "foo");
        try expectEqual(token.get(Span).*, Span{
            .begin = Position{ .column = 0, .row = 0 },
            .end = Position{ .column = 3, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(Kind).*, Kind.symbol);
        try expectEqualStrings(literalOf(codebase, token), "bar?");
        try expectEqual(token.get(Span).*, Span{
            .begin = Position{ .column = 4, .row = 0 },
            .end = Position{ .column = 8, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(Kind).*, Kind.symbol);
        try expectEqualStrings(literalOf(codebase, token), "_baz_");
        try expectEqual(token.get(Span).*, Span{
            .begin = Position{ .column = 9, .row = 0 },
            .end = Position{ .column = 14, .row = 0 },
        });
    }
    try expectEqual(tokens.next(), null);
}

fn tokenizeNumber(codebase: *Codebase, source: *Source, starts_with_decimal: bool) !Entity {
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
    const interned = try codebase.strings.intern(string);
    const literal = Literal{ .interned = interned };
    const span = Span{ .begin = begin, .end = source.position };
    const kind = if (decimals_seen == 0) Kind.int else Kind.float;
    return try codebase.ecs.createEntity(.{
        literal,
        kind,
        span,
    });
}

test "tokenize number" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch panic("MEMORY LEAK", .{});
    const allocator = &gpa.allocator;
    var codebase = try Codebase.init(allocator);
    defer codebase.deinit();
    const code = "100 -324 3.25 .73";
    var tokens = try tokenize(&codebase, code);
    defer tokens.deinit();
    {
        const token = tokens.next().?;
        try expectEqual(token.get(Kind).*, Kind.int);
        try expectEqualStrings(literalOf(codebase, token), "100");
        try expectEqual(token.get(Span).*, Span{
            .begin = Position{ .column = 0, .row = 0 },
            .end = Position{ .column = 3, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(Kind).*, Kind.int);
        try expectEqualStrings(literalOf(codebase, token), "-324");
        try expectEqual(token.get(Span).*, Span{
            .begin = Position{ .column = 4, .row = 0 },
            .end = Position{ .column = 8, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(Kind).*, Kind.float);
        try expectEqualStrings(literalOf(codebase, token), "3.25");
        try expectEqual(token.get(Span).*, Span{
            .begin = Position{ .column = 9, .row = 0 },
            .end = Position{ .column = 13, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(Kind).*, Kind.float);
        try expectEqualStrings(literalOf(codebase, token), ".73");
        try expectEqual(token.get(Span).*, Span{
            .begin = Position{ .column = 14, .row = 0 },
            .end = Position{ .column = 17, .row = 0 },
        });
    }
    try expectEqual(tokens.next(), null);
}

fn tokenizeOne(codebase: *Codebase, source: *Source, kind: Kind) !Entity {
    const begin = source.position;
    _ = source.advance(1);
    const span = Span{ .begin = begin, .end = source.position };
    return try codebase.ecs.createEntity(.{ kind, span });
}

test "tokenize function" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch panic("MEMORY LEAK", .{});
    const allocator = &gpa.allocator;
    var codebase = try Codebase.init(allocator);
    defer codebase.deinit();
    const code = "fn start() u64: 0";
    var tokens = try tokenize(&codebase, code);
    defer tokens.deinit();
    {
        const token = tokens.next().?;
        try expectEqual(token.get(Kind).*, Kind.function);
        try expectEqual(token.get(Span).*, Span{
            .begin = Position{ .column = 0, .row = 0 },
            .end = Position{ .column = 2, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(Kind).*, Kind.symbol);
        try expectEqualStrings(literalOf(codebase, token), "start");
        try expectEqual(token.get(Span).*, Span{
            .begin = Position{ .column = 3, .row = 0 },
            .end = Position{ .column = 8, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(Kind).*, Kind.left_paren);
        try expectEqual(token.get(Span).*, Span{
            .begin = Position{ .column = 8, .row = 0 },
            .end = Position{ .column = 9, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(Kind).*, Kind.right_paren);
        try expectEqual(token.get(Span).*, Span{
            .begin = Position{ .column = 9, .row = 0 },
            .end = Position{ .column = 10, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(Kind).*, Kind.symbol);
        try expectEqualStrings(literalOf(codebase, token), "u64");
        try expectEqual(token.get(Span).*, Span{
            .begin = Position{ .column = 11, .row = 0 },
            .end = Position{ .column = 14, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(Kind).*, Kind.colon);
        try expectEqual(token.get(Span).*, Span{
            .begin = Position{ .column = 14, .row = 0 },
            .end = Position{ .column = 15, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(Kind).*, Kind.int);
        try expectEqualStrings(literalOf(codebase, token), "0");
        try expectEqual(token.get(Span).*, Span{
            .begin = Position{ .column = 16, .row = 0 },
            .end = Position{ .column = 17, .row = 0 },
        });
    }
    try expectEqual(tokens.next(), null);
}
