const std = @import("std");
const Allocator = std.mem.Allocator;

const strings_module = @import("../strings.zig");
const Strings = strings_module.Strings;
const InternedString = strings_module.InternedString;
const Entity = @import("../ecs.zig").Entity;
const List = @import("../list.zig").List;
const Literal = @import("token.zig").Literal;

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

pub const Value = struct {
    entity: Entity,

    pub fn init(entity: Entity) Value {
        return Value{ .entity = entity };
    }
};

pub const Kind = enum(u8) {
    symbol,
    int,
    function,
    binary_op,
    define,
    call,
    import,
    overload_set,
};

pub const BinaryOp = enum(u8) {
    add,
    multiply,
    dot,
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

pub const Unqualified = struct {
    entities: []const Entity,

    pub fn init(entities: []const Entity) Unqualified {
        return Unqualified{ .entities = entities };
    }
};

pub const Overloads = struct {
    entities: List(Entity, .{}),

    pub fn init(allocator: *Allocator) Overloads {
        return Overloads{ .entities = List(Entity, .{}).init(allocator) };
    }
};

pub const TopLevel = struct {
    const Map = std.AutoHashMap(InternedString, Entity);

    map: Map,
    strings: *Strings,

    pub fn init(allocator: *Allocator, strings: *Strings) TopLevel {
        return TopLevel{
            .map = Map.init(allocator),
            .strings = strings,
        };
    }

    pub fn findString(self: TopLevel, string: []const u8) Entity {
        const interned = self.strings.lookup.get(string).?;
        return self.map.get(interned).?;
    }

    pub fn findName(self: TopLevel, name: Name) Entity {
        return self.hasName(name).?;
    }

    pub fn findLiteral(self: TopLevel, literal: Literal) Entity {
        return self.map.get(literal.interned).?;
    }

    pub fn hasName(self: TopLevel, name: Name) ?Entity {
        const interned = name.entity.get(Literal).interned;
        return self.map.get(interned);
    }

    pub fn hasLiteral(self: TopLevel, literal: Literal) ?Entity {
        return self.map.get(literal.interned);
    }

    pub fn put(self: *TopLevel, value: Name, entity: Entity) !void {
        try self.map.putNoClobber(value.entity.get(Literal).interned, entity);
    }
};

pub const Type = struct {
    entity: Entity,

    pub fn init(entity: Entity) Type {
        return Type{ .entity = entity };
    }
};
