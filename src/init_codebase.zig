const std = @import("std");
const Arena = std.heap.ArenaAllocator;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const ecs = @import("ecs.zig");
const ECS = ecs.ECS;
const Entity = ecs.Entity;
const Strings = @import("strings.zig").Strings;
const components = @import("components.zig");
const test_utils = @import("test_utils.zig");
const literalOf = test_utils.literalOf;
const typeOf = test_utils.typeOf;

pub fn initCodebase(arena: *Arena) !*ECS {
    const codebase = try arena.allocator().create(ECS);
    codebase.* = ECS.init(arena);
    try codebase.set(.{Strings.init(arena)});
    try initBuiltins(codebase);
    return codebase;
}

fn builtinType(codebase: *ECS, scope: *components.Scope, symbol: []const u8, Type: Entity, bytes: i32) !Entity {
    const size = components.Size{ .bytes = bytes };
    const interned = try codebase.getPtr(Strings).intern(symbol);
    const entity = try codebase.createEntity(.{
        components.Literal.init(interned),
        components.Type.init(Type),
        size,
    });
    try scope.putInterned(interned, entity);
    return entity;
}

pub fn initBuiltins(codebase: *ECS) !void {
    const allocator = codebase.arena.allocator();
    var scope = components.Scope.init(allocator, codebase.getPtr(Strings));
    const interned = try codebase.getPtr(Strings).intern("type");
    const Type = try codebase.createEntity(.{
        components.Literal.init(interned),
    });
    try scope.putInterned(interned, Type);
    _ = try Type.set(.{components.Type.init(Type)});
    const Module = try builtinType(codebase, &scope, "module", Type, 0);
    const I64 = try builtinType(codebase, &scope, "i64", Type, 8);
    const I32 = try builtinType(codebase, &scope, "i32", Type, 4);
    const U64 = try builtinType(codebase, &scope, "u64", Type, 8);
    const U32 = try builtinType(codebase, &scope, "u32", Type, 4);
    const F64 = try builtinType(codebase, &scope, "f64", Type, 8);
    const F32 = try builtinType(codebase, &scope, "f32", Type, 4);
    const IntLiteral = try builtinType(codebase, &scope, "IntLiteral", Type, 0);
    const FloatLiteral = try builtinType(codebase, &scope, "FloatLiteral", Type, 0);
    const Void = try builtinType(codebase, &scope, "void", Type, 0);
    // TODO: p32 is a function from type to type, not a type itself
    // type_of(p32) == Fn(T: type): type
    // type_of(p32(i64)) == type
    const Ptr = try builtinType(codebase, &scope, "ptr", Type, 4);
    _ = try Ptr.set(.{components.Memoized.init(allocator)});
    // TODO: cast is a function from type, and value to value of new type
    // type_of(cast) == Fn(T: type, value: U): T
    // type_of(cast(i64, 5)) == i64
    const Cast = try builtinType(codebase, &scope, "cast", Type, 0);
    const builtins = components.Builtins{
        .Type = Type,
        .Module = Module,
        .I64 = I64,
        .I32 = I32,
        .U64 = U64,
        .U32 = U32,
        .F64 = F64,
        .F32 = F32,
        .Void = Void,
        .Ptr = Ptr,
        .IntLiteral = IntLiteral,
        .FloatLiteral = FloatLiteral,
        .Cast = Cast,
    };
    try codebase.set(.{ builtins, scope });
}

test "builtins" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    const scope = codebase.get(components.Scope);
    try expectEqualStrings(literalOf(builtins.Type), "type");
    try expectEqual(typeOf(builtins.Type), builtins.Type);
    try expectEqual(scope.findString("type"), builtins.Type);
    try expectEqual(scope.findLiteral(builtins.Type.get(components.Literal)), builtins.Type);
    try expectEqualStrings(literalOf(builtins.I64), "i64");
    try expectEqual(typeOf(builtins.I64), builtins.Type);
    try expectEqual(scope.findString("i64"), builtins.I64);
}
