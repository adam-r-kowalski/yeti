const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const Entity = @import("../ecs.zig").Entity;
const List = @import("../list.zig").List;
const strings_module = @import("../strings.zig");
const Strings = strings_module.Strings;
const InternedString = strings_module.InternedString;
const Literal = @import("token.zig").Literal;

pub fn DistinctEntity(comptime unique_id: []const u8) type {
    assert(unique_id.len > 0);
    return struct {
        entity: Entity,

        const Self = @This();

        pub fn init(entity: Entity) Self {
            return Self{ .entity = entity };
        }
    };
}

pub fn DistinctEntities(comptime unique_id: []const u8) type {
    assert(unique_id.len > 0);
    return struct {
        entities: List(Entity, .{}),

        const Self = @This();

        pub fn init(allocator: *Allocator) Self {
            return Self{ .entities = List(Entity, .{}).init(allocator) };
        }

        pub fn fromSlice(allocator: *Allocator, entities: []Entity) !Self {
            const list = try List(Entity, .{}).fromSlice(allocator, entities);
            return Self{ .entities = list };
        }

        pub fn withCapacity(allocator: *Allocator, capacity: u64) !Self {
            const list = try List(Entity, .{}).withCapacity(allocator, capacity);
            return Self{ .entities = list };
        }

        pub fn append(self: *Self, entity: Entity) !void {
            try self.entities.append(entity);
        }

        pub fn appendAssumeCapacity(self: *Self, entity: Entity) void {
            self.entities.appendAssumeCapacity(entity);
        }

        pub fn slice(self: Self) []const Entity {
            return self.entities.slice();
        }

        pub fn last(self: Self) Entity {
            return self.entities.last();
        }

        pub fn len(self: Self) u64 {
            return self.entities.len;
        }
    };
}

pub fn DistinctEntityMap(comptime unique_id: []const u8, comptime Name: type) type {
    assert(unique_id.len > 0);

    return struct {
        const Map = std.AutoHashMap(InternedString, Entity);

        const Self = @This();

        map: Map,
        strings: *Strings,

        pub fn init(allocator: *Allocator, strings: *Strings) Self {
            return Self{ .map = Map.init(allocator), .strings = strings };
        }

        pub fn putInterned(self: *Self, interned: InternedString, entity: Entity) !void {
            try self.map.putNoClobber(interned, entity);
        }

        pub fn findString(self: Self, string: []const u8) Entity {
            const interned = self.strings.lookup.get(string).?;
            return self.map.get(interned).?;
        }

        pub fn findLiteral(self: Self, literal: Literal) Entity {
            return self.map.get(literal.interned).?;
        }

        pub fn hasLiteral(self: Self, literal: Literal) ?Entity {
            return self.map.get(literal.interned);
        }

        pub fn findName(self: Self, name: Name) Entity {
            return self.hasName(name).?;
        }

        pub fn hasName(self: Self, name: Name) ?Entity {
            const interned = name.entity.get(Literal).interned;
            return self.map.get(interned);
        }

        pub fn putName(self: *Self, value: Name, entity: Entity) !void {
            try self.map.putNoClobber(value.entity.get(Literal).interned, entity);
        }
    };
}
