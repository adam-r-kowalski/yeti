const std = @import("std");
const Arena = std.heap.ArenaAllocator;

const ECS = @import("ecs.zig").ECS;
const Strings = @import("strings.zig").Strings;

pub fn initCodebase(arena: *Arena) !ECS {
    var codebase = ECS.init(arena);
    try codebase.set(.{Strings.init(arena)});
    return codebase;
}
