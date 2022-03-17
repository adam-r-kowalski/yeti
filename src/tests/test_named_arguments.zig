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
const parentType = yeti.query.parentType;
const valueType = yeti.query.valueType;
const Entity = yeti.ecs.Entity;
const MockFileSystem = yeti.FileSystem;

test "analyze semantics of named argument" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start(): i64 {
        \\  id(x=5)
        \\}
        \\
        \\id(x: i64): i64 {
        \\  x
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.I64);
    const id = blk: {
        const body = start.get(components.Body).slice();
        try expectEqual(body.len, 1);
        const call = body[0];
        try expectEqual(call.get(components.AstKind), .call);
        try expectEqual(call.get(components.Arguments).len(), 0);
        const named_arguments = call.get(components.OrderedNamedArguments).slice();
        try expectEqual(named_arguments.len, 1);
        try expectEqualStrings(literalOf(named_arguments[0]), "5");
        try expectEqual(typeOf(call), builtins.I64);
        break :blk call.get(components.Callable).entity;
    };
    try expectEqualStrings(literalOf(id.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(id.get(components.Name).entity), "id");
    try expectEqual(id.get(components.Parameters).len(), 1);
    try expectEqual(id.get(components.ReturnType).entity, builtins.I64);
    const body = id.get(components.Body).slice();
    try expectEqual(body.len, 1);
    const x = body[0];
    try expectEqual(x.get(components.AstKind), .local);
    try expectEqual(typeOf(x), builtins.I64);
    try expectEqualStrings(literalOf(x), "x");
}

test "analyze semantics of positional then named argument" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start(): i64 {
        \\  bar(3, y=5)
        \\}
        \\
        \\bar(x: i64, y: i64): i64 {
        \\  x
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.I64);
    const bar = blk: {
        const body = start.get(components.Body).slice();
        try expectEqual(body.len, 1);
        const call = body[0];
        try expectEqual(call.get(components.AstKind), .call);
        const arguments = call.get(components.Arguments).slice();
        try expectEqual(arguments.len, 1);
        try expectEqualStrings(literalOf(arguments[0]), "3");
        const named_arguments = call.get(components.OrderedNamedArguments).slice();
        try expectEqual(named_arguments.len, 1);
        try expectEqualStrings(literalOf(named_arguments[0]), "5");
        try expectEqual(typeOf(call), builtins.I64);
        break :blk call.get(components.Callable).entity;
    };
    try expectEqualStrings(literalOf(bar.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(bar.get(components.Name).entity), "bar");
    try expectEqual(bar.get(components.Parameters).len(), 2);
    try expectEqual(bar.get(components.ReturnType).entity, builtins.I64);
    const body = bar.get(components.Body).slice();
    try expectEqual(body.len, 1);
    const x = body[0];
    try expectEqual(x.get(components.AstKind), .local);
    try expectEqual(typeOf(x), builtins.I64);
    try expectEqualStrings(literalOf(x), "x");
}

test "analyze semantics of uniform function call syntax with named argument" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start(): i64 {
        \\  3.bar(y=5)
        \\}
        \\
        \\bar(x: i64, y: i64): i64 {
        \\  x
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.I64);
    const bar = blk: {
        const body = start.get(components.Body).slice();
        try expectEqual(body.len, 1);
        const call = body[0];
        try expectEqual(call.get(components.AstKind), .call);
        const arguments = call.get(components.Arguments).slice();
        try expectEqual(arguments.len, 1);
        try expectEqualStrings(literalOf(arguments[0]), "3");
        const named_arguments = call.get(components.OrderedNamedArguments).slice();
        try expectEqual(named_arguments.len, 1);
        try expectEqualStrings(literalOf(named_arguments[0]), "5");
        try expectEqual(typeOf(call), builtins.I64);
        break :blk call.get(components.Callable).entity;
    };
    try expectEqualStrings(literalOf(bar.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(bar.get(components.Name).entity), "bar");
    try expectEqual(bar.get(components.Parameters).len(), 2);
    try expectEqual(bar.get(components.ReturnType).entity, builtins.I64);
    const body = bar.get(components.Body).slice();
    try expectEqual(body.len, 1);
    const x = body[0];
    try expectEqual(x.get(components.AstKind), .local);
    try expectEqual(typeOf(x), builtins.I64);
    try expectEqualStrings(literalOf(x), "x");
}

test "codegen named arguments" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start(): i32 {
        \\  id(x=5)
        \\}
        \\
        \\id(x: i32): i32 {
        \\  x
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    const start_instructions = start.get(components.WasmInstructions).slice();
    try expectEqual(start_instructions.len, 2);
    const constant = start_instructions[0];
    try expectEqual(constant.get(components.WasmInstructionKind), components.WasmInstructionKind.i32_const);
    try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "5");
    const call = start_instructions[1];
    try expectEqual(call.get(components.WasmInstructionKind), .call);
    const baz = call.get(components.Callable).entity;
    const baz_instructions = baz.get(components.WasmInstructions).slice();
    try expectEqual(baz_instructions.len, 1);
}
