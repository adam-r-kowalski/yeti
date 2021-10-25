const std = @import("std");
const Allocator = std.mem.Allocator;

const Entity = @import("../ecs.zig").Entity;
const strings_module = @import("../strings.zig");
const Strings = strings_module.Strings;
const InternedString = strings_module.InternedString;
const Literal = @import("token.zig").Literal;
const Name = @import("ast.zig").Name;

pub const Type = struct {
    entity: Entity,

    pub fn init(entity: Entity) Type {
        return Type{ .entity = entity };
    }
};

pub const Builtins = struct {
    Type: Entity,
    Int: Entity,
    Nat: Entity,
    Real: Entity,
};

pub const Scope = struct {
    const Map = std.AutoHashMap(InternedString, Entity);

    map: Map,
    strings: *Strings,

    pub fn init(allocator: *Allocator, strings: *Strings) Scope {
        return Scope{ .map = Map.init(allocator), .strings = strings };
    }

    pub fn put(self: *Scope, interned: InternedString, entity: Entity) !void {
        try self.map.putNoClobber(interned, entity);
    }

    pub fn findString(self: Scope, string: []const u8) Entity {
        const interned = self.strings.lookup.get(string).?;
        return self.map.get(interned).?;
    }

    pub fn findLiteral(self: Scope, literal: Literal) Entity {
        return self.map.get(literal.interned).?;
    }

    pub fn hasLiteral(self: Scope, literal: Literal) ?Entity {
        return self.map.get(literal.interned);
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

    pub fn hasName(self: TopLevel, name: Name) ?Entity {
        const interned = name.entity.get(Literal).interned;
        return self.map.get(interned);
    }

    pub fn put(self: *TopLevel, value: Name, entity: Entity) !void {
        try self.map.putNoClobber(value.entity.get(Literal).interned, entity);
    }
};
