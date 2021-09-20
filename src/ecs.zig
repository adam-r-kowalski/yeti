const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectEqualSlices = std.testing.expectEqualSlices;
const TypeInfo = std.builtin.TypeInfo;

fn Component(comptime T: type) type {
    return struct {
        data: []T,
        lookup: std.AutoHashMap(u64, u64),
        inverse: []u64,
        len: u64,
        allocator: *Allocator,

        const Self = @This();

        fn init(allocator: *Allocator) Self {
            return Self{
                .data = &[_]T{},
                .lookup = std.AutoHashMap(u64, u64).init(allocator),
                .inverse = &[_]u64{},
                .len = 0,
                .allocator = allocator,
            };
        }

        fn deinit(self: *Self) void {
            self.allocator.free(self.data);
            self.allocator.free(self.inverse);
            self.lookup.deinit();
        }

        fn set(self: *Self, entity: Entity, value: T) !void {
            const result = try self.lookup.getOrPut(entity.uuid);
            if (result.found_existing) {
                self.data[result.value_ptr.*] = value;
            } else {
                var capacity = self.data.len;
                if (self.len == capacity) {
                    capacity = std.math.max(32, capacity * 2);
                    const data = try self.allocator.alloc(T, capacity);
                    std.mem.copy(T, data, self.data);
                    self.allocator.free(self.data);
                    self.data = data;
                    const inverse = try self.allocator.alloc(u64, capacity);
                    std.mem.copy(u64, inverse, self.inverse);
                    self.allocator.free(self.inverse);
                    self.inverse = inverse;
                }
                self.data[self.len] = value;
                self.inverse[self.len] = entity.uuid;
                result.value_ptr.* = self.len;
                self.len += 1;
            }
        }

        fn get(self: Self, entity: Entity) ?*const T {
            if (self.lookup.get(entity.uuid)) |index| {
                return &self.data[index];
            }
            return null;
        }
    };
}

fn Iterator(comptime components: anytype) type {
    const type_info = @typeInfo(@TypeOf(components)).Struct;
    assert(type_info.is_tuple);
    const components_fields = type_info.fields;

    const ComponentData = blk: {
        var fields: [components_fields.len]TypeInfo.StructField = undefined;
        inline for (components_fields) |field, i| {
            const T = @field(components, field.name);
            const ComponentT = Component(T);
            fields[i] = TypeInfo.StructField{
                .name = @typeName(T),
                .field_type = ComponentT,
                .default_value = null,
                .is_comptime = false,
                .alignment = @alignOf(ComponentT),
            };
        }
        break :blk @Type(TypeInfo{ .Struct = .{
            .layout = TypeInfo.ContainerLayout.Auto,
            .fields = &fields,
            .decls = &[_]TypeInfo.Declaration{},
            .is_tuple = false,
        } });
    };

    const EntryData = blk: {
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
        break :blk @Type(TypeInfo{ .Struct = .{
            .layout = TypeInfo.ContainerLayout.Auto,
            .fields = &fields,
            .decls = &[_]TypeInfo.Declaration{},
            .is_tuple = false,
        } });
    };

    const Entry = struct {
        entity: Entity,
        data: EntryData,
    };

    return struct {
        data: ComponentData,
        index: u64,
        ecs: *ECS,

        const Self = @This();

        fn init(ecs: *ECS) Self {
            var data: ComponentData = undefined;
            inline for (type_info.fields) |field| {
                const T = @field(components, field.name);
                const name = @typeName(T);
                if (ecs.components.getPtr(name)) |component| {
                    @field(data, name) = @intToPtr(*Component(T), component.*).*;
                } else {
                    @field(data, name) = Component(T).init(ecs.allocator);
                }
            }
            return Self{
                .data = data,
                .index = 0,
                .ecs = ecs,
            };
        }

        fn next(self: *Self) ?Entry {
            const component = @field(self.data, @typeName(@field(components, components_fields[0].name)));
            while (self.index < component.data.len) {
                var data: EntryData = undefined;
                const entity = Entity{ .uuid = component.inverse[self.index], .ecs = self.ecs };
                var found = true;
                inline for (type_info.fields) |field| {
                    const T = @field(components, field.name);
                    const name = @typeName(T);
                    if (self.ecs.components.getPtr(name)) |c| {
                        if (@intToPtr(*Component(T), c.*).get(entity)) |value| {
                            @field(data, name) = value;
                        } else {
                            found = false;
                        }
                    }
                }
                self.index += 1;
                if (found) {
                    return Entry{
                        .entity = entity,
                        .data = data,
                    };
                }
            }
            return null;
        }
    };
}

