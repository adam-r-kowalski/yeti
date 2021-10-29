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

pub fn List(comptime T: type, comptime config: Config) type {
    assert(config.grown_factor > 1);

    return struct {
        items: []T,
        len: u64,
        allocator: *Allocator,

        const Self = @This();

        pub fn init(allocator: *Allocator) Self {
            return Self{
                .items = &.{},
                .len = 0,
                .allocator = allocator,
            };
        }

        pub fn fromSlice(allocator: *Allocator, data: []T) !Self {
            const items = try allocator.dupe(T, data);
            return Self{
                .items = items,
                .len = data.len,
                .allocator = allocator,
            };
        }

        pub fn withCapacity(allocator: *Allocator, capacity: u64) !Self {
            const items = try allocator.alloc(T, capacity);
            return Self{
                .items = items,
                .len = 0,
                .allocator = allocator,
            };
        }

        pub fn append(self: *Self, value: T) !void {
            if (self.items.len == self.len) {
                const capacity = std.math.max(
                    self.len * config.grown_factor,
                    config.initial_capacity,
                );
                const items = try self.allocator.alloc(T, capacity);
                std.mem.copy(T, items, self.items);
                self.allocator.free(self.items);
                self.items = items;
            }
            self.items[self.len] = value;
            self.len += 1;
        }

        pub fn appendAssumeCapacity(self: *Self, value: T) void {
            assert(self.len < self.items.len);
            self.items[self.len] = value;
            self.len += 1;
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.items);
        }

        pub fn slice(self: Self) []const T {
            return self.items[0..self.len];
        }

        pub fn mutSlice(self: Self) []T {
            return self.items[0..self.len];
        }

        pub fn last(self: Self) T {
            assert(self.len > 0);
            return self.items[self.len - 1];
        }
    };
}

test "list push" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch panic("MEMORY LEAK!!!", .{});
    const allocator = &gpa.allocator;
    var list = List(i64, .{}).init(allocator);
    defer list.deinit();
    try expectEqual(list.len, 0);
    try list.append(4);
    try expectEqual(list.len, 1);
    try expectEqual(list.slice()[0], 4);
    try list.append(10);
    try expectEqual(list.len, 2);
    try expectEqual(list.slice()[0], 4);
    try expectEqual(list.slice()[1], 10);
    try list.append(7);
    try expectEqual(list.len, 3);
    try expectEqual(list.slice()[0], 4);
    try expectEqual(list.slice()[1], 10);
    try expectEqual(list.slice()[2], 7);
    const items = list.slice();
    try expectEqual(items.len, 3);
}

test "list fill initial_capacity" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch panic("MEMORY LEAK!!!", .{});
    const allocator = &gpa.allocator;
    var list = List(u64, .{}).init(allocator);
    defer list.deinit();
    const fill = 32;
    var i: u64 = 0;
    while (i < fill) : (i += 1) {
        try list.append(i);
    }
    const items = list.slice();
    try expectEqual(items.len, fill);
    i = 0;
    while (i < fill) : (i += 1) {
        try expectEqual(items[i], i);
    }
}

test "list fill double initial_capacity" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch panic("MEMORY LEAK!!!", .{});
    const allocator = &gpa.allocator;
    var list = List(u64, .{}).init(allocator);
    defer list.deinit();
    const fill = 64;
    var i: u64 = 0;
    while (i < fill) : (i += 1) {
        try list.append(i);
    }
    const items = list.slice();
    try expectEqual(items.len, fill);
    i = 0;
    while (i < fill) : (i += 1) {
        try expectEqual(items[i], i);
    }
}
