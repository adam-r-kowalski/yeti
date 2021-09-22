const std = @import("std");
const Allocator = std.mem.Allocator;

const ECS = @import("ecs.zig").ECS;
const Strings = @import("strings.zig").Strings;
const components = @import("components.zig");

pub const Codebase = struct {
    ecs: ECS,
    strings: Strings,
    allocator: *Allocator,

    pub fn init(allocator: *Allocator) Codebase {
        return Codebase{
            .ecs = ECS.init(allocator),
            .strings = Strings.init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Codebase) void {
        if (self.ecs.component(components.Functions)) |functions| {
            for (functions) |*component| component.entities.deinit();
        }
        self.ecs.deinit();
        self.strings.deinit();
    }
};
