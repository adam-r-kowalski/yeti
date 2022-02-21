const std = @import("std");
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const Arena = std.heap.ArenaAllocator;

const yeti = @import("yeti");
const initCodebase = yeti.initCodebase;
const components = yeti.components;
const literalOf = yeti.query.literalOf;
const typeOf = yeti.query.typeOf;

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
