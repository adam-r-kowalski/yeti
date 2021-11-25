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
    const codebase = try arena.allocator.create(ECS);
    codebase.* = ECS.init(arena);
    try codebase.set(.{Strings.init(arena)});
    try initBuiltins(codebase);
    return codebase;
}

fn builtinType(codebase: *ECS, scope: *components.Scope, symbol: []const u8, Type: Entity) !Entity {
    const interned = try codebase.getPtr(Strings).intern(symbol);
    const entity = try codebase.createEntity(.{
        components.Literal.init(interned),
        components.Type.init(Type),
    });
    try scope.putInterned(interned, entity);
    return entity;
}

pub fn initBuiltins(codebase: *ECS) !void {
    var scope = components.Scope.init(&codebase.arena.allocator, codebase.getPtr(Strings));
    const interned = try codebase.getPtr(Strings).intern("Type");
    const Type = try codebase.createEntity(.{
        components.Literal.init(interned),
    });
    try scope.putInterned(interned, Type);
    _ = try Type.set(.{components.Type.init(Type)});
    const Module = try builtinType(codebase, &scope, "Module", Type);
    const I64 = try builtinType(codebase, &scope, "I64", Type);
    const I32 = try builtinType(codebase, &scope, "I32", Type);
    const U64 = try builtinType(codebase, &scope, "U64", Type);
    const U32 = try builtinType(codebase, &scope, "U32", Type);
    const F64 = try builtinType(codebase, &scope, "F64", Type);
    const F32 = try builtinType(codebase, &scope, "F32", Type);
    const IntLiteral = try builtinType(codebase, &scope, "IntLiteral", Type);
    const FloatLiteral = try builtinType(codebase, &scope, "FloatLiteral", Type);
    const StringLiteral = try builtinType(codebase, &scope, "StringLiteral", Type);
    const Void = try builtinType(codebase, &scope, "Void", Type);
    const builtins = components.Builtins{
        .Type = Type,
        .Module = Module,
        .I64 = I64,
        .I32 = I32,
        .U64 = U64,
        .U32 = U32,
        .F64 = F64,
        .F32 = F32,
        .IntLiteral = IntLiteral,
        .FloatLiteral = FloatLiteral,
        .StringLiteral = StringLiteral,
        .Void = Void,
    };
    try codebase.set(.{ builtins, scope });
}

test "builtins" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    const scope = codebase.get(components.Scope);
    try expectEqualStrings(literalOf(builtins.Type), "Type");
    try expectEqual(typeOf(builtins.Type), builtins.Type);
    try expectEqual(scope.findString("Type"), builtins.Type);
    try expectEqual(scope.findLiteral(builtins.Type.get(components.Literal)), builtins.Type);
    try expectEqualStrings(literalOf(builtins.I64), "I64");
    try expectEqual(typeOf(builtins.I64), builtins.Type);
    try expectEqual(scope.findString("I64"), builtins.I64);
}
