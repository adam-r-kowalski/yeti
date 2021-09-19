const std = @import("std");

const ecs = @import("ecs.zig");

test "run all tests" {
    std.testing.refAllDecls(@This());
}
