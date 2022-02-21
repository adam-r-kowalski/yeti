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

test "parse import and function" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\math = import("math.yeti")
        \\
        \\start(): u64 {
        \\  math.sum_of_squares(10, 56 * 3)
        \\}
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const math = top_level.findString("math");
    try expectEqual(math.get(components.AstKind), .import);
    try expectEqualStrings(literalOf(math.get(components.Path).entity), "math.yeti");
    const start = top_level.findString("start");
    const overloads = start.get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const body = overloads[0].get(components.Body).slice();
    try expectEqual(body.len, 1);
    const dot = body[0];
    try expectEqual(dot.get(components.AstKind), .binary_op);
    const dot_arguments = dot.get(components.Arguments).slice();
    try expectEqualStrings(literalOf(dot_arguments[0]), "math");
    const sum_of_squares = dot_arguments[1];
    const callable = sum_of_squares.get(components.Callable).entity;
    try expectEqualStrings(literalOf(callable), "sum_of_squares");
    const sum_of_squares_arguments = sum_of_squares.get(components.Arguments).slice();
    try expectEqualStrings(literalOf(sum_of_squares_arguments[0]), "10");
    const multiply = sum_of_squares_arguments[1];
    try expectEqual(multiply.get(components.BinaryOp), .multiply);
    const arguments = multiply.get(components.Arguments).slice();
    try expectEqualStrings(literalOf(arguments[0]), "56");
    try expectEqualStrings(literalOf(arguments[1]), "3");
}

test "analyze semantics call function import" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    const types = [_][]const u8{ "i64", "i32", "u64", "u32", "f64", "f32" };
    const builtin_types = [_]Entity{ builtins.I64, builtins.I32, builtins.U64, builtins.U32, builtins.F64, builtins.F32 };
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\bar = import("bar.yeti")
            \\
            \\start(): {s} {{
            \\  bar.baz()
            \\}}
        , .{type_of}));
        _ = try fs.newFile("bar.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\baz(): {s} {{
            \\  10
            \\}}
        , .{type_of}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
        try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
        try expectEqual(start.get(components.Parameters).len(), 0);
        try expectEqual(start.get(components.ReturnType).entity, builtin_types[i]);
        const baz = blk: {
            const body = start.get(components.Body).slice();
            try expectEqual(body.len, 1);
            const call = body[0];
            try expectEqual(call.get(components.AstKind), .call);
            try expectEqual(call.get(components.Arguments).len(), 0);
            try expectEqual(typeOf(call), builtin_types[i]);
            break :blk call.get(components.Callable).entity;
        };
        try expectEqualStrings(literalOf(baz.get(components.Module).entity), "bar");
        try expectEqualStrings(literalOf(baz.get(components.Name).entity), "baz");
        try expectEqual(baz.get(components.Parameters).len(), 0);
        try expectEqual(baz.get(components.ReturnType).entity, builtin_types[i]);
        const body = baz.get(components.Body).slice();
        try expectEqual(body.len, 1);
        const int_literal = body[0];
        try expectEqual(int_literal.get(components.AstKind), .int);
        try expectEqual(typeOf(int_literal), builtin_types[i]);
        try expectEqualStrings(literalOf(int_literal), "10");
    }
}

test "analyze semantics of calling imported function with local arguments" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\bar = import("bar.yeti")
        \\
        \\g(x: i64): i64 {
        \\  x + x
        \\}
        \\
        \\start(): i64 {
        \\  bar.f(g(300))
        \\}
    );
    _ = try fs.newFile("bar.yeti",
        \\f(x: i64): i64 {
        \\  x * x
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.I64);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 1);
    const g = blk: {
        const f = body[0];
        try expectEqual(f.get(components.AstKind), .call);
        const arguments = f.get(components.Arguments).slice();
        try expectEqual(arguments.len, 1);
        try expectEqual(typeOf(f), builtins.I64);
        const callable = f.get(components.Callable).entity;
        try expectEqualStrings(literalOf(callable.get(components.Module).entity), "bar");
        try expectEqualStrings(literalOf(callable.get(components.Name).entity), "f");
        break :blk arguments[0];
    };
    try expectEqual(g.get(components.AstKind), .call);
    const arguments = g.get(components.Arguments).slice();
    try expectEqual(arguments.len, 1);
    try expectEqual(typeOf(g), builtins.I64);
    const callable = g.get(components.Callable).entity;
    try expectEqualStrings(literalOf(callable.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(callable.get(components.Name).entity), "g");
    const five = arguments[0];
    try expectEqual(typeOf(five), builtins.I64);
    try expectEqualStrings(literalOf(five), "300");
}

test "analyze semantics of calling imported function twice" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\bar = import("bar.yeti")
        \\
        \\start(): i64 {
        \\  bar.f(bar.f(300))
        \\}
    );
    _ = try fs.newFile("bar.yeti",
        \\f(x: i64): i64 {
        \\  x * x
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.I64);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 1);
    const f = body[0];
    try expectEqual(f.get(components.AstKind), .call);
    const f_arguments = f.get(components.Arguments).slice();
    try expectEqual(f_arguments.len, 1);
    try expectEqual(typeOf(f), builtins.I64);
    const f_callable = f.get(components.Callable).entity;
    const f_module = f_callable.get(components.Module).entity;
    try expectEqualStrings(literalOf(f_module), "bar");
    try expectEqualStrings(literalOf(f_callable.get(components.Name).entity), "f");
    const f_inner = f_arguments[0];
    try expectEqual(f_inner.get(components.AstKind), .call);
    const f_inner_arguments = f_inner.get(components.Arguments).slice();
    try expectEqual(f_inner_arguments.len, 1);
    try expectEqual(typeOf(f_inner), builtins.I64);
    const f_inner_callable = f_inner.get(components.Callable).entity;
    try expectEqual(f_inner_callable, f_callable);
}
