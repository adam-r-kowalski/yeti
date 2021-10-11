const std = @import("std");
const Arena = std.heap.ArenaAllocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;
const panic = std.debug.panic;
const assert = std.debug.assert;

//  TODO: [performance] make the bucket size dynamic
const BUCKET_SIZE: u64 = 32;

pub fn List(comptime T: type) type {
    const Node = struct {
        data: [BUCKET_SIZE]T,
        next: ?*@This(),
    };

    return struct {
        head: ?*Node,
        tail: ?*Node,
        len: u64,
        arena: *Arena,

        const Self = @This();

        pub fn init(arena: *Arena) Self {
            return Self{
                .head = null,
                .tail = null,
                .len = 0,
                .arena = arena,
            };
        }

        pub fn push(self: *Self, value: T) !void {
            const index = self.len % BUCKET_SIZE;
            if (index == 0) {
                if (self.tail) |tail| {
                    const node = try self.arena.allocator.create(Node);
                    node.* = Node{ .data = undefined, .next = null };
                    tail.next = node;
                    self.tail = tail.next;
                } else {
                    const node = try self.arena.allocator.create(Node);
                    node.* = Node{ .data = undefined, .next = null };
                    self.head = node;
                    self.tail = node;
                }
            }
            self.tail.?.data[index] = value;
            self.len += 1;
        }

        pub fn nth(self: Self, index: u64) T {
            assert(index < self.len);
            var bucket = index / BUCKET_SIZE;
            var current = self.head.?;
            while (bucket > 0) : (bucket -= 1) {
                current = current.next.?;
            }
            return current.data[index % BUCKET_SIZE];
        }

        pub const Iterator = struct {
            node: ?*Node,
            i: u64,
            len: u64,

            pub fn next(self: *@This()) ?T {
                if (self.len == 0) return null;
                const node = self.node.?;
                const value = node.data[self.i];
                self.i += 1;
                if (self.i == BUCKET_SIZE) {
                    self.node = node.next;
                    self.i = 0;
                }
                self.len -= 1;
                return value;
            }

            pub fn peek(self: @This()) ?T {
                if (self.len == 0) return null;
                const node = self.node.?;
                return node.data[self.i];
            }
        };

        pub fn iterate(self: Self) Iterator {
            return Iterator{
                .node = self.head,
                .i = 0,
                .len = self.len,
            };
        }
    };
}

test "list push 1" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var list = List(u64).init(&arena);
    try list.push(1);
    try expectEqual(list.nth(0), 1);
}

test "list push 50" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var list = List(u64).init(&arena);
    const elements = 1_000;
    var i: u64 = 0;
    while (i < elements) : (i += 1) {
        try list.push(i);
    }
    i = 0;
    while (i < elements) : (i += 1) {
        try expectEqual(list.nth(i), i);
    }
}

test "list iterate" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var list = List(u64).init(&arena);
    const elements = 1_000;
    var i: u64 = 0;
    while (i < elements) : (i += 1) {
        try list.push(i);
    }
    var iterator = list.iterate();
    i = 0;
    while (i < elements) : (i += 1) {
        try expectEqual(iterator.peek().?, i);
        try expectEqual(iterator.next().?, i);
    }
    try expectEqual(iterator.next(), null);
}
