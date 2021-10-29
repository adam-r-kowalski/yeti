const std = @import("std");
const Allocator = std.mem.Allocator;

const strings_module = @import("../strings.zig");
const Strings = strings_module.Strings;
const InternedString = strings_module.InternedString;
const Entity = @import("../ecs.zig").Entity;
const List = @import("../list.zig").List;
const Literal = @import("token.zig").Literal;
const distinct = @import("distinct.zig");
const DistinctEntity = distinct.DistinctEntity;
const DistinctEntities = distinct.DistinctEntities;

pub const Name = DistinctEntity("Name");
pub const ReturnType = DistinctEntity("Return Type");
pub const Value = DistinctEntity("Value");
pub const Callable = DistinctEntity("Callable");
pub const Type = DistinctEntity("Type");
pub const Parameters = DistinctEntities("Parameters");
pub const Body = DistinctEntities("Body");
pub const Arguments = DistinctEntities("Arguments");
pub const Unqualified = DistinctEntities("Unqualified");
pub const Overloads = DistinctEntities("Overloads");

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
