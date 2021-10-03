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

pub const Position = struct {
    column: u64,
    row: u64,
};

pub const Span = struct {
    begin: Position,
    end: Position,
};

pub const Kind = enum(u8) {
    Symbol,
    Int,
    Float,
    Fn,
    LeftParen,
    RightParen,
    Colon,
};

pub const Literal = struct {
    interned: InternedString,
};

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
    codebase: *Codebase,
    source: Source,

    pub fn init(codebase: *Codebase, code: []const u8) Tokens {
        return Tokens{
            .codebase = codebase,
            .source = Source.init(code),
        };
    }

    pub fn next(self: *Tokens) !?Entity {
        trimWhitespace(self);
        if (self.source.code.len == 0) {
            return null;
        }
        return switch (self.source.code[0]) {
            '0'...'9', '-' => try tokenizeNumber(self, false),
            '.' => try tokenizeNumber(self, true),
            '(' => try tokenizeOne(self, Kind.LeftParen),
            ')' => try tokenizeOne(self, Kind.RightParen),
            ':' => try tokenizeOne(self, Kind.Colon),
            else => try tokenizeSymbol(self),
        };
    }
};

fn trimWhitespace(tokens: *Tokens) void {
    var i: u64 = 0;
    while (i < tokens.source.code.len and tokens.source.code[i] == ' ') : (i += 1) {}
    _ = tokens.source.advance(i);
}

fn tokenizeSymbol(tokens: *Tokens) !Entity {
    const begin = tokens.source.position;
    var i: u64 = 1;
    while (i < tokens.source.code.len) : (i += 1) {
        switch (tokens.source.code[i]) {
            '(', ')', '[', ']', '{', '}', ' ', ':', '+', '-', '*', '/', '&', '|', '<', '>' => break,
            else => continue,
        }
    }
    const string = tokens.source.advance(i);
    const span = Span{ .begin = begin, .end = tokens.source.position };
    if (std.mem.eql(u8, string, "fn")) {
        return try tokens.codebase.ecs.createEntity(.{ Kind.Fn, span });
    }
    const interned = try tokens.codebase.strings.intern(string);
    const literal = Literal{ .interned = interned };
    return try tokens.codebase.ecs.createEntity(.{
        literal,
        Kind.Symbol,
        span,
    });
}

fn literalOf(codebase: Codebase, entity: Entity) []const u8 {
    return codebase.strings.get(entity.get(Literal).?.interned).?;
}

test "tokenize symbol" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch panic("MEMORY LEAK", .{});
    const allocator = &gpa.allocator;
    var codebase = try Codebase.init(allocator);
    defer codebase.deinit();
    const code = "foo bar? _baz_";
    var tokens = Tokens.init(&codebase, code);
    {
        const token = (try tokens.next()).?;
        try expectEqual(token.get(Kind).?.*, Kind.Symbol);
        try expectEqualStrings(literalOf(codebase, token), "foo");
        try expectEqual(token.get(Span).?.*, Span{
            .begin = Position{ .column = 0, .row = 0 },
            .end = Position{ .column = 3, .row = 0 },
        });
    }
    {
        const token = (try tokens.next()).?;
        try expectEqual(token.get(Kind).?.*, Kind.Symbol);
        try expectEqualStrings(literalOf(codebase, token), "bar?");
        try expectEqual(token.get(Span).?.*, Span{
            .begin = Position{ .column = 4, .row = 0 },
            .end = Position{ .column = 8, .row = 0 },
        });
    }
    {
        const token = (try tokens.next()).?;
        try expectEqual(token.get(Kind).?.*, Kind.Symbol);
        try expectEqualStrings(literalOf(codebase, token), "_baz_");
        try expectEqual(token.get(Span).?.*, Span{
            .begin = Position{ .column = 9, .row = 0 },
            .end = Position{ .column = 14, .row = 0 },
        });
    }
    try expectEqual(try tokens.next(), null);
}

