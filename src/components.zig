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
    symbol,
    int,
    float,
    function,
    left_paren,
    right_paren,
    colon,
    plus,
    times,
};

pub const Literal = struct {
    interned: InternedString,
};

pub const Name = struct {
    interned: InternedString,

    pub fn init(symbol: Entity) Name {
        return Name{ .interned = symbol.get(Literal).interned };
    }
};

pub const ReturnType = struct {
    expression: Entity,

    pub fn init(expression: Entity) ReturnType {
        return ReturnType{ .expression = expression };
    }
};

pub const Body = struct {
    expressions: List(Entity),

    pub fn init(allocator: *Allocator) Body {
        return Body{ .expressions = List(Entity).init(allocator) };
    }
};

pub const AstKind = enum(u8) {
    symbol,
    int,
    function,
    binary_op,
};

pub const BinaryOpKind = enum(u8) {
    add,
    multiply,
};

pub const BinaryOp = struct {
    kind: BinaryOpKind,
    left: Entity,
    right: Entity,
};
