const std = @import("std");
const Arena = std.heap.ArenaAllocator;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const yeti = @import("yeti");
const initCodebase = yeti.initCodebase;
const tokenize = yeti.tokenize;
const parse = yeti.parse;
const analyzeSemantics = yeti.analyzeSemantics;
const codegen = yeti.codegen;
const printWasm = yeti.printWasm;
const components = yeti.components;
const literalOf = yeti.query.literalOf;
const typeOf = yeti.query.typeOf;
const MockFileSystem = yeti.FileSystem;
const Entity = yeti.ecs.Entity;

test "parse import" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\import "math.yeti"
        \\
        \\start() f64 {
        \\  clamp(7, low=0, high=5)
        \\}
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const imports = module.get(components.Imports).slice();
    try expectEqual(imports.len, 1);
    const math = imports[0];
    try expectEqual(math.get(components.AstKind), .import);
    try expectEqualStrings(literalOf(math.get(components.Path).entity), "math.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start");
    const overloads = start.get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const body = overloads[0].get(components.Body).slice();
    try expectEqual(body.len, 1);
    const clamp = body[0];
    const callable = clamp.get(components.Callable).entity;
    try expectEqualStrings(literalOf(callable), "clamp");
    const arguments = clamp.get(components.Arguments).slice();
    try expectEqual(arguments.len, 1);
    try expectEqualStrings(literalOf(arguments[0]), "7");
    const named_arguments = clamp.get(components.NamedArguments);
    try expectEqual(named_arguments.count(), 2);
    try expectEqualStrings(literalOf(named_arguments.findString("low")), "0");
    try expectEqualStrings(literalOf(named_arguments.findString("high")), "5");
}

test "analyze semantics of import" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("start.yeti",
        \\import "math.yeti"
        \\
        \\start() f64 {
        \\  clamp(7, low=0, high=5)
        \\}
    );
    _ = try fs.newFile("math.yeti",
        \\min(x: f64, y: f64) f64 {
        \\  if x < y { x } else { y }
        \\}
        \\
        \\max(x: f64, y: f64) f64 {
        \\  if x > y { x } else { y }
        \\}
        \\
        \\clamp(x: f64, low: f64, high: f64) f64 {
        \\  x.min(high).max(low)
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "start.yeti");
    const top_level = module.get(components.TopLevel);
    const clamp = blk: {
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        try expectEqualStrings(literalOf(start.get(components.Module).entity), "start");
        try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
        try expectEqual(start.get(components.Parameters).len(), 0);
        try expectEqual(start.get(components.ReturnType).entity, builtins.F64);
        const body = start.get(components.Body).slice();
        try expectEqual(body.len, 1);
        const call = body[0];
        try expectEqual(call.get(components.AstKind), .call);
        try expectEqual(call.get(components.Arguments).len(), 1);
        try expectEqual(call.get(components.OrderedNamedArguments).len(), 2);
        try expectEqual(typeOf(call), builtins.F64);
        const callable = call.get(components.Callable).entity;
        break :blk callable;
    };
    const max = blk: {
        try expectEqualStrings(literalOf(clamp.get(components.Module).entity), "math");
        try expectEqualStrings(literalOf(clamp.get(components.Name).entity), "clamp");
        try expectEqual(clamp.get(components.AstKind), .function);
        try expectEqual(clamp.get(components.Parameters).len(), 3);
        try expectEqual(clamp.get(components.ReturnType).entity, builtins.F64);
        const body = clamp.get(components.Body).slice();
        try expectEqual(body.len, 1);
        const call = body[0];
        try expectEqual(call.get(components.AstKind), .call);
        try expectEqual(call.get(components.Arguments).len(), 2);
        try expectEqual(call.get(components.OrderedNamedArguments).len(), 0);
        try expectEqual(typeOf(call), builtins.F64);
        const callable = call.get(components.Callable).entity;
        break :blk callable;
    };
    {
        try expectEqualStrings(literalOf(max.get(components.Module).entity), "math");
        try expectEqualStrings(literalOf(max.get(components.Name).entity), "max");
        try expectEqual(max.get(components.AstKind), .function);
        try expectEqual(max.get(components.Parameters).len(), 2);
        try expectEqual(max.get(components.ReturnType).entity, builtins.F64);
        const body = max.get(components.Body).slice();
        try expectEqual(body.len, 1);
        try expectEqual(body[0].get(components.AstKind), .if_);
    }
}
