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

test "tokenize string" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\"hello" "world"
    ;
    var tokens = try tokenize(module, code);
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .string);
        try expectEqualStrings(literalOf(token), "hello");
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 0, .row = 0 },
            .end = .{ .column = 6, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .string);
        try expectEqualStrings(literalOf(token), "world");
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 8, .row = 0 },
            .end = .{ .column = 14, .row = 0 },
        });
    }
    try expectEqual(tokens.next(), null);
}

test "tokenize multiline string" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\"hello
        \\world"
    ;
    var tokens = try tokenize(module, code);
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .string);
        try expectEqualStrings(literalOf(token), "hello\nworld");
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 0, .row = 0 },
            .end = .{ .column = 6, .row = 1 },
        });
    }
    try expectEqual(tokens.next(), null);
}

test "parse string literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\start(): []u8 {
        \\  "hello world"
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
    try expectEqualStrings(literalOf(return_type.get(components.Value).entity), "u8");
    const body = overloads[0].get(components.Body).slice();
    try expectEqual(body.len, 1);
    const hello_world = body[0];
    try expectEqual(hello_world.get(components.AstKind), .string);
    try expectEqualStrings(literalOf(hello_world), "hello world");
}

test "parse array index" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\start(): u8 {
        \\  text = "hello world"
        \\  text[0]
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
    try expectEqualStrings(literalOf(return_type), "u8");
    const body = overloads[0].get(components.Body).slice();
    try expectEqual(body.len, 2);
    const define = body[0];
    try expectEqual(define.get(components.AstKind), .define);
    try expectEqualStrings(literalOf(define.get(components.Name).entity), "text");
    const hello_world = define.get(components.Value).entity;
    try expectEqual(hello_world.get(components.AstKind), .string);
    try expectEqualStrings(literalOf(hello_world), "hello world");
    const index = body[1];
    try expectEqual(index.get(components.AstKind), .index);
    const arguments = index.get(components.Arguments).slice();
    try expectEqual(arguments.len, 2);
    try expectEqualStrings(literalOf(arguments[0]), "text");
    try expectEqualStrings(literalOf(arguments[1]), "0");
}

test "analyze semantics of string literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start(): []u8 {
        \\  "hello world"
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
    try expectEqualStrings(literalOf(return_type), "[]u8");
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 1);
    const hello_world = body[0];
    try expectEqual(hello_world.get(components.AstKind), .string);
    try expectEqual(typeOf(hello_world), return_type);
    try expectEqualStrings(literalOf(hello_world), "hello world");
}

test "analyze semantics of array index" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start(): u8 {
        \\  text = "hello world"
        \\  text[0]
        \\}
    );
    _ = try analyzeSemantics(codebase, fs, "foo.yeti");
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.U8);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 2);
    const define = body[0];
    try expectEqual(define.get(components.AstKind), .define);
    try expectEqual(typeOf(define), builtins.Void);
    const local = define.get(components.Local).entity;
    try expectEqual(local.get(components.AstKind), .local);
    try expectEqualStrings(literalOf(local.get(components.Name).entity), "text");
    const hello_world = define.get(components.Value).entity;
    try expectEqual(hello_world.get(components.AstKind), .string);
    try expectEqualStrings(literalOf(typeOf(hello_world)), "[]u8");
    try expectEqualStrings(literalOf(hello_world), "hello world");
    const index = body[1];
    try expectEqual(index.get(components.AstKind), .index);
    try expectEqual(typeOf(index), builtins.U8);
    const arguments = index.get(components.Arguments).slice();
    try expectEqual(arguments[0], local);
    try expectEqualStrings(literalOf(arguments[1]), "0");
}

test "codegen of string literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start(): []u8 {
        \\  "hello world"
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
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "11");
    }
    const data_segment = codebase.get(components.DataSegment);
    try expectEqual(data_segment.end, 88);
    const entities = data_segment.entities.slice();
    try expectEqual(entities.len, 1);
    try expectEqualStrings(literalOf(entities[0]), "hello world");
}

