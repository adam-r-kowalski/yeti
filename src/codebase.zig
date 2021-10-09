const std = @import("std");
const Arena = std.heap.ArenaAllocator;

const ecs_module = @import("ecs.zig");
const ECS = ecs_module.ECS;
const Entity = ecs_module.Entity;
const strings_module = @import("strings.zig");
const Strings = strings_module.Strings;
const InternedString = strings_module.InternedString;
const components = @import("components.zig");
const Body = components.Body;
const Parameters = components.Parameters;

// TODO(ergonomics): change ecs to have a "resource" api
// move strings into the ecs as a resource
// move allocator into the ecs as a resource
// add a arena into the ecs for local allocations
pub const Codebase = struct {
    ecs: ECS,
    strings: Strings,
    arena: *Arena,

    pub fn init(arena: *Arena) Codebase {
        return Codebase{
            .ecs = ECS.init(arena),
            .strings = Strings.init(arena),
            .arena = arena,
        };
    }
};