const ECS = struct {
    components: std.StringHashMap(u64),
    next_uuid: u64,
    allocator: *Allocator,

    fn init(allocator: *Allocator) ECS {
        return ECS{
            .components = std.StringHashMap(u64).init(allocator),
            .next_uuid = 0,
            .allocator = allocator,
        };
    }

    fn deinit(self: *ECS) void {
        var iterator = self.components.valueIterator();
        while (iterator.next()) |ptr| {
            const component = @intToPtr(*Component(u1), ptr.*);
            component.deinit();
            self.allocator.destroy(component);
        }
        self.components.deinit();
    }

    fn create_entity(self: *ECS, components: anytype) !Entity {
        const uuid = self.next_uuid;
        self.next_uuid += 1;
        const entity = Entity{
            .uuid = uuid,
            .ecs = self,
        };
        return try entity.set(components);
    }

    fn iterate(self: *ECS, comptime components: anytype) Iterator(components) {
        return Iterator(components).init(self);
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

const Entity = struct {
    uuid: u64,
    ecs: *ECS,

    fn set(self: Entity, components: anytype) !Entity {
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

    fn get(self: Entity, comptime T: type) ?*const T {
        if (self.ecs.components.getPtr(@typeName(T))) |component| {
            return @intToPtr(*Component(T), component.*).get(self);
        } else {
            return null;
        }
    }

    fn query(entity: Entity, comptime components: anytype) ?Query(components) {
        var result: Query(components) = undefined;
        var found = true;
        const type_info = @typeInfo(@TypeOf(components)).Struct;
        assert(type_info.is_tuple);
        inline for (type_info.fields) |field| {
            const T = @field(components, field.name);
            if (entity.get(T)) |component| {
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
    defer expect(!gpa.deinit()) catch @panic("MEMORY LEAK");
    const allocator = &gpa.allocator;
    var ecs = ECS.init(allocator);
    defer ecs.deinit();
    const entity = try ecs.create_entity(.{});
    try expectEqual(entity.get(Name), null);
    _ = try entity.set(.{Name{ .value = "Joe" }});
    try expectEqual(entity.get(Name).?.*, Name{ .value = "Joe" });
    _ = try entity.set(.{Name{ .value = "Bob" }});
    try expectEqual(entity.get(Name).?.*, Name{ .value = "Bob" });
}

test "entity get and set components" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch @panic("MEMORY LEAK");
    const allocator = &gpa.allocator;
    var ecs = ECS.init(allocator);
    defer ecs.deinit();
    const entity = try ecs.create_entity(.{});
    _ = try entity.set(.{ Name{ .value = "Joe" }, Age{ .value = 20 } });
    try expectEqual(entity.get(Name).?.*, Name{ .value = "Joe" });
    try expectEqual(entity.get(Age).?.*, Age{ .value = 20 });
}

test "entity get and set components on creation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch @panic("MEMORY LEAK");
    const allocator = &gpa.allocator;
    var ecs = ECS.init(allocator);
    defer ecs.deinit();
    const entity = try ecs.create_entity(.{ Name{ .value = "Joe" }, Age{ .value = 20 } });
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
    defer expect(!gpa.deinit()) catch @panic("MEMORY LEAK");
    const allocator = &gpa.allocator;
    var ecs = ECS.init(allocator);
    defer ecs.deinit();
    const entity = try ecs.create_entity(.{});
    try expectEqual(entity.query(.{ Name, Age }), null);
    _ = try entity.set(.{Name{ .value = "Joe" }});
    try expectEqual(entity.query(.{ Name, Age }), null);
    _ = try entity.set(.{Age{ .value = 20 }});
    const query = entity.query(.{ Name, Age }).?;
    try expectEqual(query.Name.*, Name{ .value = "Joe" });
    try expectEqual(query.Age.*, Age{ .value = 20 });
}

test "iterate components" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch @panic("MEMORY LEAK");
    const allocator = &gpa.allocator;
    var ecs = ECS.init(allocator);
    defer ecs.deinit();
    _ = try ecs.create_entity(.{ Name{ .value = "Joe" }, Age{ .value = 20 } });
    _ = try ecs.create_entity(.{ Name{ .value = "Sally" }, Job{ .value = "Cook" } });
    _ = try ecs.create_entity(.{ Name{ .value = "Bob" }, Age{ .value = 30 }, Job{ .value = "Sales Rep" } });
    var iterator = ecs.iterate(.{ Name, Job });
    {
        const entry = iterator.next().?;
        try expectEqual(entry.data.Name.*, Name{ .value = "Sally" });
        try expectEqual(entry.data.Job.*, Job{ .value = "Cook" });
        try expectEqual(entry.entity.get(Age), null);
    }
    {
        const entry = iterator.next().?;
        try expectEqual(entry.data.Name.*, Name{ .value = "Bob" });
        try expectEqual(entry.data.Job.*, Job{ .value = "Sales Rep" });
        try expectEqual(entry.entity.get(Age).?.*, Age{ .value = 30 });
    }
    try expectEqual(iterator.next(), null);
}
