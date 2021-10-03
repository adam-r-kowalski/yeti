const std = @import("std");
const Allocator = std.mem.Allocator;

const ecs_module = @import("ecs.zig");
const ECS = ecs_module.ECS;
const Entity = ecs_module.Entity;
const strings_module = @import("strings.zig");
const Strings = strings_module.Strings;
const InternedString = strings_module.InternedString;
const components = @import("components.zig");
const Body = components.Body;

pub const Codebase = struct {
    ecs: ECS,
    strings: Strings,
    allocator: *Allocator,

    pub fn init(allocator: *Allocator) !Codebase {
        return Codebase{
            .ecs = ECS.init(allocator),
            .strings = Strings.init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Codebase) void {
        for (self.ecs.getMut(Body)) |*body| {
            body.expressions.deinit();
        }
        self.ecs.deinit();
        self.strings.deinit();
    }
};
