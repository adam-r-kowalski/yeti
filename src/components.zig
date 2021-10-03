const std = @import("std");
const Allocator = std.mem.Allocator;

const InternedString = @import("strings.zig").InternedString;
const List = @import("list.zig").List;
const Entity = @import("ecs.zig").Entity;

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
    Plus,
};

pub const Literal = struct {
    interned: InternedString,
};

pub const Name = struct {
    interned: InternedString,
};

pub const ReturnType = struct {
    expression: Entity,
};

pub const Body = struct {
    expressions: List(Entity),

    pub fn init(allocator: *Allocator) Body {
        return Body{ .expressions = List(Entity).init(allocator) };
    }
};

pub const AstKind = enum(u8) {
    Symbol,
    Int,
    Function,
    BinaryOp,
};

pub const BinaryOpKind = enum(u8) {
    Add,
};

pub const BinaryOp = struct {
    kind: BinaryOpKind,
    left: Entity,
    right: Entity,
};
