const std = @import("std");
const Allocator = std.mem.Allocator;

const ECS = @import("ecs.zig").ECS;
const Strings = @import("strings.zig").Strings;

pub const Codebase = struct {
    ecs: ECS,
    strings: Strings,

    pub fn init(allocator: *Allocator) Codebase {
        return Codebase{
            .ecs = ECS.init(allocator),
            .strings = Strings.init(allocator),
        };
    }

    pub fn deinit(self: *Codebase) void {
        self.ecs.deinit();
        self.strings.deinit();
    }
};
