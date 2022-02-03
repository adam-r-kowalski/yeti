const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const panic = std.debug.panic;

const yeti = @import("yeti");
const List = yeti.List;

test "list push" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch panic("MEMORY LEAK!!!", .{});
    var list = List(i64, .{}).init(gpa.allocator());
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
    var list = List(u64, .{}).init(gpa.allocator());
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
    var list = List(u64, .{}).init(gpa.allocator());
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

test "list appendSlice" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch panic("MEMORY LEAK!!!", .{});
    var list = List(u8, .{ .initial_capacity = 2 }).init(gpa.allocator());
    defer list.deinit();
    try list.appendSlice("hello");
    try expectEqual(list.len, 5);
    try expectEqual(list.items.len, 8);
    try expectEqualStrings(list.slice(), "hello");
    try list.appendSlice(" world");
    try expectEqual(list.len, 11);
    try expectEqual(list.items.len, 20);
    try expectEqualStrings(list.slice(), "hello world");
}
