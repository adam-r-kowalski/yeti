const std = @import("std");

pub const ECS = @import("ecs.zig").ECS;
pub const Strings = @import("strings.zig").Strings;
pub const Codebase = @import("codebase.zig").Codebase;
pub const parse = @import("parser.zig").parse;

test "run all tests" {
    std.testing.refAllDecls(@This());
}
