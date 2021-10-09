const std = @import("std");
const Allocator = std.mem.Allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;
const panic = std.debug.panic;
const assert = std.debug.assert;

const BUCKET_SIZE: u64 = 32;

pub fn BucketList(comptime T: type) type {
    const Node = struct {
        data: [BUCKET_SIZE]T,
        next: ?*@This(),
    };

    return struct {
        head: ?*Node,
        tail: ?*Node,
        len: u64,
        allocator: *Allocator,

        const Self = @This();

        pub fn init(allocator: *Allocator) Self {
            return Self{
                .head = null,
                .tail = null,
                .len = 0,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            var current = self.head;
            while (current) |node| {
                const next = node.next;
                self.allocator.destroy(node);
                current = next;
            }
        }

        pub fn push(self: *Self, value: T) !void {
            const index = self.len % BUCKET_SIZE;
            if (index == 0) {
                if (self.tail) |tail| {
                    const node = try self.allocator.create(Node);
                    node.* = Node{ .data = undefined, .next = null };
                    tail.next = node;
                    self.tail = tail.next;
                } else {
                    const node = try self.allocator.create(Node);
                    node.* = Node{ .data = undefined, .next = null };
                    self.head = node;
                    self.tail = node;
                }
            }
            self.tail.?.data[index] = value;
            self.len += 1;
        }

        pub fn nth(self: Self, index: u64) *const T {
            var bucket = index / BUCKET_SIZE;
            var current = self.head.?;
            while (bucket > 0) : (bucket -= 1) {
                current = current.next.?;
            }
            return &current.data[index % BUCKET_SIZE];
        }
    };
}

test "list init and deinit" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch panic("MEMORY LEAK", .{});
    const allocator = &gpa.allocator;
    var list = BucketList(u64).init(allocator);
    list.deinit();
}

test "list push 1" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch panic("MEMORY LEAK", .{});
    const allocator = &gpa.allocator;
    var list = BucketList(u64).init(allocator);
    defer list.deinit();
    try list.push(1);
    try expectEqual(list.nth(0).*, 1);
}

test "list push 50" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch panic("MEMORY LEAK", .{});
    const allocator = &gpa.allocator;
    var list = BucketList(u64).init(allocator);
    defer list.deinit();
    const elements = 1_000;
    var i: u64 = 0;
    while (i < elements) : (i += 1) {
        try list.push(i);
    }
    i = 0;
    while (i < elements) : (i += 1) {
        try expectEqual(list.nth(i).*, i);
    }
}
