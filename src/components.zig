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
    left_paren,
    right_paren,
    colon,
    plus,
    times,
    comma,
    indent,
    equal,
};

pub const Indent = struct {
    spaces: u64,
};

pub const Literal = struct {
    interned: InternedString,
};

pub const Function = struct {
    name: Entity,
    parameters: List(Entity),
    return_type: Entity,
    body: List(Entity),
};

pub const Type = struct {
    entity: Entity,
};

pub const AstKind = enum(u8) {
    symbol,
    int,
    function,
    binary_op,
    define,
    call,
};

pub const BinaryOp = struct {
    pub const Kind = enum(u8) {
        add,
        multiply,
    };

    left: Entity,
    right: Entity,
    kind: Kind,
};

pub const Define = struct {
    name: Entity,
    value: Entity,
};

pub const Call = struct {
    function: Entity,
    arguments: List(Entity),
};
