const std = @import("std");
const Arena = std.heap.ArenaAllocator;
const panic = std.debug.panic;
const assert = std.debug.assert;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectEqualSlices = std.testing.expectEqualSlices;

const List = @import("list.zig").List;
const ecs_module = @import("ecs.zig");
const ECS = ecs_module.ECS;
const Entity = ecs_module.Entity;

const File = struct {
    bytes: []const u8,

    fn init(bytes: []const u8) File {
        return File{ .bytes = bytes };
    }
};

const Contents = struct {
    bytes: []const u8,

    fn init(bytes: []const u8) Contents {
        return Contents{ .bytes = bytes };
    }
};

const Files = struct {
    entities: List(Entity, .{}),

    fn init(arena: *Arena) Files {
        return Files{ .entities = List(Entity, .{}).init(arena.allocator()) };
    }
};

const Lookup = struct {
    map: std.StringHashMap(Entity),

    fn init(arena: *Arena) Lookup {
        return Lookup{ .map = std.StringHashMap(Entity).init(arena.allocator()) };
    }
};

pub const FileSystem = struct {
    ecs: ECS,

    pub fn init(arena: *Arena) !FileSystem {
        var ecs = ECS.init(arena);
        try ecs.set(.{
            Files.init(arena),
            Lookup.init(arena),
        });
        return FileSystem{ .ecs = ecs };
    }

    pub fn newFile(self: *FileSystem, name: []const u8, contents: []const u8) !Entity {
        const file = try self.ecs.createEntity(.{
            File.init(name),
            Contents.init(contents),
        });
        try self.ecs.getPtr(Files).entities.append(file);
        try self.ecs.getPtr(Lookup).map.putNoClobber(name, file);
        return file;
    }

    pub fn read(self: FileSystem, name: []const u8) error{ OutOfMemory, CantOpenFile }![]const u8 {
        const file = self.ecs.get(Lookup).map.get(name).?;
        return file.get(Contents).bytes;
    }
};

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
