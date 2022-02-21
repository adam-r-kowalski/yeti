const std = @import("std");
const Arena = std.heap.ArenaAllocator;
const expectEqualStrings = std.testing.expectEqualStrings;

const yeti = @import("yeti");
const FileSystem = yeti.FileSystem;
const Contents = yeti.file_system.Contents;

test "filesystem create and lookup file" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var fs = try FileSystem.init(&arena);
    const foo = try fs.newFile("foo.yeti",
        \\a(): u64 { 10 }
        \\
        \\b(): u64 { a() }
    );
    _ = try fs.newFile("bar.yeti",
        \\c(): u64 { d() }
        \\
        \\d(): u64 { 5 }
    );
    const contents = try fs.read("foo.yeti");
    try expectEqualStrings(foo.get(Contents).bytes, contents);
}
