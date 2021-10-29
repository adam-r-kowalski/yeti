const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const Entity = @import("../ecs.zig").Entity;
const List = @import("../list.zig").List;

pub fn DistinctEntity(comptime name: []const u8) type {
    assert(name.len > 0);
    return struct {
        entity: Entity,

        const Self = @This();

        pub fn init(entity: Entity) Self {
            return Self{ .entity = entity };
        }
    };
}

pub fn DistinctEntities(comptime name: []const u8) type {
    assert(name.len > 0);
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

        pub fn append(self: *Self, entity: Entity) !void {
            try self.entities.append(entity);
        }

        pub fn slice(self: Self) []const Entity {
            return self.entities.slice();
        }

        pub fn last(self: Self) Entity {
            return self.entities.last();
        }
    };
}
