const std = @import("std");
const Allocator = std.mem.Allocator;
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

        fn init(allocator: *Allocator) Self {
            return Self{
                .lookup = std.AutoHashMap(u64, u64).init(allocator),
                .data = List(T).init(allocator),
            };
        }

        fn deinit(self: *Self) void {
            self.lookup.deinit();
            self.data.deinit();
        }

        fn set(self: *Self, entity: Entity, value: T) !void {
            try self.lookup.putNoClobber(entity.uuid, self.data.len);
            try self.data.push(value);
        }

        fn get(self: Self, entity: Entity) *const T {
            const index = self.lookup.get(entity.uuid).?;
            return &self.data.data[index];
        }
    };
}

pub const ECS = struct {
    components: std.StringHashMap(u64),
    next_uuid: u64,
    allocator: *Allocator,

    pub fn init(allocator: *Allocator) ECS {
        return ECS{
            .components = std.StringHashMap(u64).init(allocator),
            .next_uuid = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ECS) void {
        var iterator = self.components.valueIterator();
        while (iterator.next()) |ptr| {
            const component_ptr = @intToPtr(*Component(u1), ptr.*);
            component_ptr.deinit();
            self.allocator.destroy(component_ptr);
        }
        self.components.deinit();
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

    pub fn getMut(self: *ECS, comptime T: type) []T {
        if (self.components.getPtr(@typeName(T))) |component| {
            return @intToPtr(*Component(T), component.*).data.slice();
        }
        return &[_]T{};
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
                const component = try self.ecs.allocator.create(Component(T));
                component.* = Component(T).init(self.ecs.allocator);
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
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch panic("MEMORY LEAK", .{});
    const allocator = &gpa.allocator;
    var ecs = ECS.init(allocator);
    defer ecs.deinit();
    const entity = try ecs.createEntity(.{});
    _ = try entity.set(.{Name{ .value = "Joe" }});
    try expectEqual(entity.get(Name).*, Name{ .value = "Joe" });
}

test "entity get and set components" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch panic("MEMORY LEAK", .{});
    const allocator = &gpa.allocator;
    var ecs = ECS.init(allocator);
    defer ecs.deinit();
    const entity = try ecs.createEntity(.{});
    _ = try entity.set(.{ Name{ .value = "Joe" }, Age{ .value = 20 } });
    try expectEqual(entity.get(Name).*, Name{ .value = "Joe" });
    try expectEqual(entity.get(Age).*, Age{ .value = 20 });
}

test "entity get and set components on creation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch panic("MEMORY LEAK", .{});
    const allocator = &gpa.allocator;
    var ecs = ECS.init(allocator);
    defer ecs.deinit();
    const entity = try ecs.createEntity(.{ Name{ .value = "Joe" }, Age{ .value = 20 } });
    try expectEqual(entity.get(Name).*, Name{ .value = "Joe" });
    try expectEqual(entity.get(Age).*, Age{ .value = 20 });
}

test "get all components of type" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch panic("MEMORY LEAK", .{});
    const allocator = &gpa.allocator;
    var ecs = ECS.init(allocator);
    defer ecs.deinit();
    _ = try ecs.createEntity(.{
        Name{ .value = "Joe" },
        Age{ .value = 20 },
    });
    _ = try ecs.createEntity(.{
        Name{ .value = "Bob" },
    });
    const names = ecs.getMut(Name);
    try expectEqual(names.len, 2);
    try expectEqualStrings(names[0].value, "Joe");
    try expectEqualStrings(names[1].value, "Bob");
}
