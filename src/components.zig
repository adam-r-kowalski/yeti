const std = @import("std");
const Arena = std.heap.ArenaAllocator;

const InternedString = @import("strings.zig").InternedString;
const List = @import("list.zig").List;
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
    const Entities = List(Entity, .{ .bucket_size = 8 });

    entities: Entities,

    pub fn init(arena: *Arena) Parameters {
        return Parameters{ .entities = Entities.init(arena) };
    }

    pub fn push(self: *Parameters, entity: Entity) !void {
        try self.entities.push(entity);
    }

    pub fn nth(self: Parameters, index: u64) Entity {
        return self.entities.nth(index);
    }

    pub fn len(self: Parameters) u64 {
        return self.entities.len;
    }
};

pub const ReturnType = struct {
    entity: Entity,

    pub fn init(entity: Entity) ReturnType {
        return ReturnType{ .entity = entity };
    }
};

pub const Body = struct {
    const Entities = List(Entity, .{ .bucket_size = 16 });

    entities: Entities,

    pub fn init(arena: *Arena) Body {
        return Body{ .entities = Entities.init(arena) };
    }

    pub fn push(self: *Body, entity: Entity) !void {
        try self.entities.push(entity);
    }

    pub fn nth(self: Body, index: u64) Entity {
        return self.entities.nth(index);
    }

    pub fn len(self: Body) u64 {
        return self.entities.len;
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
    const Entities = List(Entity, .{ .bucket_size = 8 });

    entities: Entities,

    pub fn init(arena: *Arena) Arguments {
        return Arguments{ .entities = Entities.init(arena) };
    }

    pub fn push(self: *Arguments, entity: Entity) !void {
        try self.entities.push(entity);
    }

    pub fn nth(self: Arguments, index: u64) Entity {
        return self.entities.nth(index);
    }

    pub fn len(self: Arguments) u64 {
        return self.entities.len;
    }
};

pub const Callable = struct {
    entity: Entity,

    pub fn init(entity: Entity) Callable {
        return Callable{ .entity = entity };
    }
};
