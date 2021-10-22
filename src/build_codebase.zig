const std = @import("std");
const Arena = std.heap.ArenaAllocator;
const assert = std.debug.assert;
const panic = std.debug.panic;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const init_codebase = @import("init_codebase.zig");
const initCodebase = init_codebase.initCodebase;
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
const TopLevel = components.TopLevel;
const Overloads = components.Overloads;
const Parameters = components.Parameters;
const Literal = components.Literal;
const Type = components.Type;
const AstKind = components.AstKind;
const ReturnType = components.ReturnType;
const literalOf = @import("test_utils.zig").literalOf;

pub const Builtins = struct {
    Type: Entity,
    I64: Entity,

    pub fn init(codebase: *ECS) !Builtins {
        const Type_ = blk: {
            const interned = try codebase.getPtr(Strings).intern("type");
            const entity = try codebase.createEntity(.{
                Literal.init(interned),
            });
            break :blk try entity.set(.{Type.init(entity)});
        };
        const I64 = blk: {
            const interned = try codebase.getPtr(Strings).intern("i64");
            break :blk try codebase.createEntity(.{
                Literal.init(interned),
                Type.init(Type_),
            });
        };
        return Builtins{
            .Type = Type_,
            .I64 = I64,
        };
    }
};

fn typeOf(entity: Entity) Entity {
    return entity.get(Type).entity;
}

test "builtins" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = try Builtins.init(&codebase);
    try expectEqualStrings(literalOf(builtins.Type), "type");
    try expectEqual(typeOf(builtins.Type), builtins.Type);
    try expectEqualStrings(literalOf(builtins.I64), "i64");
    try expectEqual(typeOf(builtins.I64), builtins.Type);
}

fn eval(entity: Entity) Entity {
    const kind = entity.get(AstKind);
    switch (kind) {
        .symbol => {
            panic("got here", .{});
        },
        else => panic("\nunsupported kind {}\n", .{kind}),
    }
}

pub fn buildCodebase(arena: *Arena, fs: ECS, entry_point: []const u8) !ECS {
    var codebase = try initCodebase(arena);
    const contents = read(fs, entry_point);
    var tokens = try tokenize(&codebase, contents);
    const module = try parse(&codebase, &tokens);
    const top_level = module.get(TopLevel);
    const overloads = top_level.literal("start").get(Overloads).entities.slice();
    assert(overloads.len == 1);
    const start = overloads[0];
    assert(start.get(Parameters).entities.len == 0);
    _ = eval(start.get(ReturnType).entity);
    return codebase;
}

test "call function from import" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var fs = try initFileSystem(&arena);
    _ = try newFile(&fs, "foo",
        \\import bar
        \\
        \\start() i64 = bar.baz()
    );
    _ = try newFile(&fs, "bar",
        \\baz() i64 = 10
    );
    _ = try buildCodebase(&arena, fs, "foo");
}
