const std = @import("std");
const Arena = std.heap.ArenaAllocator;

const ECS = @import("ecs.zig").ECS;
const Strings = @import("strings.zig").Strings;

pub fn initCodebase(arena: *Arena) !ECS {
    var ecs = ECS.init(arena);
    try ecs.set(.{Strings.init(arena)});
    return ecs;
}
