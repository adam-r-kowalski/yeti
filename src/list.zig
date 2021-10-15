const std = @import("std");
const Allocator = std.mem.Allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;
const panic = std.debug.panic;
const assert = std.debug.assert;

pub const Config = struct {
    initial_capacity: u64 = 32,
    grown_factor: u64 = 2,
};

pub fn List(comptime T: type) type {
    return struct {
        items: []T,
        len: u64,
        allocator: *Allocator,
        config: Config,

        const Self = @This();

        pub fn init(allocator: *Allocator, config: Config) Self {
            return Self{
                .items = &[_]T{},
                .len = 0,
                .allocator = allocator,
                .config = config,
            };
        }

        pub fn append(self: *Self, value: T) !void {
            if (self.items.len == self.len) {
                const capacity = std.math.max(
                    self.len * self.config.grown_factor,
                    self.config.initial_capacity,
                );
                const items = try self.allocator.alloc(T, capacity);
                std.mem.copy(T, items, self.items);
                self.allocator.free(self.items);
                self.items = items;
            }
            self.items[self.len] = value;
            self.len += 1;
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.items);
        }

        pub fn slice(self: Self) []T {
            return self.items[0..self.len];
        }
    };
}

test "list push" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch panic("MEMORY LEAK!!!", .{});
    const allocator = &gpa.allocator;
    var list = List(i64).init(allocator, .{ .initial_capacity = 2 });
    defer list.deinit();
    try expectEqual(list.len, 0);
    try list.append(4);
    try expectEqual(list.len, 1);
    try expectEqual(list.items[0], 4);
    try list.append(10);
    try expectEqual(list.len, 2);
    try expectEqual(list.items[0], 4);
    try expectEqual(list.items[1], 10);
    try list.append(7);
    try expectEqual(list.len, 3);
    try expectEqual(list.items[0], 4);
    try expectEqual(list.items[1], 10);
    try expectEqual(list.items[2], 7);
    try expectEqual(list.items.len, 4);
    const items = list.slice();
    try expectEqual(items.len, 3);
}
