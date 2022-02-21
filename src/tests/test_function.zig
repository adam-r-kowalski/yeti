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

test "tokenize function" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code = "start(): u64 { 0 }";
    var tokens = try tokenize(module, code);
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .symbol);
        try expectEqualStrings(literalOf(token), "start");
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 0, .row = 0 },
            .end = .{ .column = 5, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .left_paren);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 5, .row = 0 },
            .end = .{ .column = 6, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .right_paren);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 6, .row = 0 },
            .end = .{ .column = 7, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .colon);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 7, .row = 0 },
            .end = .{ .column = 8, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .symbol);
        try expectEqualStrings(literalOf(token), "u64");
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 9, .row = 0 },
            .end = .{ .column = 12, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .left_brace);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 13, .row = 0 },
            .end = .{ .column = 14, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .int);
        try expectEqualStrings(literalOf(token), "0");
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 15, .row = 0 },
            .end = .{ .column = 16, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .right_brace);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 17, .row = 0 },
            .end = .{ .column = 18, .row = 0 },
        });
    }
    try expectEqual(tokens.next(), null);
}

test "tokenize multine function" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\f(): u64 {
        \\  x = 5
        \\  y = 15
        \\  x + y
        \\}
    ;
    var tokens = try tokenize(module, code);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .left_paren);
    try expectEqual(tokens.next().?.get(components.TokenKind), .right_paren);
    try expectEqual(tokens.next().?.get(components.TokenKind), .colon);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .left_brace);
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .new_line);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 10, .row = 0 },
            .end = .{ .column = 0, .row = 1 },
        });
    }
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .equal);
    try expectEqual(tokens.next().?.get(components.TokenKind), .int);
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .new_line);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 7, .row = 1 },
            .end = .{ .column = 0, .row = 2 },
        });
    }
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .equal);
    try expectEqual(tokens.next().?.get(components.TokenKind), .int);
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .new_line);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 8, .row = 2 },
            .end = .{ .column = 0, .row = 3 },
        });
    }
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .plus);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .new_line);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 7, .row = 3 },
            .end = .{ .column = 0, .row = 4 },
        });
    }
    try expectEqual(tokens.next().?.get(components.TokenKind), .right_brace);
    try expectEqual(tokens.next(), null);
}

test "parse function" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\start(): u64 {
        \\  0
        \\}
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const overloads = top_level.findString("start").get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const start = overloads[0];
    const return_type = start.get(components.ReturnTypeAst).entity;
    try expectEqual(return_type.get(components.AstKind), .symbol);
    try expectEqualStrings(literalOf(return_type), "u64");
    const body = overloads[0].get(components.Body).slice();
    try expectEqual(body.len, 1);
    const zero = body[0];
    try expectEqual(zero.get(components.AstKind), .int);
    try expectEqualStrings(literalOf(zero), "0");
}

test "parse two functions" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\sum_of_squares(x: u64, y: u64): u64 {
        \\  x*2 + y*2
        \\}
        \\
        \\start(): u64 {
        \\  sum_of_squares(10, 56 * 3)
        \\}
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    {
        const sum_of_squares = module.get(components.TopLevel).findString("sum_of_squares");
        const overloads = sum_of_squares.get(components.Overloads).slice();
        try expectEqual(overloads.len, 1);
        try expectEqual(overloads[0].get(components.Parameters).slice().len, 2);
    }
    {
        const start = module.get(components.TopLevel).findString("start");
        const overloads = start.get(components.Overloads).slice();
        try expectEqual(overloads.len, 1);
        try expectEqual(overloads[0].get(components.Parameters).slice().len, 0);
    }
}

test "parse overload" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\id(x: u64): u64 { x }
        \\
        \\id(x: f64): f64 { x }
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const id = module.get(components.TopLevel).findString("id");
    const overloads = id.get(components.Overloads).slice();
    try expectEqual(overloads.len, 2);
    {
        const id_u64 = overloads[0];
        const parameters = id_u64.get(components.Parameters).slice();
        try expectEqual(parameters.len, 1);
        const x = parameters[0];
        try expectEqualStrings(literalOf(x), "x");
        try expectEqualStrings(literalOf(x.get(components.TypeAst).entity), "u64");
        try expectEqualStrings(literalOf(id_u64.get(components.ReturnTypeAst).entity), "u64");
    }
    {
        const id_f64 = overloads[1];
        const parameters = id_f64.get(components.Parameters).slice();
        try expectEqual(parameters.len, 1);
        const x = parameters[0];
        try expectEqualStrings(literalOf(x), "x");
        try expectEqualStrings(literalOf(x.get(components.TypeAst).entity), "f64");
        try expectEqualStrings(literalOf(id_f64.get(components.ReturnTypeAst).entity), "f64");
    }
}

