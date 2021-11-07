const std = @import("std");
const Arena = std.heap.ArenaAllocator;
const init_codebase = @import("init_codebase.zig");
const initCodebase = init_codebase.initCodebase;
const file_system = @import("file_system.zig");
const initFileSystem = file_system.initFileSystem;
const newFile = file_system.newFile;
const lower = @import("lower.zig").lower;
const ecs = @import("ecs.zig");
const Entity = ecs.Entity;
const ECS = ecs.ECS;
const components = @import("components.zig");

fn codegen(_: *ECS, ir: Entity) !Entity {
    return ir;
}

test "return int literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try initFileSystem(&arena);
    _ = try newFile(&fs, "foo.yeti",
        \\start = function(): I64
        \\  5
        \\end
    );
    const ir = try lower(codebase, fs, "foo.yeti", "start");
    _ = try codegen(codebase, ir);
}
