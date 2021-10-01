const std = @import("std");
const Allocator = std.mem.Allocator;

const ecs_module = @import("ecs.zig");
const ECS = ecs_module.ECS;
const Entity = ecs_module.Entity;
const strings_module = @import("strings.zig");
const Strings = strings_module.Strings;
const InternedString = strings_module.InternedString;
const components = @import("components.zig");

pub const Scope = std.AutoHashMap(InternedString, Entity);

pub const Builtins = struct {
    Type: Entity,
    U64: Entity,
    scope: Scope,

    fn init(allocator: *Allocator, ecs: *ECS, strings: *Strings) !Builtins {
        var scope = Scope.init(allocator);
        const Type = blk: {
            const interned = try strings.intern("type");
            const name = components.Name{ .interned = interned };
            const entity = try ecs.createEntity(.{name});
            const type_component = components.Type{ .entity = entity };
            _ = try entity.set(.{type_component});
            try scope.putNoClobber(interned, entity);
            break :blk entity;
        };
        const U64 = blk: {
            const interned = try strings.intern("u64");
            const name = components.Name{ .interned = interned };
            const type_component = components.Type{ .entity = Type };
            const entity = try ecs.createEntity(.{ name, type_component });
            try scope.putNoClobber(interned, entity);
            break :blk entity;
        };
        return Builtins{
            .Type = Type,
            .U64 = U64,
            .scope = scope,
        };
    }

    fn deinit(self: *Builtins) void {
        self.scope.deinit();
    }
};

pub const Codebase = struct {
    ecs: ECS,
    strings: Strings,
    builtins: Builtins,
    allocator: *Allocator,

    pub fn init(allocator: *Allocator) !Codebase {
        var ecs = ECS.init(allocator);
        var strings = Strings.init(allocator);
        const builtins = try Builtins.init(allocator, &ecs, &strings);
        return Codebase{
            .ecs = ecs,
            .strings = strings,
            .builtins = builtins,
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
        self.builtins.deinit();
    }
};