fn tokenizeNumber(tokens: *Tokens, starts_with_decimal: bool) !Entity {
    var decimals_seen: u64 = if (starts_with_decimal) 1 else 0;
    const begin = tokens.source.position;
    var i: u64 = 1;
    while (i < tokens.source.code.len) : (i += 1) {
        switch (tokens.source.code[i]) {
            '0'...'9' => continue,
            '.' => decimals_seen += 1,
            else => break,
        }
    }
    assert(decimals_seen <= 1);
    const string = tokens.source.advance(i);
    const interned = try tokens.codebase.strings.intern(string);
    const literal = Literal{ .interned = interned };
    const span = Span{ .begin = begin, .end = tokens.source.position };
    const kind = if (decimals_seen == 0) Kind.Int else Kind.Float;
    return try tokens.codebase.ecs.createEntity(.{
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
    var tokens = Tokens.init(&codebase, code);
    {
        const token = (try tokens.next()).?;
        try expectEqual(token.get(Kind).?.*, Kind.Int);
        try expectEqualStrings(literalOf(codebase, token), "100");
        try expectEqual(token.get(Span).?.*, Span{
            .begin = Position{ .column = 0, .row = 0 },
            .end = Position{ .column = 3, .row = 0 },
        });
    }
    {
        const token = (try tokens.next()).?;
        try expectEqual(token.get(Kind).?.*, Kind.Int);
        try expectEqualStrings(literalOf(codebase, token), "-324");
        try expectEqual(token.get(Span).?.*, Span{
            .begin = Position{ .column = 4, .row = 0 },
            .end = Position{ .column = 8, .row = 0 },
        });
    }
    {
        const token = (try tokens.next()).?;
        try expectEqual(token.get(Kind).?.*, Kind.Float);
        try expectEqualStrings(literalOf(codebase, token), "3.25");
        try expectEqual(token.get(Span).?.*, Span{
            .begin = Position{ .column = 9, .row = 0 },
            .end = Position{ .column = 13, .row = 0 },
        });
    }
    {
        const token = (try tokens.next()).?;
        try expectEqual(token.get(Kind).?.*, Kind.Float);
        try expectEqualStrings(literalOf(codebase, token), ".73");
        try expectEqual(token.get(Span).?.*, Span{
            .begin = Position{ .column = 14, .row = 0 },
            .end = Position{ .column = 17, .row = 0 },
        });
    }
    try expectEqual(try tokens.next(), null);
}

fn tokenizeOne(tokens: *Tokens, kind: Kind) !Entity {
    const begin = tokens.source.position;
    _ = tokens.source.advance(1);
    const span = Span{ .begin = begin, .end = tokens.source.position };
    return try tokens.codebase.ecs.createEntity(.{ kind, span });
}

test "tokenize function" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch panic("MEMORY LEAK", .{});
    const allocator = &gpa.allocator;
    var codebase = try Codebase.init(allocator);
    defer codebase.deinit();
    const code = "fn start() u64: 0";
    var tokens = Tokens.init(&codebase, code);
    {
        const token = (try tokens.next()).?;
        try expectEqual(token.get(Kind).?.*, Kind.Fn);
        try expectEqual(token.get(Span).?.*, Span{
            .begin = Position{ .column = 0, .row = 0 },
            .end = Position{ .column = 2, .row = 0 },
        });
    }
    {
        const token = (try tokens.next()).?;
        try expectEqual(token.get(Kind).?.*, Kind.Symbol);
        try expectEqualStrings(literalOf(codebase, token), "start");
        try expectEqual(token.get(Span).?.*, Span{
            .begin = Position{ .column = 3, .row = 0 },
            .end = Position{ .column = 8, .row = 0 },
        });
    }
    {
        const token = (try tokens.next()).?;
        try expectEqual(token.get(Kind).?.*, Kind.LeftParen);
        try expectEqual(token.get(Span).?.*, Span{
            .begin = Position{ .column = 8, .row = 0 },
            .end = Position{ .column = 9, .row = 0 },
        });
    }
    {
        const token = (try tokens.next()).?;
        try expectEqual(token.get(Kind).?.*, Kind.RightParen);
        try expectEqual(token.get(Span).?.*, Span{
            .begin = Position{ .column = 9, .row = 0 },
            .end = Position{ .column = 10, .row = 0 },
        });
    }
    {
        const token = (try tokens.next()).?;
        try expectEqual(token.get(Kind).?.*, Kind.Symbol);
        try expectEqualStrings(literalOf(codebase, token), "u64");
        try expectEqual(token.get(Span).?.*, Span{
            .begin = Position{ .column = 11, .row = 0 },
            .end = Position{ .column = 14, .row = 0 },
        });
    }
    {
        const token = (try tokens.next()).?;
        try expectEqual(token.get(Kind).?.*, Kind.Colon);
        try expectEqual(token.get(Span).?.*, Span{
            .begin = Position{ .column = 14, .row = 0 },
            .end = Position{ .column = 15, .row = 0 },
        });
    }
    {
        const token = (try tokens.next()).?;
        try expectEqual(token.get(Kind).?.*, Kind.Int);
        try expectEqualStrings(literalOf(codebase, token), "0");
        try expectEqual(token.get(Span).?.*, Span{
            .begin = Position{ .column = 16, .row = 0 },
            .end = Position{ .column = 17, .row = 0 },
        });
    }
    try expectEqual(try tokens.next(), null);
}
