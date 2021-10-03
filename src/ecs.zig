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

        fn get(self: Self, entity: Entity) ?*const T {
            if (self.lookup.get(entity.uuid)) |index| {
                return &self.data.data[index];
            }
            return null;
        }

        fn share(self: *Self, entity: Entity, with: Entity) !void {
            const index = self.lookup.get(with.uuid).?;
            try self.lookup.putNoClobber(entity.uuid, index);
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
};

fn Query(comptime components: anytype) type {
    const components_fields = @typeInfo(@TypeOf(components)).Struct.fields;
    var fields: [components_fields.len]TypeInfo.StructField = undefined;
    inline for (components_fields) |field, i| {
        const T = @field(components, field.name);
        fields[i] = TypeInfo.StructField{
            .name = @typeName(T),
            .field_type = *const T,
            .default_value = null,
            .is_comptime = false,
            .alignment = 8,
        };
    }
    return @Type(TypeInfo{ .Struct = .{
        .layout = TypeInfo.ContainerLayout.Auto,
        .fields = &fields,
        .decls = &[_]TypeInfo.Declaration{},
        .is_tuple = false,
    } });
}

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

    pub fn get(self: Entity, comptime T: type) ?*const T {
        if (self.ecs.components.getPtr(@typeName(T))) |component| {
            return @intToPtr(*Component(T), component.*).get(self);
        } else {
            return null;
        }
    }

    pub fn query(self: Entity, comptime components: anytype) ?Query(components) {
        var result: Query(components) = undefined;
        var found = true;
        const type_info = @typeInfo(@TypeOf(components)).Struct;
        assert(type_info.is_tuple);
        inline for (type_info.fields) |field| {
            const T = @field(components, field.name);
            if (self.get(T)) |component| {
                @field(result, @typeName(T)) = component;
            } else {
                found = false;
            }
        }
        if (!found) {
            return null;
        } else {
            return result;
        }
    }

    pub fn share(self: Entity, comptime T: type, with: Entity) !void {
        const component = self.ecs.components.getPtr(@typeName(T)).?;
        try @intToPtr(*Component(T), component.*).share(self, with);
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
    try expectEqual(entity.get(Name), null);
    _ = try entity.set(.{Name{ .value = "Joe" }});
    try expectEqual(entity.get(Name).?.*, Name{ .value = "Joe" });
}

test "entity get and set components" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch panic("MEMORY LEAK", .{});
    const allocator = &gpa.allocator;
    var ecs = ECS.init(allocator);
    defer ecs.deinit();
    const entity = try ecs.createEntity(.{});
    _ = try entity.set(.{ Name{ .value = "Joe" }, Age{ .value = 20 } });
    try expectEqual(entity.get(Name).?.*, Name{ .value = "Joe" });
    try expectEqual(entity.get(Age).?.*, Age{ .value = 20 });
}

test "entity get and set components on creation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch panic("MEMORY LEAK", .{});
    const allocator = &gpa.allocator;
    var ecs = ECS.init(allocator);
    defer ecs.deinit();
    const entity = try ecs.createEntity(.{ Name{ .value = "Joe" }, Age{ .value = 20 } });
    try expectEqual(entity.get(Name).?.*, Name{ .value = "Joe" });
    try expectEqual(entity.get(Age).?.*, Age{ .value = 20 });
}

test "query" {
    const type_info = @typeInfo(Query(.{ Name, Age })).Struct;
    try expectEqual(type_info.layout, TypeInfo.ContainerLayout.Auto);
    try expectEqual(type_info.fields.len, 2);
    try expectEqual(type_info.fields[0], .{
        .name = "Name",
        .field_type = *const Name,
        .default_value = null,
        .is_comptime = false,
        .alignment = 8,
    });
    try expectEqual(type_info.fields[1], .{
        .name = "Age",
        .field_type = *const Age,
        .default_value = null,
        .is_comptime = false,
        .alignment = 8,
    });
    try expectEqualSlices(TypeInfo.Declaration, type_info.decls, &[_]TypeInfo.Declaration{});
    try expectEqual(type_info.is_tuple, false);
}

test "entity query components" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch panic("MEMORY LEAK", .{});
    const allocator = &gpa.allocator;
    var ecs = ECS.init(allocator);
    defer ecs.deinit();
    const entity = try ecs.createEntity(.{});
    try expectEqual(entity.query(.{ Name, Age }), null);
    _ = try entity.set(.{Name{ .value = "Joe" }});
    try expectEqual(entity.query(.{ Name, Age }), null);
    _ = try entity.set(.{Age{ .value = 20 }});
    const query = entity.query(.{ Name, Age }).?;
    try expectEqual(query.Name.*, Name{ .value = "Joe" });
    try expectEqual(query.Age.*, Age{ .value = 20 });
}

test "share components between entities" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch panic("MEMORY LEAK", .{});
    const allocator = &gpa.allocator;
    var ecs = ECS.init(allocator);
    defer ecs.deinit();
    const entity1 = try ecs.createEntity(.{
        Name{ .value = "Joe" },
        Age{ .value = 20 },
    });
    const entity2 = try ecs.createEntity(.{});
    try entity2.share(Name, entity1);
    try expectEqual(entity1.get(Name).?.*, Name{ .value = "Joe" });
    try expectEqual(entity2.get(Name).?.*, Name{ .value = "Joe" });
}
