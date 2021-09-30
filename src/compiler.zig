const std = @import("std");

pub const Codebase = @import("codebase.zig").Codebase;
pub const ECS = @import("ecs.zig").ECS;
pub const List = @import("list.zig").List;
pub const parse = @import("parser.zig").parse;
pub const Strings = @import("strings.zig").Strings;
pub const Scopes = @import("scopes.zig").Scopes;

test "run all tests" {
    std.testing.refAllDecls(@This());
}
