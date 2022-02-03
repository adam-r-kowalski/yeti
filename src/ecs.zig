const std = @import("std");
const Arena = std.heap.ArenaAllocator;
const panic = std.debug.panic;
const assert = std.debug.assert;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectEqualSlices = std.testing.expectEqualSlices;

const List = @import("list.zig").List;

pub fn typeid(comptime _: type) usize {
    const S = struct {
        var N: usize = 0;
    };
    return @ptrToInt(&S.N);
}

pub fn Component(comptime T: type) type {
    const initial_capacity = 1024;
    const Data = List(T, .{ .initial_capacity = initial_capacity });
    const Inverse = List(u64, .{ .initial_capacity = initial_capacity });

    return struct {
        lookup: std.AutoHashMap(u64, u64),
        data: Data,
        inverse: Inverse,

        const Self = @This();

        fn init(arena: *Arena) Self {
            const allocator = arena.allocator();
            return Self{
                .lookup = std.AutoHashMap(u64, u64).init(allocator),
                .data = Data.init(allocator),
                .inverse = Inverse.init(allocator),
            };
        }

        fn set(self: *Self, entity: Entity, value: T) !void {
            const result = try self.lookup.getOrPut(entity.uuid);
            if (result.found_existing) {
                self.data.items[result.value_ptr.*] = value;
            } else {
                result.value_ptr.* = self.data.len;
                try self.data.append(value);
                try self.inverse.append(entity.uuid);
            }
        }

        fn get(self: Self, entity: Entity) T {
            return self.data.slice()[self.lookup.get(entity.uuid).?];
        }

        fn has(self: Self, entity: Entity) ?T {
            if (self.lookup.get(entity.uuid)) |index| {
                return self.data.slice()[index];
            }
            return null;
        }

        fn contains(self: Self, entity: Entity) bool {
            return self.lookup.contains(entity.uuid);
        }

        fn getPtr(self: *Self, entity: Entity) *T {
            return &self.data.mutSlice()[self.lookup.get(entity.uuid).?];
        }
    };
}

const TypeInfo = std.builtin.TypeInfo;
const StructField = TypeInfo.StructField;

pub fn IteratorComponents(components: anytype) type {
    const components_type_info = @typeInfo(@TypeOf(components)).Struct;
    const components_fields = components_type_info.fields;
    comptime var data_fields: [components_fields.len]StructField = undefined;
    inline for (components_type_info.fields) |field, i| {
        const T = @field(components, field.name);
        data_fields[i] = .{
            .name = @typeName(T),
            .field_type = *Component(T),
            .default_value = null,
            .is_comptime = false,
            .alignment = 8,
        };
    }
    return @Type(.{ .Struct = .{
        .layout = .Auto,
        .fields = &data_fields,
        .decls = &.{},
        .is_tuple = false,
    } });
}

fn Iterator(components: anytype) type {
    const IteratorComponentsT = IteratorComponents(components);
    const type_info = @typeInfo(@TypeOf(components)).Struct;
    const fields = type_info.fields;

    return struct {
        iterator_components: IteratorComponentsT,
        inverse: []const u64,
        ecs: *ECS,

        const Self = @This();

        fn init(ecs: *ECS) Self {
            var iterator_components: IteratorComponentsT = undefined;
            inline for (fields) |field| {
                const T = @field(components, field.name);
                const component = ecs.components.get(typeid(T)).?;
                @field(iterator_components, @typeName(T)) = @intToPtr(*Component(T), component);
            }
            const T = components[0];
            const inverse = @intToPtr(*Component(T), ecs.components.get(typeid(T)).?).inverse.slice();
            return .{
                .iterator_components = iterator_components,
                .inverse = inverse,
                .ecs = ecs,
            };
        }

        pub fn next(self: *Self) ?Entity {
            while (self.inverse.len > 0) {
                const uuid = self.inverse[0];
                var matches = true;
                inline for (fields[1..]) |field| {
                    const T = @field(components, field.name);
                    const component = @field(self.iterator_components, @typeName(T));
                    if (!component.lookup.contains(uuid)) matches = false;
                }
                self.inverse = self.inverse[1..];
                if (matches) return Entity{ .uuid = uuid, .ecs = self.ecs };
            }
            return null;
        }
    };
}

pub const ECS = struct {
    components: std.AutoHashMap(u64, u64),
    resources: std.AutoHashMap(u64, u64),
    next_uuid: u64,
    arena: *Arena,

    pub fn init(arena: *Arena) ECS {
        const allocator = arena.allocator();
        return ECS{
            .components = std.AutoHashMap(u64, u64).init(allocator),
            .resources = std.AutoHashMap(u64, u64).init(allocator),
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
            const result = try self.resources.getOrPut(typeid(T));
            if (result.found_existing) {
                const resource = @intToPtr(*T, result.value_ptr.*);
                resource.* = @field(resources, field.name);
            } else {
                const resource = try self.arena.allocator().create(T);
                resource.* = @field(resources, field.name);
                result.value_ptr.* = @ptrToInt(resource);
            }
        }
    }

    pub fn get(self: ECS, comptime T: type) T {
        return @intToPtr(*T, self.resources.get(typeid(T)).?).*;
    }

    pub fn getPtr(self: ECS, comptime T: type) *T {
        return @intToPtr(*T, self.resources.get(typeid(T)).?);
    }

    pub fn contains(self: ECS, comptime T: type) bool {
        return self.resources.contains(typeid(T));
    }

    pub fn query(self: *ECS, components: anytype) Iterator(components) {
        return Iterator(components).init(self);
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
            const result = try self.ecs.components.getOrPut(typeid(T));
            if (result.found_existing) {
                const component = @intToPtr(*Component(T), result.value_ptr.*);
                try component.*.set(self, @field(components, field.name));
            } else {
                const component = try self.ecs.arena.allocator().create(Component(T));
                component.* = Component(T).init(self.ecs.arena);
                try component.*.set(self, @field(components, field.name));
                result.value_ptr.* = @ptrToInt(component);
            }
        }
        return self;
    }

    pub fn get(self: Entity, comptime T: type) T {
        const component = self.ecs.components.get(typeid(T)).?;
        return @intToPtr(*Component(T), component).get(self);
    }

    pub fn has(self: Entity, comptime T: type) ?T {
        if (self.ecs.components.get(typeid(T))) |component| {
            return @intToPtr(*Component(T), component).has(self);
        }
        return null;
    }

    pub fn contains(self: Entity, comptime T: type) bool {
        if (self.ecs.components.get(typeid(T))) |component| {
            return @intToPtr(*Component(T), component).contains(self);
        }
        return false;
    }

    pub fn getPtr(self: Entity, comptime T: type) *T {
        const component = self.ecs.components.get(typeid(T)).?;
        return @intToPtr(*Component(T), component).getPtr(self);
    }
};
