const std = @import("std");
const Allocator = std.mem.Allocator;

const List = @import("list.zig").List;
const Entity = @import("ecs.zig").Entity;
const InternedString = @import("strings.zig").InternedString;

pub const Position = struct {
    column: u64,
    row: u64,
};

pub const Span = struct {
    begin: Position,
    end: Position,
};

pub const TokenKind = enum(u8) {
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
