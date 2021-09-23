const std = @import("std");
const Allocator = std.mem.Allocator;

const ecs_module = @import("ecs.zig");
const ECS = ecs_module.ECS;
const Entity = ecs_module.Entity;
const Strings = @import("strings.zig").Strings;
const components = @import("components.zig");

pub const Builtins = struct {
    U64: Entity,

    fn init(ecs: *ECS) !Builtins {
        return Builtins{
            .U64 = try ecs.createEntity(.{}),
        };
    }
};

pub const Codebase = struct {
    ecs: ECS,
    strings: Strings,
    builtins: Builtins,
    allocator: *Allocator,

    pub fn init(allocator: *Allocator) !Codebase {
        var ecs = ECS.init(allocator);
        return Codebase{
            .ecs = ecs,
            .strings = Strings.init(allocator),
            .builtins = try Builtins.init(&ecs),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Codebase) void {
        if (self.ecs.component(components.Functions)) |all_functions| {
            for (all_functions) |*functions| functions.deinit();
        }
        if (self.ecs.component(components.Body)) |bodies| {
            for (bodies) |*body| body.deinit();
        }
        self.ecs.deinit();
        self.strings.deinit();
    }
};
