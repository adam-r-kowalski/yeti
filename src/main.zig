const std = @import("std");
const compiler = @import("compiler");

pub fn main() anyerror!void {
    std.log.info("All your codebase are belong to us.", .{});
    std.log.info("{}", .{compiler.foo()});
}
