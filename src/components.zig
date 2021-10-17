const std = @import("std");
const Arena = std.heap.ArenaAllocator;

const strings_module = @import("strings.zig");
const Strings = strings_module.Strings;
const InternedString = strings_module.InternedString;
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
    import,
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
    import,
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
    const Map = std.AutoHashMap(InternedString, Entity);

    map: Map,
    strings: *Strings,

    pub fn init(map: Map, strings: *Strings) Lookup {
        return Lookup{ .map = map, .strings = strings };
    }

    pub fn literal(self: Lookup, string: []const u8) Entity {
        const interned = self.strings.lookup.get(string).?;
        return self.map.get(interned).?;
    }

    pub fn name(self: Lookup, value: Name) Entity {
        const interned = value.entity.get(Literal).interned;
        return self.map.get(interned).?;
    }
};
