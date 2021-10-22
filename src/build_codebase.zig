const std = @import("std");
const eql = std.meta.eql;
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
const Builtins = components.Builtins;
const Scope = components.Scope;
const literalOf = @import("test_utils.zig").literalOf;

fn builtinType(codebase: *ECS, scope: *Scope, symbol: []const u8, Type_: Entity) !Entity {
    const interned = try codebase.getPtr(Strings).intern(symbol);
    const entity = try codebase.createEntity(.{
        Literal.init(interned),
        Type.init(Type_),
    });
    try scope.put(interned, entity);
    return entity;
}

fn initBuiltins(codebase: *ECS) !void {
    var scope = Scope.init(&codebase.arena.allocator, codebase.getPtr(Strings));
    const interned = try codebase.getPtr(Strings).intern("type");
    const Type_ = try codebase.createEntity(.{
        Literal.init(interned),
    });
    try scope.put(interned, Type_);
    _ = try Type_.set(.{Type.init(Type_)});
    const I64 = try builtinType(codebase, &scope, "i64", Type_);
    const I32 = try builtinType(codebase, &scope, "i32", Type_);
    const U64 = try builtinType(codebase, &scope, "u64", Type_);
    const U32 = try builtinType(codebase, &scope, "u32", Type_);
    const builtins = Builtins{
        .Type = Type_,
        .I64 = I64,
        .I32 = I32,
        .U64 = U64,
        .U32 = U32,
    };
    try codebase.set(.{ builtins, scope });
}

fn typeOf(entity: Entity) Entity {
    return entity.get(Type).entity;
}

test "builtins" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    try initBuiltins(&codebase);
    const builtins = codebase.get(Builtins);
    const scope = codebase.get(Scope);
    try expectEqualStrings(literalOf(builtins.Type), "type");
    try expectEqual(typeOf(builtins.Type), builtins.Type);
    try expectEqual(scope.findString("type"), builtins.Type);
    try expectEqual(scope.findLiteral(builtins.Type.get(Literal)), builtins.Type);
    try expectEqualStrings(literalOf(builtins.I64), "i64");
    try expectEqual(typeOf(builtins.I64), builtins.Type);
    try expectEqual(scope.findString("i64"), builtins.I64);
    try expectEqualStrings(literalOf(builtins.I32), "i32");
    try expectEqual(typeOf(builtins.I32), builtins.Type);
    try expectEqual(scope.findString("i32"), builtins.I32);
    try expectEqualStrings(literalOf(builtins.U64), "u64");
    try expectEqual(typeOf(builtins.U64), builtins.Type);
    try expectEqual(scope.findString("u64"), builtins.U64);
    try expectEqualStrings(literalOf(builtins.U32), "u32");
    try expectEqual(typeOf(builtins.U32), builtins.Type);
    try expectEqual(scope.findString("u32"), builtins.U32);
}

fn eval(entity: Entity) Entity {
    const kind = entity.get(AstKind);
    switch (kind) {
        .symbol => return entity.ecs.get(Scope).findLiteral(entity.get(Literal)),
        else => panic("\nunsupported kind {}\n", .{kind}),
    }
}

pub fn buildCodebase(arena: *Arena, fs: ECS, entry_point: []const u8) !ECS {
    var codebase = try initCodebase(arena);
    try initBuiltins(&codebase);
    const contents = read(fs, entry_point);
    var tokens = try tokenize(&codebase, contents);
    const module = try parse(&codebase, &tokens);
    const top_level = module.get(TopLevel);
    const overloads = top_level.findString("start").get(Overloads).entities.slice();
    assert(overloads.len == 1);
    const start = overloads[0];
    assert(start.get(Parameters).entities.len == 0);
    const return_type = eval(start.get(ReturnType).entity);
    assert(eql(return_type, codebase.get(Builtins).I64));
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
