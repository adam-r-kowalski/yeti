const std = @import("std");
const assert = std.debug.assert;
const panic = std.debug.panic;
const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;

const Codebase = @import("codebase.zig").Codebase;
const Entity = @import("ecs.zig").Entity;
const InternedString = @import("strings.zig").InternedString;
const tokenizer = @import("tokenizer.zig");
const Kind = tokenizer.Kind;
const Tokens = tokenizer.Tokens;
const Literal = tokenizer.Literal;

pub const Name = struct {
    interned: InternedString,
};

fn parseFunction(codebase: *Codebase, tokens: *Tokens) !Entity {
    {
        const token = (try tokens.next()).?;
        assert(token.get(Kind).?.* == Kind.Fn);
    }
    const name = blk: {
        const token = (try tokens.next()).?;
        assert(token.get(Kind).?.* == Kind.Symbol);
        const interned = token.get(Literal).?.interned;
        break :blk Name{ .interned = interned };
    };
    assert((try tokens.next()).?.get(Kind).?.* == Kind.LeftParen);
    assert((try tokens.next()).?.get(Kind).?.* == Kind.RightParen);
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
