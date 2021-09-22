const std = @import("std");
const Allocator = std.mem.Allocator;
const expect = std.testing.expect;
const expectEqualSlices = std.testing.expectEqualSlices;
const panic = std.debug.panic;

fn List(comptime T: type) type {
    return struct {
        data: []T,
        len: u64,
        allocator: *Allocator,

        const Self = @This();

        fn init(allocator: *Allocator) Self {
            return Self{
                .data = &.{},
                .len = 0,
                .allocator = allocator,
            };
        }

        fn deinit(self: *Self) void {
            self.allocator.free(self.data);
        }

        fn push(self: *Self, value: T) !void {
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

        fn slice(self: Self) []const T {
            return self.data[0..self.len];
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
