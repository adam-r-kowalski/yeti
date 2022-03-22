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

test "tokenize struct" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code = "struct";
    var tokens = try tokenize(module, code);
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .struct_);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 0, .row = 0 },
            .end = .{ .column = 6, .row = 0 },
        });
    }
    try expectEqual(tokens.next(), null);
}

test "parse struct" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\struct Rectangle {
        \\  width: f64
        \\  height: f64
        \\}
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const rectangle = top_level.findString("Rectangle");
    const overloads = rectangle.get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const overload = overloads[0];
    try expectEqual(overload.get(components.AstKind), .struct_);
    const fields = overload.get(components.Fields).slice();
    try expectEqual(fields.len, 2);
    const width = fields[0];
    try expectEqualStrings(literalOf(width), "width");
    try expectEqualStrings(literalOf(width.get(components.TypeAst).entity), "f64");
    const height = fields[1];
    try expectEqualStrings(literalOf(height), "height");
    try expectEqualStrings(literalOf(height.get(components.TypeAst).entity), "f64");
}

test "analyze semantics of struct" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\struct Rectangle {
        \\  width: f64
        \\  height: f64
        \\}
        \\
        \\start() Rectangle {
        \\  Rectangle(10, 30)
        \\}
    );
    _ = try analyzeSemantics(codebase, fs, "foo.yeti");
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    const rectangle = start.get(components.ReturnType).entity;
    try expectEqualStrings(literalOf(rectangle.get(components.Name).entity), "Rectangle");
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 1);
    const construct = body[0];
    try expectEqual(construct.get(components.AstKind), .construct);
    try expectEqual(typeOf(construct), rectangle);
    const arguments = construct.get(components.Arguments).slice();
    try expectEqual(arguments.len, 2);
    try expectEqualStrings(literalOf(arguments[0]), "10");
    try expectEqualStrings(literalOf(arguments[1]), "30");
}

test "analyze semantics of struct field access" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    const builtins = codebase.get(components.Builtins);
    _ = try fs.newFile("foo.yeti",
        \\struct Rectangle {
        \\  width: f64
        \\  height: f64
        \\}
        \\
        \\start() f64 {
        \\  r = Rectangle(10, 30)
        \\  r.width
        \\}
    );
    _ = try analyzeSemantics(codebase, fs, "foo.yeti");
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.F64);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 2);
    const r = blk: {
        const define = body[0];
        try expectEqual(define.get(components.AstKind), .define);
        try expectEqual(typeOf(define), builtins.Void);
        const local = define.get(components.Local).entity;
        try expectEqual(local.get(components.AstKind), .local);
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "r");
        const construct = define.get(components.Value).entity;
        const rectangle = typeOf(construct);
        try expectEqual(typeOf(local), rectangle);
        try expectEqualStrings(literalOf(rectangle.get(components.Name).entity), "Rectangle");
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "r");
        try expectEqual(construct.get(components.AstKind), .construct);
        try expectEqual(typeOf(construct), rectangle);
        const arguments = construct.get(components.Arguments).slice();
        try expectEqual(arguments.len, 2);
        try expectEqualStrings(literalOf(arguments[0]), "10");
        try expectEqualStrings(literalOf(arguments[1]), "30");
        break :blk local;
    };
    const field = body[1];
    try expectEqual(field.get(components.AstKind), .field);
    try expectEqual(typeOf(field), builtins.F64);
    try expectEqual(field.get(components.Local).entity, r);
    try expectEqualStrings(literalOf(field.get(components.Field).entity), "width");
}

test "analyze semantics of struct field write" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    const builtins = codebase.get(components.Builtins);
    _ = try fs.newFile("foo.yeti",
        \\struct Rectangle {
        \\  width: f64
        \\  height: f64
        \\}
        \\
        \\start() Rectangle {
        \\  r = Rectangle(10, 30)
        \\  r.width = 45
        \\  r
        \\}
    );
    _ = try analyzeSemantics(codebase, fs, "foo.yeti");
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    const rectangle = start.get(components.ReturnType).entity;
    try expectEqualStrings(literalOf(rectangle.get(components.Name).entity), "Rectangle");
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 3);
    const r = blk: {
        const define = body[0];
        try expectEqual(define.get(components.AstKind), .define);
        try expectEqual(typeOf(define), builtins.Void);
        const local = define.get(components.Local).entity;
        try expectEqual(local.get(components.AstKind), .local);
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "r");
        const construct = define.get(components.Value).entity;
        try expectEqual(typeOf(construct), rectangle);
        try expectEqual(typeOf(local), rectangle);
        try expectEqualStrings(literalOf(rectangle.get(components.Name).entity), "Rectangle");
        try expectEqual(construct.get(components.AstKind), .construct);
        try expectEqual(typeOf(construct), rectangle);
        const arguments = construct.get(components.Arguments).slice();
        try expectEqual(arguments.len, 2);
        try expectEqualStrings(literalOf(arguments[0]), "10");
        try expectEqualStrings(literalOf(arguments[1]), "30");
        break :blk local;
    };
    const assign_field = body[1];
    try expectEqual(assign_field.get(components.AstKind), .assign_field);
    try expectEqual(typeOf(assign_field), builtins.Void);
    try expectEqual(assign_field.get(components.Local).entity, r);
    try expectEqualStrings(literalOf(assign_field.get(components.Field).entity), "width");
    try expectEqualStrings(literalOf(assign_field.get(components.Value).entity), "45");
    try expectEqual(body[2], r);
}

