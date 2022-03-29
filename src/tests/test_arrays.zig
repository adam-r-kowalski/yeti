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

test "tokenize array" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code = "[1, 2, 3]";
    var tokens = try tokenize(module, code);
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .left_bracket);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 0, .row = 0 },
            .end = .{ .column = 1, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .int);
        try expectEqualStrings(literalOf(token), "1");
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 1, .row = 0 },
            .end = .{ .column = 2, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .comma);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 2, .row = 0 },
            .end = .{ .column = 3, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .int);
        try expectEqualStrings(literalOf(token), "2");
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 4, .row = 0 },
            .end = .{ .column = 5, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .comma);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 5, .row = 0 },
            .end = .{ .column = 6, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .int);
        try expectEqualStrings(literalOf(token), "3");
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 7, .row = 0 },
            .end = .{ .column = 8, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .right_bracket);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 8, .row = 0 },
            .end = .{ .column = 9, .row = 0 },
        });
    }
    try expectEqual(tokens.next(), null);
}

test "parse array literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\start() []f32 {
        \\  [1, 2, 3]
        \\}
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const overloads = top_level.findString("start").get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const start = overloads[0];
    const return_type = start.get(components.ReturnTypeAst).entity;
    try expectEqual(return_type.get(components.AstKind), .array);
    try expectEqualStrings(literalOf(return_type.get(components.Value).entity), "f32");
    const body = overloads[0].get(components.Body).slice();
    try expectEqual(body.len, 1);
    const array_literal = body[0];
    try expectEqual(array_literal.get(components.AstKind), .array_literal);
    const values = array_literal.get(components.Values).slice();
    try expectEqual(values.len, 3);
    try expectEqualStrings(literalOf(values[0]), "1");
    try expectEqualStrings(literalOf(values[1]), "2");
    try expectEqualStrings(literalOf(values[2]), "3");
}

test "parse multiline array literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\start() []f32 {
        \\  [ 1, 2,
        \\    3, 4,
        \\    5, 6 ]
        \\}
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const overloads = top_level.findString("start").get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const start = overloads[0];
    const return_type = start.get(components.ReturnTypeAst).entity;
    try expectEqual(return_type.get(components.AstKind), .array);
    try expectEqualStrings(literalOf(return_type.get(components.Value).entity), "f32");
    const body = overloads[0].get(components.Body).slice();
    try expectEqual(body.len, 1);
    const array_literal = body[0];
    try expectEqual(array_literal.get(components.AstKind), .array_literal);
    const values = array_literal.get(components.Values).slice();
    try expectEqual(values.len, 6);
    try expectEqualStrings(literalOf(values[0]), "1");
    try expectEqualStrings(literalOf(values[1]), "2");
    try expectEqualStrings(literalOf(values[2]), "3");
    try expectEqualStrings(literalOf(values[3]), "4");
    try expectEqualStrings(literalOf(values[4]), "5");
    try expectEqualStrings(literalOf(values[5]), "6");
}

test "analyze semantics of array literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start() []f32 {
        \\  [1, 2, 3]
        \\}
    );
    _ = try analyzeSemantics(codebase, fs, "foo.yeti");
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    const return_type = start.get(components.ReturnType).entity;
    try expectEqualStrings(literalOf(return_type), "[]f32");
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 1);
    const array_literal = body[0];
    try expectEqual(array_literal.get(components.AstKind), .array_literal);
    try expectEqual(typeOf(array_literal), return_type);
    const values = array_literal.get(components.Values).slice();
    try expectEqual(values.len, 3);
    try expectEqual(typeOf(values[0]), builtins.IntLiteral);
    try expectEqual(typeOf(values[1]), builtins.IntLiteral);
    try expectEqual(typeOf(values[2]), builtins.IntLiteral);
}

test "codegen of array literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start() []f32 {
        \\  [1, 2, 3]
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    const wasm_instructions = start.get(components.WasmInstructions).slice();
    try expectEqual(wasm_instructions.len, 2);
    {
        const constant = wasm_instructions[0];
        try expectEqual(constant.get(components.WasmInstructionKind), .i32_const);
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "0");
    }
    {
        const constant = wasm_instructions[1];
        try expectEqual(constant.get(components.WasmInstructionKind), .i32_const);
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "3");
    }
    const data_segment = codebase.get(components.DataSegment);
    try expectEqual(data_segment.end, 96);
    const entities = data_segment.entities.slice();
    try expectEqual(entities.len, 1);
}

test "print wasm i32 array literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start() []i32 {
        \\  [1, 2, 3]
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/start (result i32 i32)
        \\    (i32.const 0)
        \\    (i32.const 3))
        \\
        \\  (export "_start" (func $foo/start))
        \\
        \\  (data (i32.const 0) "\01\00\00\00\02\00\00\00\03\00\00\00")
        \\
        \\  (memory 1)
        \\  (export "memory" (memory 0)))
    );
}

test "print wasm f32 array literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start() []f32 {
        \\  [1, 2, 3]
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/start (result i32 i32)
        \\    (i32.const 0)
        \\    (i32.const 3))
        \\
        \\  (export "_start" (func $foo/start))
        \\
        \\  (data (i32.const 0) "\00\00\80\3f\00\00\00\40\00\00\40\40")
        \\
        \\  (memory 1)
        \\  (export "memory" (memory 0)))
    );
}

test "print wasm f32 array literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\id(x: f32) f32 {
        \\  x
        \\}
        \\
        \\start() []f32 {
        \\  [id(1), id(2), id(3)]
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/start (result i32 i32)
        \\    (i32.const 0)
        \\    (i32.const 3))
        \\
        \\  (export "_start" (func $foo/start))
        \\
        \\  (data (i32.const 0) "\00\00\80\3f\00\00\00\40\00\00\40\40")
        \\
        \\  (memory 1)
        \\  (export "memory" (memory 0)))
    );
}
