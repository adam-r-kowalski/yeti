const std = @import("std");
const Allocator = std.mem.Allocator;

const ecs_module = @import("ecs.zig");
const ECS = ecs_module.ECS;
const Entity = ecs_module.Entity;
const strings_module = @import("strings.zig");
const Strings = strings_module.Strings;
const InternedString = strings_module.InternedString;

pub const Codebase = struct {
    ecs: ECS,
    strings: Strings,

    pub fn init(allocator: *Allocator) !Codebase {
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