test "analyze semantics call local function" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    const types = [_][]const u8{ "i64", "i32", "u64", "u32", "f64", "f32" };
    const builtin_types = [_]Entity{ builtins.I64, builtins.I32, builtins.U64, builtins.U32, builtins.F64, builtins.F32 };
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start(): {s} {{
            \\  baz()
            \\}}
            \\
            \\baz(): {s} {{
            \\  10
            \\}}
        , .{ type_of, type_of }));
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
        try expectEqualStrings(literalOf(baz.get(components.Module).entity), "foo");
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

test "analyze semantics function with argument" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    const types = [_][]const u8{ "i64", "i32", "u64", "u32", "f64", "f32" };
    const builtin_types = [_]Entity{ builtins.I64, builtins.I32, builtins.U64, builtins.U32, builtins.F64, builtins.F32 };
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start(): {s} {{
            \\  x: {s} = 10
            \\  id(x)
            \\}}
            \\
            \\id(x: {s}): {s} {{
            \\  x
            \\}}
        , .{ type_of, type_of, type_of, type_of }));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
        try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
        try expectEqual(start.get(components.Parameters).len(), 0);
        try expectEqual(start.get(components.ReturnType).entity, builtin_types[i]);
        const id = blk: {
            const body = start.get(components.Body).slice();
            try expectEqual(body.len, 2);
            const define = body[0];
            try expectEqual(define.get(components.AstKind), .define);
            try expectEqual(typeOf(define), builtins.Void);
            try expectEqualStrings(literalOf(define.get(components.Value).entity), "10");
            const x = define.get(components.Local).entity;
            try expectEqual(x.get(components.AstKind), .local);
            try expectEqualStrings(literalOf(x.get(components.Name).entity), "x");
            try expectEqual(typeOf(x), builtin_types[i]);
            const call = body[1];
            try expectEqual(call.get(components.AstKind), .call);
            try expectEqual(typeOf(call), builtin_types[i]);
            const arguments = call.get(components.Arguments).slice();
            try expectEqual(arguments.len, 1);
            try expectEqual(arguments[0], x);
            break :blk call.get(components.Callable).entity;
        };
        try expectEqualStrings(literalOf(id.get(components.Module).entity), "foo");
        try expectEqualStrings(literalOf(id.get(components.Name).entity), "id");
        const parameters = id.get(components.Parameters).slice();
        try expectEqual(parameters.len, 1);
        const x = parameters[0];
        try expectEqual(typeOf(x), builtin_types[i]);
        try expectEqualStrings(literalOf(x.get(components.Name).entity), "x");
        const body = id.get(components.Body).slice();
        try expectEqual(body.len, 1);
        try expectEqual(body[0], x);
    }
}

