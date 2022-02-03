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
        \\a = function(): U64 10 end
        \\
        \\b = function(): U64 a() end
    );
    _ = try fs.newFile("bar.yeti",
        \\c = function(): U64 d() end
        \\
        \\d = function(): U64 5 end
    );
    const contents = try fs.read("foo.yeti");
    try expectEqualStrings(foo.get(Contents).bytes, contents);
}
