const std = @import("std");
const Allocator = std.mem.Allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;
const panic = std.debug.panic;

pub fn List(comptime T: type) type {
    const Iterator = struct {
        data: []const T,
        index: u64,

        pub fn next(self: *@This()) ?*const T {
            if (self.index < self.data.len) {
                const index = self.index;
                self.index += 1;
                return &self.data[index];
            }
            return null;
        }
    };

    return struct {
        data: []T,
        len: u64,
        allocator: *Allocator,

        const Self = @This();

        pub fn init(allocator: *Allocator) Self {
            return Self{
                .data = &.{},
                .len = 0,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.data);
        }

        pub fn push(self: *Self, value: T) !void {
            if (self.data.len == self.len) {
                const capacity = std.math.max(32, 2 * self.data.len);
                const data = try self.allocator.alloc(T, capacity);
                std.mem.copy(T, data, self.data);
                self.allocator.free(self.data);
                self.data = data;
            }
            self.data[self.len] = value;
            self.len += 1;
        }

        pub fn slice(self: Self) []const T {
            return self.data[0..self.len];
        }

        pub fn iterate(self: Self) Iterator {
            return Iterator{
                .data = self.slice(),
                .index = 0,
            };
        }
    };
}

test "list push" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch panic("MEMORY LEAK", .{});
    const allocator = &gpa.allocator;
    var list = List(u64).init(allocator);
    defer list.deinit();
    try list.push(10);
    try list.push(20);
    try expectEqualSlices(u64, list.slice(), &.{ 10, 20 });
}

test "list iterate" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch panic("MEMORY LEAK", .{});
    const allocator = &gpa.allocator;
    var list = List(u64).init(allocator);
    defer list.deinit();
    try list.push(10);
    try list.push(20);
    var iterator = list.iterate();
    try expectEqual(iterator.next().?.*, 10);
    try expectEqual(iterator.next().?.*, 20);
    try expectEqual(iterator.next(), null);
}
