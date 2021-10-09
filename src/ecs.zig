const std = @import("std");
const Arena = std.heap.ArenaAllocator;
const panic = std.debug.panic;
const assert = std.debug.assert;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectEqualSlices = std.testing.expectEqualSlices;
const TypeInfo = std.builtin.TypeInfo;

const List = @import("list.zig").List;

fn Component(comptime T: type) type {
    return struct {
        lookup: std.AutoHashMap(u64, u64),
        data: List(T),

        const Self = @This();

        fn init(arena: *Arena) Self {
            return Self{
                .lookup = std.AutoHashMap(u64, u64).init(&arena.allocator),
                .data = List(T).init(arena),
            };
        }

        fn set(self: *Self, entity: Entity, value: T) !void {
            try self.lookup.putNoClobber(entity.uuid, self.data.len);
            try self.data.push(value);
        }

        fn get(self: Self, entity: Entity) *const T {
            const index = self.lookup.get(entity.uuid).?;
            return self.data.nth(index);
        }
    };
}

pub const ECS = struct {
    components: std.StringHashMap(u64),
    resources: std.StringHashMap(u64),
    next_uuid: u64,
    arena: *Arena,

    pub fn init(arena: *Arena) ECS {
        return ECS{
            .components = std.StringHashMap(u64).init(&arena.allocator),
            .resources = std.StringHashMap(u64).init(&arena.allocator),
            .next_uuid = 0,
            .arena = arena,
        };
    }

    pub fn createEntity(self: *ECS, components: anytype) !Entity {
        const uuid = self.next_uuid;
        self.next_uuid += 1;
        const entity = Entity{
            .uuid = uuid,
            .ecs = self,
        };
        return try entity.set(components);
    }
};

pub const Entity = struct {
    uuid: u64,
    ecs: *ECS,

    pub fn set(self: Entity, components: anytype) !Entity {
        const type_info = @typeInfo(@TypeOf(components)).Struct;
        assert(type_info.is_tuple);
        inline for (type_info.fields) |field| {
            const T = field.field_type;
            const result = try self.ecs.components.getOrPut(@typeName(T));
            if (result.found_existing) {
                const component = @intToPtr(*Component(T), result.value_ptr.*);
                try component.*.set(self, @field(components, field.name));
            } else {
                const component = try self.ecs.arena.allocator.create(Component(T));
                component.* = Component(T).init(self.ecs.arena);
                try component.*.set(self, @field(components, field.name));
                result.value_ptr.* = @ptrToInt(component);
            }
        }
        return self;
    }

    pub fn get(self: Entity, comptime T: type) *const T {
        const component = self.ecs.components.getPtr(@typeName(T)).?;
        return @intToPtr(*Component(T), component.*).get(self);
    }
};

const Name = struct {
    value: []const u8,
};

const Age = struct {
    value: u8,
};

const Job = struct {
    value: []const u8,
};

test "entity get and set component" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var ecs = ECS.init(&arena);
    const entity = try ecs.createEntity(.{});
    _ = try entity.set(.{Name{ .value = "Joe" }});
    try expectEqual(entity.get(Name).*, Name{ .value = "Joe" });
}

test "entity get and set components" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var ecs = ECS.init(&arena);
    const entity = try ecs.createEntity(.{});
    _ = try entity.set(.{ Name{ .value = "Joe" }, Age{ .value = 20 } });
    try expectEqual(entity.get(Name).*, Name{ .value = "Joe" });
    try expectEqual(entity.get(Age).*, Age{ .value = 20 });
}

test "entity get and set components on creation" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var ecs = ECS.init(&arena);
    const entity = try ecs.createEntity(.{ Name{ .value = "Joe" }, Age{ .value = 20 } });
    try expectEqual(entity.get(Name).*, Name{ .value = "Joe" });
    try expectEqual(entity.get(Age).*, Age{ .value = 20 });
}