test "codegen of struct" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\struct Rectangle {
        \\  width: f64
        \\  height: f64
        \\}
        \\
        \\start() Rectangle {
        \\  Rectangle(10, 30)
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
        try expectEqual(constant.get(components.WasmInstructionKind), .f64_const);
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "10");
    }
    {
        const constant = wasm_instructions[1];
        try expectEqual(constant.get(components.WasmInstructionKind), .f64_const);
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "30");
    }
}

test "codegen of struct field write" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\struct Rectangle {
        \\  width: f64
        \\  height: f64
        \\}
        \\
        \\start() Rectangle {
        \\  r = Rectangle(10, 30)
        \\  r.width = 45
        \\  r
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    const wasm_instructions = start.get(components.WasmInstructions).slice();
    try expectEqual(wasm_instructions.len, 6);
    {
        const constant = wasm_instructions[0];
        try expectEqual(constant.get(components.WasmInstructionKind), .f64_const);
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "10");
    }
    {
        const constant = wasm_instructions[1];
        try expectEqual(constant.get(components.WasmInstructionKind), .f64_const);
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "30");
    }
    {
        const local_set = wasm_instructions[2];
        try expectEqual(local_set.get(components.WasmInstructionKind), .local_set);
        const local = local_set.get(components.Local).entity;
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "r");
    }
    {
        const constant = wasm_instructions[3];
        try expectEqual(constant.get(components.WasmInstructionKind), .f64_const);
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "45");
    }
    {
        const assign_field = wasm_instructions[4];
        try expectEqual(assign_field.get(components.WasmInstructionKind), .assign_field);
        const local = assign_field.get(components.Local).entity;
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "r");
        try expectEqualStrings(literalOf(assign_field.get(components.Field).entity), "width");
    }
    {
        const local_get = wasm_instructions[5];
        try expectEqual(local_get.get(components.WasmInstructionKind), .local_get);
        const local = local_get.get(components.Local).entity;
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "r");
    }
}

test "print wasm struct" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\struct Rectangle {
        \\  width: f64
        \\  height: f64
        \\}
        \\
        \\start() Rectangle {
        \\  Rectangle(10, 30)
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/start (result f64 f64)
        \\    (f64.const 10)
        \\    (f64.const 30))
        \\
        \\  (export "_start" (func $foo/start)))
    );
}

test "print wasm assign struct to variable" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\struct Rectangle {
        \\  width: f64
        \\  height: f64
        \\}
        \\
        \\start() Rectangle {
        \\  r = Rectangle(10, 30)
        \\  r
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/start (result f64 f64)
        \\    (local $r.width f64)
        \\    (local $r.height f64)
        \\    (f64.const 10)
        \\    (f64.const 30)
        \\    (local.set $r.height)
        \\    (local.set $r.width)
        \\    (local.get $r.width)
        \\    (local.get $r.height))
        \\
        \\  (export "_start" (func $foo/start)))
    );
}

test "print wasm pass struct to function" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\struct Rectangle {
        \\  width: f64
        \\  height: f64
        \\}
        \\
        \\id(r: Rectangle) Rectangle {
        \\  r
        \\}
        \\
        \\start() Rectangle {
        \\  id(Rectangle(10, 30))
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/start (result f64 f64)
        \\    (f64.const 10)
        \\    (f64.const 30)
        \\    (call $foo/id..r.Rectangle))
        \\
        \\  (func $foo/id..r.Rectangle (param $r.width f64) (param $r.height f64) (result f64 f64)
        \\    (local.get $r.width)
        \\    (local.get $r.height))
        \\
        \\  (export "_start" (func $foo/start)))
    );
}

test "print wasm struct field access" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\struct Rectangle {
        \\  width: f64
        \\  height: f64
        \\}
        \\
        \\start() f64 {
        \\  r = Rectangle(10, 30)
        \\  r.width
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/start (result f64)
        \\    (local $r.width f64)
        \\    (local $r.height f64)
        \\    (f64.const 10)
        \\    (f64.const 30)
        \\    (local.set $r.height)
        \\    (local.set $r.width)
        \\    (local.get $r.width))
        \\
        \\  (export "_start" (func $foo/start)))
    );
}

test "print wasm struct field write" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\struct Rectangle {
        \\  width: f64
        \\  height: f64
        \\}
        \\
        \\start() Rectangle {
        \\  r = Rectangle(10, 30)
        \\  r.width = 45
        \\  r
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/start (result f64 f64)
        \\    (local $r.width f64)
        \\    (local $r.height f64)
        \\    (f64.const 10)
        \\    (f64.const 30)
        \\    (local.set $r.height)
        \\    (local.set $r.width)
        \\    (f64.const 45)
        \\    (local.set $r.width)
        \\    (local.get $r.width)
        \\    (local.get $r.height))
        \\
        \\  (export "_start" (func $foo/start)))
    );
}
