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
    const Data = List(T, .{ .bucket_size = 1024 });

    return struct {
        lookup: std.AutoHashMap(u64, u64),
        data: Data,

        const Self = @This();

        fn init(arena: *Arena) Self {
            return Self{
                .lookup = std.AutoHashMap(u64, u64).init(&arena.allocator),
                .data = Data.init(arena),
            };
        }

        fn set(self: *Self, entity: Entity, value: T) !void {
            try self.lookup.putNoClobber(entity.uuid, self.data.len);
            try self.data.push(value);
        }

        fn get(self: Self, entity: Entity) T {
            return self.data.nth(self.lookup.get(entity.uuid).?);
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

    pub fn set(self: *ECS, resources: anytype) !void {
        const type_info = @typeInfo(@TypeOf(resources)).Struct;
        assert(type_info.is_tuple);
        inline for (type_info.fields) |field| {
            const T = field.field_type;
            const result = try self.resources.getOrPut(@typeName(T));
            if (result.found_existing) {
                const resource = @intToPtr(*T, result.value_ptr.*);
                resource.* = @field(resources, field.name);
            } else {
                const resource = try self.arena.allocator.create(T);
                resource.* = @field(resources, field.name);
                result.value_ptr.* = @ptrToInt(resource);
            }
        }
    }

    pub fn get(self: ECS, comptime T: type) T {
        return @intToPtr(*T, self.resources.get(@typeName(T)).?).*;
    }

    pub fn getPtr(self: ECS, comptime T: type) *T {
        return @intToPtr(*T, self.resources.get(@typeName(T)).?);
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

    pub fn get(self: Entity, comptime T: type) T {
        const component = self.ecs.components.get(@typeName(T)).?;
        return @intToPtr(*Component(T), component).get(self);
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
    try expectEqual(entity.get(Name), Name{ .value = "Joe" });
}

test "entity get and set components" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var ecs = ECS.init(&arena);
    const entity = try ecs.createEntity(.{});
    _ = try entity.set(.{ Name{ .value = "Joe" }, Age{ .value = 20 } });
    try expectEqual(entity.get(Name), Name{ .value = "Joe" });
    try expectEqual(entity.get(Age), Age{ .value = 20 });
}

test "entity get and set components on creation" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var ecs = ECS.init(&arena);
    const entity = try ecs.createEntity(.{ Name{ .value = "Joe" }, Age{ .value = 20 } });
    try expectEqual(entity.get(Name), Name{ .value = "Joe" });
    try expectEqual(entity.get(Age), Age{ .value = 20 });
}

test "ecs get and set components" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var ecs = ECS.init(&arena);
    try ecs.set(.{ Name{ .value = "Joe" }, Age{ .value = 20 } });
    try expectEqual(ecs.get(Name), Name{ .value = "Joe" });
    try expectEqual(ecs.get(Age), Age{ .value = 20 });
}
