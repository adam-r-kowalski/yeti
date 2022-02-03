const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const Arena = std.heap.ArenaAllocator;
const eql = std.meta.eql;

const yeti = @import("yeti");
const Strings = yeti.Strings;

test "intern a string" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var strings = Strings.init(&arena);
    const joe = try strings.intern("Joe");
    const bob = try strings.intern("Bob");
    try expect(!eql(joe, bob));
    const joe_again = try strings.intern("Joe");
    try expectEqual(joe, joe_again);
    const bob_again = try strings.intern("Bob");
    try expectEqual(bob, bob_again);
    try expectEqualStrings(strings.get(joe), "Joe");
}
