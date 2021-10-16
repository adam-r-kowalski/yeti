const std = @import("std");
const Arena = std.heap.ArenaAllocator;
const panic = std.debug.panic;
const assert = std.debug.assert;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectEqualSlices = std.testing.expectEqualSlices;

const ECS = @import("ecs.zig").ECS;

test "ecs get and set components" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var ecs = ECS.init(&arena);
    const file = ecs.createEntity(.{
        File.init("beti.yeti"),
        Contents.init(
            \\fn f() u64 = 0
            \\
            \\fn g() u64 = 0
        ),
    });
}
