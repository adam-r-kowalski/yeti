const std = @import("std");
const assert = std.debug.assert;
const panic = std.debug.panic;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const Codebase = @import("codebase.zig").Codebase;
const Entity = @import("ecs.zig").Entity;
const InternedString = @import("strings.zig").InternedString;
const tokenizer = @import("tokenizer.zig");
const TokenKind = tokenizer.Kind;
const Tokens = tokenizer.Tokens;
const Literal = tokenizer.Literal;
const Span = tokenizer.Span;
const Position = tokenizer.Position;
const literalOf = @import("test_utils.zig").literalOf;

pub const Name = struct {
    interned: InternedString,
};

pub const Kind = enum(u8) {
    Symbol,
};

fn parseExpression(codebase: *Codebase, tokens: *Tokens) !Entity {
    const token = (try tokens.next()).?;
    const kind = token.get(TokenKind).?.*;
    return switch (kind) {
        TokenKind.Symbol => parseSymbol(codebase, token),
        else => panic("\nkind = {}\n", .{kind}),
    };
}

fn parseSymbol(codebase: *Codebase, token: Entity) !Entity {
    const expression = try codebase.ecs.createEntity(.{Kind.Symbol});
    try expression.share(token, .{ Literal, Span });
    return expression;
}

test "parse symbol" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch panic("MEMORY LEAK", .{});
    const allocator = &gpa.allocator;
    var codebase = try Codebase.init(allocator);
    defer codebase.deinit();
    const code = "foo";
    var tokens = Tokens.init(&codebase, code);
    const expression = try parseExpression(&codebase, &tokens);
    try expectEqual(expression.get(Kind).?.*, Kind.Symbol);
    try expectEqualStrings(literalOf(codebase, expression), "foo");
    try expectEqual(expression.get(Span).?.*, Span{
        .begin = Position{ .column = 0, .row = 0 },
        .end = Position{ .column = 3, .row = 0 },
    });
}

fn parseFunction(codebase: *Codebase, tokens: *Tokens) !Entity {
    {
        const token = (try tokens.next()).?;
        assert(token.get(TokenKind).?.* == TokenKind.Fn);
    }
    const name = blk: {
        const token = (try tokens.next()).?;
        assert(token.get(TokenKind).?.* == TokenKind.Symbol);
        const interned = token.get(Literal).?.interned;
        break :blk Name{ .interned = interned };
    };
    assert((try tokens.next()).?.get(TokenKind).?.* == TokenKind.LeftParen);
    assert((try tokens.next()).?.get(TokenKind).?.* == TokenKind.RightParen);
    assert((try tokens.next()).?.get(TokenKind).?.* == TokenKind.Symbol);
    assert((try tokens.next()).?.get(TokenKind).?.* == TokenKind.Colon);
    assert((try tokens.next()).?.get(TokenKind).?.* == TokenKind.Int);
    return try codebase.ecs.createEntity(.{name});
}

fn nameOf(codebase: Codebase, entity: Entity) []const u8 {
    return codebase.strings.get(entity.get(Name).?.interned).?;
}

test "parse function" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch panic("MEMORY LEAK", .{});
    const allocator = &gpa.allocator;
    var codebase = try Codebase.init(allocator);
    defer codebase.deinit();
    const code = "fn start() u64: 0";
    var tokens = Tokens.init(&codebase, code);
    const function = try parseFunction(&codebase, &tokens);
    try expectEqualStrings(nameOf(codebase, function), "start");
}
