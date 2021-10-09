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
};

pub const Parameters = struct {
    entity: Entity,
};

pub const ReturnType = struct {
    entity: Entity,
};

pub const Children = struct {
    entities: List(Entity),
};

pub const Body = struct {
    entity: Entity,
};

pub const AstKind = enum(u8) {
    symbol,
    int,
    function,
    binary_op,
};

pub const BinaryOp = struct {
    pub const Kind = enum(u8) {
        add,
        multiply,
    };

    kind: Kind,
    left: Entity,
    right: Entity,
};
