const std = @import("std");
const Arena = std.heap.ArenaAllocator;

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
    entity: Entity,

    pub fn init(entity: Entity) Name {
        return Name{ .entity = entity };
    }
};

pub const Parameters = struct {
    entities: List(Entity),

    pub fn init(arena: *Arena) Parameters {
        return Parameters{ .entities = List(Entity).init(arena) };
    }
};

pub const ReturnType = struct {
    entity: Entity,

    pub fn init(entity: Entity) ReturnType {
        return ReturnType{ .entity = entity };
    }
};

pub const Body = struct {
    entities: List(Entity),

    pub fn init(arena: *Arena) Body {
        return Body{ .entities = List(Entity).init(arena) };
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
