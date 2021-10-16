const std = @import("std");
const Arena = std.heap.ArenaAllocator;

const InternedString = @import("strings.zig").InternedString;
const Entity = @import("ecs.zig").Entity;

pub const Position = struct {
    column: u64,
    row: u64,

    pub fn init(column: u64, row: u64) Position {
        return Position{ .column = column, .row = row };
    }
};

pub const Span = struct {
    begin: Position,
    end: Position,

    pub fn init(begin: Position, end: Position) Span {
        return Span{ .begin = begin, .end = end };
    }
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

pub const Name = struct {
    entity: Entity,

    pub fn init(entity: Entity) Name {
        return Name{ .entity = entity };
    }
};

pub const Parameters = struct {
    entities: []const Entity,

    pub fn init(entities: []const Entity) Parameters {
        return Parameters{ .entities = entities };
    }
};

pub const ReturnType = struct {
    entity: Entity,

    pub fn init(entity: Entity) ReturnType {
        return ReturnType{ .entity = entity };
    }
};

pub const Body = struct {
    entities: []const Entity,

    pub fn init(entities: []const Entity) Body {
        return Body{ .entities = entities };
    }
};

pub const Type = struct {
    entity: Entity,

    pub fn init(entity: Entity) Type {
        return Type{ .entity = entity };
    }
};

pub const Value = struct {
    entity: Entity,

    pub fn init(entity: Entity) Value {
        return Value{ .entity = entity };
    }
};

pub const AstKind = enum(u8) {
    symbol,
    int,
    function,
    binary_op,
    define,
    call,
};

pub const BinaryOp = enum(u8) {
    add,
    multiply,
};

pub const Arguments = struct {
    entities: []const Entity,

    pub fn init(entities: []const Entity) Arguments {
        return Arguments{ .entities = entities };
    }
};

pub const Callable = struct {
    entity: Entity,

    pub fn init(entity: Entity) Callable {
        return Callable{ .entity = entity };
    }
};

pub const Functions = struct {
    entities: []const Entity,

    pub fn init(entities: []const Entity) Functions {
        return Functions{ .entities = entities };
    }
};

pub const Lookup = struct {
    map: std.AutoHashMap(InternedString, Entity),

    pub fn init(map: std.AutoHashMap(InternedString, Entity)) Lookup {
        return Lookup{ .map = map };
    }
};