test "codegen of array index" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start(): u8 {
        \\  text = "hello world"
        \\  text[0]
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    const wasm_instructions = start.get(components.WasmInstructions).slice();
    try expectEqual(wasm_instructions.len, 9);
    {
        const constant = wasm_instructions[0];
        try expectEqual(constant.get(components.WasmInstructionKind), .i32_const);
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "0");
    }
    {
        const constant = wasm_instructions[1];
        try expectEqual(constant.get(components.WasmInstructionKind), .i32_const);
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "11");
    }
    {
        const local_set = wasm_instructions[2];
        try expectEqual(local_set.get(components.WasmInstructionKind), .local_set);
        try expectEqualStrings(literalOf(local_set.get(components.Local).entity.get(components.Name).entity), "text");
    }
    {
        const field = wasm_instructions[3];
        try expectEqual(field.get(components.WasmInstructionKind), .field);
        try expectEqualStrings(literalOf(field.get(components.Local).entity.get(components.Name).entity), "text");
        try expectEqualStrings(literalOf(field.get(components.Field).entity), "ptr");
    }
    {
        const constant = wasm_instructions[4];
        try expectEqual(constant.get(components.WasmInstructionKind), .i32_const);
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "0");
    }
    {
        const constant = wasm_instructions[5];
        try expectEqual(constant.get(components.WasmInstructionKind), .i32_const);
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "1");
    }
    try expectEqual(wasm_instructions[6].get(components.WasmInstructionKind), .i32_mul);
    try expectEqual(wasm_instructions[7].get(components.WasmInstructionKind), .i32_add);
    try expectEqual(wasm_instructions[8].get(components.WasmInstructionKind), .i32_load8_u);
    const data_segment = codebase.get(components.DataSegment);
    try expectEqual(data_segment.end, 88);
    const entities = data_segment.entities.slice();
    try expectEqual(entities.len, 1);
    try expectEqualStrings(literalOf(entities[0]), "hello world");
}

test "print wasm string literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start(): []u8 {
        \\  "hello world"
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
        \\    (i32.const 11))
        \\
        \\  (export "_start" (func $foo/start))
        \\
        \\  (data (i32.const 0) "hello world")
        \\
        \\  (memory 1)
        \\  (export "memory" (memory 0)))
    );
}

test "print wasm assign string literal to variable" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start(): []u8 {
        \\  text = "hello world"
        \\  text
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/start (result i32 i32)
        \\    (local $text.ptr i32)
        \\    (local $text.len i32)
        \\    (i32.const 0)
        \\    (i32.const 11)
        \\    (local.set $text.len)
        \\    (local.set $text.ptr)
        \\    (local.get $text.ptr)
        \\    (local.get $text.len))
        \\
        \\  (export "_start" (func $foo/start))
        \\
        \\  (data (i32.const 0) "hello world")
        \\
        \\  (memory 1)
        \\  (export "memory" (memory 0)))
    );
}

test "print wasm pass string literal as argument" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\first(text: []u8): u8 {
        \\  *text.ptr
        \\}
        \\
        \\start(): u8 {
        \\  first("hello world")
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/start (result i32)
        \\    (i32.const 0)
        \\    (i32.const 11)
        \\    (call $foo/first.array.u8))
        \\
        \\  (func $foo/first.array.u8 (param $text.ptr i32) (param $text.len i32) (result i32)
        \\    (local.get $text.ptr)
        \\    i32.load8_u)
        \\
        \\  (export "_start" (func $foo/start))
        \\
        \\  (data (i32.const 0) "hello world")
        \\
        \\  (memory 1)
        \\  (export "memory" (memory 0)))
    );
}

test "print wasm dereference string literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start(): u8 {
        \\  text = "hello world"
        \\  *text.ptr
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/start (result i32)
        \\    (local $text.ptr i32)
        \\    (local $text.len i32)
        \\    (i32.const 0)
        \\    (i32.const 11)
        \\    (local.set $text.len)
        \\    (local.set $text.ptr)
        \\    (local.get $text.ptr)
        \\    i32.load8_u)
        \\
        \\  (export "_start" (func $foo/start))
        \\
        \\  (data (i32.const 0) "hello world")
        \\
        \\  (memory 1)
        \\  (export "memory" (memory 0)))
    );
}

test "print wasm write through **u8" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start(): void {
        \\  text = "hello world"
        \\  ptr = cast(**u8, 100)
        \\  *ptr = text.ptr
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/start
        \\    (local $text.ptr i32)
        \\    (local $text.len i32)
        \\    (local $ptr i32)
        \\    (i32.const 0)
        \\    (i32.const 11)
        \\    (local.set $text.len)
        \\    (local.set $text.ptr)
        \\    (i32.const 100)
        \\    (local.set $ptr)
        \\    (local.get $ptr)
        \\    (local.get $text.ptr)
        \\    i32.store)
        \\
        \\  (export "_start" (func $foo/start))
        \\
        \\  (data (i32.const 0) "hello world")
        \\
        \\  (memory 1)
        \\  (export "memory" (memory 0)))
    );
}
