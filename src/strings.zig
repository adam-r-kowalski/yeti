const std = @import("std");
const Allocator = std.mem.Allocator;
const panic = std.debug.panic;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const eql = std.meta.eql;

const InternedString = struct {
    value: u64,
};

pub const Strings = struct {
    lookup: std.StringHashMap(InternedString),
    next: InternedString,
    allocator: *Allocator,

    pub fn init(allocator: *Allocator) Strings {
        return Strings{
            .lookup = std.StringHashMap(InternedString).init(allocator),
            .next = InternedString{ .value = 0 },
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Strings) void {
        self.lookup.deinit();
    }

    pub fn intern(self: *Strings, value: []const u8) !InternedString {
        const result = try self.lookup.getOrPut(value);
        if (result.found_existing) {
            return result.value_ptr.*;
        } else {
            const interned = self.next;
            result.value_ptr.* = interned;
            self.next.value += 1;
            return interned;
        }
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
}
