const std = @import("std");
const Allocator = std.mem.Allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

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

    fn new(self: *ECS) Entity {
        const uuid = self.next_uuid;
        self.next_uuid += 1;
        return Entity{
            .uuid = uuid,
            .ecs = self,
        };
    }
};

const Entity = struct {
    uuid: u64,
    ecs: *ECS,

    fn set(self: Entity, value: anytype) !void {
        const T = @TypeOf(value);
        const result = try self.ecs.components.getOrPut(@typeName(T));
        if (result.found_existing) {
            try @intToPtr(*Component(T), result.value_ptr.*).*.set(self, value);
        } else {
            const component = try self.ecs.allocator.create(Component(T));
            component.* = Component(T).init(self.ecs.allocator);
            try component.*.set(self, value);
            result.value_ptr.* = @ptrToInt(component);
        }
    }

    fn get(self: Entity, comptime T: type) ?*const T {
        if (self.ecs.components.getPtr(@typeName(T))) |component| {
            return @intToPtr(*Component(T), component.*).get(self);
        } else {
            return null;
        }
    }
};

test "entity get and set component" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch @panic("MEMORY LEAK");
    const allocator = &gpa.allocator;
    var ecs = ECS.init(allocator);
    defer ecs.deinit();
    const entity = ecs.new();
    try expectEqual(entity.get(u64), null);
    try entity.set(@as(u64, 10));
    try expectEqual(entity.get(u64).?.*, 10);
    try entity.set(@as(u64, 20));
    try expectEqual(entity.get(u64).?.*, 20);
}
