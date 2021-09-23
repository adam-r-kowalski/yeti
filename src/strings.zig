const std = @import("std");
const Allocator = std.mem.Allocator;
const panic = std.debug.panic;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const eql = std.meta.eql;

const List = @import("list.zig").List;

pub const InternedString = struct {
    value: u64,
};

pub const Strings = struct {
    lookup: std.StringHashMap(InternedString),
    inverse: List([]const u8),
    next: InternedString,
    allocator: *Allocator,

    pub fn init(allocator: *Allocator) Strings {
        return Strings{
            .lookup = std.StringHashMap(InternedString).init(allocator),
            .inverse = List([]const u8).init(allocator),
            .next = InternedString{ .value = 0 },
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Strings) void {
        self.lookup.deinit();
        for (self.inverse.slice()) |string| {
            self.allocator.free(string);
        }
        self.inverse.deinit();
    }

    pub fn intern(self: *Strings, value: []const u8) !InternedString {
        const result = try self.lookup.getOrPut(value);
        if (result.found_existing) {
            return result.value_ptr.*;
        } else {
            const interned = self.next;
            result.value_ptr.* = interned;
            self.next.value += 1;
            try self.inverse.push(try self.allocator.dupe(u8, value));
            return interned;
        }
    }

    pub fn get(self: Strings, interned: InternedString) ?[]const u8 {
        if (self.inverse.nth(interned.value)) |ptr| {
            return ptr.*;
        }
        return null;
    }
};

test "intern a string" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch panic("MEMORY LEAK", .{});
    const allocator = &gpa.allocator;
    var strings = Strings.init(allocator);
    defer strings.deinit();
    const joe = try strings.intern("Joe");
    const bob = try strings.intern("Bob");
    try expect(!eql(joe, bob));
    const joe_again = try strings.intern("Joe");
    try expectEqual(joe, joe_again);
    const bob_again = try strings.intern("Bob");
    try expectEqual(bob, bob_again);
    try expectEqualStrings(strings.get(joe).?, "Joe");
}