test "analyze semantics function call twice" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    const types = [_][]const u8{ "i64", "i32", "u64", "u32", "f64", "f32" };
    const builtin_types = [_]Entity{ builtins.I64, builtins.I32, builtins.U64, builtins.U32, builtins.F64, builtins.F32 };
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start(): {s} {{
            \\  x = id(10)
            \\  id(25)
            \\}}
            \\
            \\id(x: {s}): {s} {{
            \\  x
            \\}}
        , .{ type_of, type_of, type_of }));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
        try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
        try expectEqual(start.get(components.Parameters).len(), 0);
        try expectEqual(start.get(components.ReturnType).entity, builtin_types[i]);
        const start_body = start.get(components.Body).slice();
        try expectEqual(start_body.len, 2);
        const id = blk: {
            const define = start_body[0];
            try expectEqual(define.get(components.AstKind), .define);
            try expectEqual(typeOf(define), builtins.Void);
            const x = define.get(components.Local).entity;
            try expectEqual(x.get(components.AstKind), .local);
            try expectEqualStrings(literalOf(x.get(components.Name).entity), "x");
            try expectEqual(typeOf(x), builtin_types[i]);
            const call = define.get(components.Value).entity;
            try expectEqual(typeOf(call), builtin_types[i]);
            try expectEqual(call.get(components.AstKind), .call);
            const arguments = call.get(components.Arguments).slice();
            try expectEqual(arguments.len, 1);
            const argument = arguments[0];
            try expectEqual(argument.get(components.AstKind), .int);
            try expectEqual(typeOf(argument), builtin_types[i]);
            try expectEqualStrings(literalOf(argument), "10");
            break :blk call.get(components.Callable).entity;
        };
        const call = start_body[1];
        try expectEqual(call.get(components.AstKind), .call);
        try expectEqual(typeOf(call), builtin_types[i]);
        const arguments = call.get(components.Arguments).slice();
        try expectEqual(arguments.len, 1);
        const argument = arguments[0];
        try expectEqual(argument.get(components.AstKind), .int);
        try expectEqual(typeOf(argument), builtin_types[i]);
        try expectEqualStrings(literalOf(argument), "25");
        try expectEqual(call.get(components.Callable).entity, id);
        try expectEqualStrings(literalOf(id.get(components.Module).entity), "foo");
        try expectEqualStrings(literalOf(id.get(components.Name).entity), "id");
        const parameters = id.get(components.Parameters).slice();
        try expectEqual(parameters.len, 1);
        const x = parameters[0];
        try expectEqual(typeOf(x), builtin_types[i]);
        try expectEqualStrings(literalOf(x.get(components.Name).entity), "x");
        const body = id.get(components.Body).slice();
        try expectEqual(body.len, 1);
        try expectEqual(body[0], x);
    }
}

test "codegen call local function" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "i64", "i32", "u64", "u32", "f64", "f32" };
    const const_kinds = [_]components.WasmInstructionKind{ .i64_const, .i32_const, .i64_const, .i32_const, .f64_const, .f32_const };
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start(): {s} {{
            \\  baz()
            \\}}
            \\
            \\baz(): {s} {{
            \\  10
            \\}}
        , .{ type_, type_ }));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        try codegen(module);
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        const start_instructions = start.get(components.WasmInstructions).slice();
        try expectEqual(start_instructions.len, 1);
        const call = start_instructions[0];
        try expectEqual(call.get(components.WasmInstructionKind), .call);
        const baz = call.get(components.Callable).entity;
        const baz_instructions = baz.get(components.WasmInstructions).slice();
        try expectEqual(baz_instructions.len, 1);
        const constant = baz_instructions[0];
        try expectEqual(constant.get(components.WasmInstructionKind), const_kinds[i]);
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "10");
    }
}

test "print wasm call local function" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "f64", "f32" };
    const wasm_types = [_][]const u8{ "f64", "f32" };
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start(): {s} {{
            \\  baz()
            \\}}
            \\
            \\baz(): {s} {{
            \\  10
            \\}}
        , .{ type_, type_ }));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        try codegen(module);
        const wasm = try printWasm(module);
        try expectEqualStrings(wasm, try std.fmt.allocPrint(arena.allocator(),
            \\(module
            \\
            \\  (func $foo/start (result {s})
            \\    (call $foo/baz))
            \\
            \\  (func $foo/baz (result {s})
            \\    ({s}.const 10))
            \\
            \\  (export "_start" (func $foo/start)))
        , .{ wasm_types[i], wasm_types[i], wasm_types[i] }));
    }
}

test "print wasm call local function with argument" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "i64", "i32", "u64", "u32", "f64", "f32" };
    const wasm_types = [_][]const u8{ "i64", "i32", "i64", "i32", "f64", "f32" };
    const const_kinds = [_][]const u8{ "i64.const", "i32.const", "i64.const", "i32.const", "f64.const", "f32.const" };
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start(): {s} {{
            \\  id(5)
            \\}}
            \\
            \\id(x: {s}): {s} {{
            \\  x
            \\}}
        , .{ type_, type_, type_ }));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        try codegen(module);
        const wasm = try printWasm(module);
        try expectEqualStrings(wasm, try std.fmt.allocPrint(arena.allocator(),
            \\(module
            \\
            \\  (func $foo/start (result {s})
            \\    ({s} 5)
            \\    (call $foo/id.{s}))
            \\
            \\  (func $foo/id.{s} (param $x {s}) (result {s})
            \\    (local.get $x))
            \\
            \\  (export "_start" (func $foo/start)))
        , .{ wasm_types[i], const_kinds[i], type_, type_, wasm_types[i], wasm_types[i] }));
    }
}
