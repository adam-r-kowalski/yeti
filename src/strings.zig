const std = @import("std");
const Arena = std.heap.ArenaAllocator;
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
    const Inverse = List([]const u8, .{ .initial_capacity = 1024 });

    lookup: std.StringHashMap(InternedString),
    inverse: Inverse,
    next: InternedString,
    arena: *Arena,

    pub fn init(arena: *Arena) Strings {
        const allocator = arena.allocator();
        return Strings{
            .lookup = std.StringHashMap(InternedString).init(allocator),
            .inverse = Inverse.init(allocator),
            .next = InternedString{ .value = 0 },
            .arena = arena,
        };
    }

    pub fn intern(self: *Strings, string: []const u8) !InternedString {
        const result = try self.lookup.getOrPut(string);
        if (result.found_existing) {
            return result.value_ptr.*;
        } else {
            const interned = self.next;
            result.value_ptr.* = interned;
            self.next.value += 1;
            try self.inverse.append(try self.arena.allocator().dupe(u8, string));
            return interned;
        }
    }

    pub fn get(self: Strings, interned: InternedString) []const u8 {
        return self.inverse.slice()[interned.value];
    }
};
