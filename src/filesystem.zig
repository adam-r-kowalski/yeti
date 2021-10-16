const std = @import("std");
const Arena = std.heap.ArenaAllocator;
const panic = std.debug.panic;
const assert = std.debug.assert;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectEqualSlices = std.testing.expectEqualSlices;

const ECS = @import("ecs.zig").ECS;

const File = struct {
    bytes: []const u8,

    fn init(bytes: []const u8) File {
        return File{ .bytes = bytes };
    }
};

const Contents = struct {
    bytes: []const u8,

    fn init(bytes: []const u8) Contents {
        return Contents{ .bytes = bytes };
    }
};

test "filesystem create and lookup file" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var ecs = ECS.init(&arena);
    _ = try ecs.createEntity(.{
        File.init("beti.yeti"),
        Contents.init(
            \\fn f() u64 = 10
            \\
            \\fn g() u64 = f()
        ),
    });
}
