const std = @import("std");
const Allocator = std.mem.Allocator;

const Entity = @import("../ecs.zig").Entity;
const strings_module = @import("../strings.zig");
const Strings = strings_module.Strings;
const InternedString = strings_module.InternedString;
const Literal = @import("token.zig").Literal;

pub const Type = struct {
    entity: Entity,

    pub fn init(entity: Entity) Type {
        return Type{ .entity = entity };
    }
};

pub const Builtins = struct {
    Type: Entity,
    I64: Entity,
    I32: Entity,
    U64: Entity,
    U32: Entity,
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
};
