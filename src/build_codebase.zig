const std = @import("std");
const Arena = std.heap.ArenaAllocator;
const assert = std.debug.assert;
const panic = std.debug.panic;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const initCodebase = @import("init_codebase.zig").initCodebase;
const List = @import("list.zig").List;
const ecs = @import("ecs.zig");
const Entity = ecs.Entity;
const ECS = ecs.ECS;
const strings = @import("strings.zig");
const Strings = strings.Strings;
const InternedString = strings.InternedString;
const tokenize = @import("tokenizer.zig").tokenize;
const parse = @import("parser.zig").parse;
const file_system = @import("file_system.zig");
const FileSystem = file_system.FileSystem;
const initFileSystem = file_system.initFileSystem;
const read = file_system.read;
const newFile = file_system.newFile;
const components = @import("components.zig");
const Functions = components.Functions;

pub fn buildCodebase(arena: *Arena, fs: ECS, entry_point: []const u8) !Entity {
    var codebase = try initCodebase(arena);
    const contents = read(fs, entry_point);
    var tokens = try tokenize(&codebase, contents);
    return try parse(&codebase, &tokens);
}

test "build codebase" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    _ = try initCodebase(&arena);
    var fs = try initFileSystem(&arena);
    _ = try newFile(&fs, "foo.yeti",
        \\import bar: baz
        \\
        \\start() u64 = baz()
    );
    _ = try newFile(&fs, "bar.yeti",
        \\baz() u64 = 10
    );
    const module = try buildCodebase(&arena, fs, "foo.yeti");
    try expectEqual(module.get(Functions).entities.len, 1);
}
