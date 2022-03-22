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

test "parse if" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\start() u64 {
        \\  if 10 > 5 { 20 } else { 30 }
        \\}
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start");
    const overloads = start.get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const body = overloads[0].get(components.Body).slice();
    try expectEqual(body.len, 1);
    const if_ = body[0];
    try expectEqual(if_.get(components.AstKind), .if_);
    const conditional = if_.get(components.Conditional).entity;
    try expectEqual(conditional.get(components.AstKind), .binary_op);
    try expectEqual(conditional.get(components.BinaryOp), .greater_than);
    const then = if_.get(components.Then).slice();
    try expectEqual(then.len, 1);
    try expectEqualStrings(literalOf(then[0]), "20");
    const else_ = if_.get(components.Else).slice();
    try expectEqual(else_.len, 1);
    try expectEqualStrings(literalOf(else_[0]), "30");
}

test "parse if using arguments of function" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\min(x: i64, y: i64) i64 {
        \\  if x < y { x } else { y }
        \\}
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const overloads = top_level.findString("min").get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const min = overloads[0];
    const return_type = min.get(components.ReturnTypeAst).entity;
    try expectEqual(return_type.get(components.AstKind), .symbol);
    try expectEqualStrings(literalOf(return_type), "i64");
    const body = overloads[0].get(components.Body).slice();
    try expectEqual(body.len, 1);
    const if_ = body[0];
    try expectEqual(if_.get(components.AstKind), .if_);
    const conditional = if_.get(components.Conditional).entity;
    try expectEqual(conditional.get(components.AstKind), .binary_op);
    try expectEqual(conditional.get(components.BinaryOp), .less_than);
    const then = if_.get(components.Then).slice();
    try expectEqual(then.len, 1);
    try expectEqualStrings(literalOf(then[0]), "x");
    const else_ = if_.get(components.Else).slice();
    try expectEqual(else_.len, 1);
    try expectEqualStrings(literalOf(else_[0]), "y");
}
test "parse multiline if then else" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\start() u64 {
        \\  if 10 > 5 {
        \\    x = 20
        \\    x
        \\  } else {
        \\    y = 30
        \\    y
        \\  }
        \\}
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start");
    const overloads = start.get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const body = overloads[0].get(components.Body).slice();
    try expectEqual(body.len, 1);
    const if_ = body[0];
    try expectEqual(if_.get(components.AstKind), .if_);
    const conditional = if_.get(components.Conditional).entity;
    try expectEqual(conditional.get(components.AstKind), .binary_op);
    try expectEqual(conditional.get(components.BinaryOp), .greater_than);
    const then = if_.get(components.Then).slice();
    try expectEqual(then.len, 2);
    {
        const define = then[0];
        try expectEqual(define.get(components.AstKind), .define);
        try expectEqualStrings(literalOf(define.get(components.Name).entity), "x");
        try expectEqualStrings(literalOf(define.get(components.Value).entity), "20");
        const x = then[1];
        try expectEqual(x.get(components.AstKind), .symbol);
        try expectEqualStrings(literalOf(x), "x");
    }
    const else_ = if_.get(components.Else).slice();
    try expectEqual(else_.len, 2);
    {
        const define = else_[0];
        try expectEqual(define.get(components.AstKind), .define);
        try expectEqualStrings(literalOf(define.get(components.Name).entity), "y");
        try expectEqualStrings(literalOf(define.get(components.Value).entity), "30");
        const y = else_[1];
        try expectEqual(y.get(components.AstKind), .symbol);
        try expectEqualStrings(literalOf(y), "y");
    }
}

test "analyze semantics if" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    const types = [_][]const u8{"i64"};
    const builtin_types = [_]Entity{builtins.I64};
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start() {s} {{
            \\  if 1 {{ 20 }} else {{ 30 }}
            \\}}
        , .{type_of}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
        try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
        try expectEqual(start.get(components.Parameters).len(), 0);
        try expectEqual(start.get(components.ReturnType).entity, builtin_types[i]);
        const body = start.get(components.Body).slice();
        try expectEqual(body.len, 1);
        const if_ = body[0];
        try expectEqual(if_.get(components.AstKind), .if_);
        try expectEqual(typeOf(if_), builtin_types[i]);
        const conditional = if_.get(components.Conditional).entity;
        try expectEqual(conditional.get(components.AstKind), .int);
        try expectEqualStrings(literalOf(conditional), "1");
        try expectEqual(typeOf(conditional), builtins.I32);
        const then = if_.get(components.Then).slice();
        try expectEqual(then.len, 1);
        const twenty = then[0];
        try expectEqual(twenty.get(components.AstKind), .int);
        try expectEqualStrings(literalOf(twenty), "20");
        try expectEqual(typeOf(twenty), builtin_types[i]);
        const else_ = if_.get(components.Else).slice();
        try expectEqual(else_.len, 1);
        const thirty = else_[0];
        try expectEqual(thirty.get(components.AstKind), .int);
        try expectEqualStrings(literalOf(thirty), "30");
        try expectEqual(typeOf(thirty), builtin_types[i]);
    }
}

test "analyze semantics if non constant conditional" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    const types = [_][]const u8{"i64"};
    const builtin_types = [_]Entity{builtins.I64};
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start() {s} {{
            \\  if f() {{ 20 }} else {{ 30 }}
            \\}}
            \\
            \\f() i32 {{
            \\  1
            \\}}
        , .{type_of}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
        try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
        try expectEqual(start.get(components.Parameters).len(), 0);
        try expectEqual(start.get(components.ReturnType).entity, builtin_types[i]);
        const f = blk: {
            const body = start.get(components.Body).slice();
            try expectEqual(body.len, 1);
            const if_ = body[0];
            try expectEqual(if_.get(components.AstKind), .if_);
            try expectEqual(typeOf(if_), builtin_types[i]);
            const conditional = if_.get(components.Conditional).entity;
            try expectEqual(conditional.get(components.AstKind), .call);
            try expectEqual(typeOf(conditional), builtins.I32);
            const f = conditional.get(components.Callable).entity;
            const then = if_.get(components.Then).slice();
            try expectEqual(then.len, 1);
            const twenty = then[0];
            try expectEqual(twenty.get(components.AstKind), .int);
            try expectEqualStrings(literalOf(twenty), "20");
            try expectEqual(typeOf(twenty), builtin_types[i]);
            const else_ = if_.get(components.Else).slice();
            try expectEqual(else_.len, 1);
            const thirty = else_[0];
            try expectEqual(thirty.get(components.AstKind), .int);
            try expectEqualStrings(literalOf(thirty), "30");
            try expectEqual(typeOf(thirty), builtin_types[i]);
            break :blk f;
        };
        try expectEqualStrings(literalOf(f.get(components.Module).entity), "foo");
        try expectEqualStrings(literalOf(f.get(components.Name).entity), "f");
        try expectEqual(f.get(components.Parameters).len(), 0);
        try expectEqual(f.get(components.ReturnType).entity, builtins.I32);
        const body = f.get(components.Body).slice();
        try expectEqual(body.len, 1);
    }
}

test "analyze semantics if with different type branches" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    const types = [_][]const u8{"i64"};
    const builtin_types = [_]Entity{builtins.I64};
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start() {s} {{
            \\  if 1 {{ 20 }} else {{ f() }}
            \\}}
            \\
            \\f() {s} {{
            \\  0
            \\}}
        , .{ type_of, type_of }));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
        try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
        try expectEqual(start.get(components.Parameters).len(), 0);
        try expectEqual(start.get(components.ReturnType).entity, builtin_types[i]);
        const body = start.get(components.Body).slice();
        try expectEqual(body.len, 1);
        const if_ = body[0];
        try expectEqual(if_.get(components.AstKind), .if_);
        try expectEqual(typeOf(if_), builtin_types[i]);
        const conditional = if_.get(components.Conditional).entity;
        try expectEqual(conditional.get(components.AstKind), .int);
        try expectEqualStrings(literalOf(conditional), "1");
        try expectEqual(typeOf(conditional), builtins.I32);
        const then = if_.get(components.Then).slice();
        try expectEqual(then.len, 1);
        const twenty = then[0];
        try expectEqual(twenty.get(components.AstKind), .int);
        try expectEqualStrings(literalOf(twenty), "20");
        try expectEqual(typeOf(twenty), builtin_types[i]);
        const else_ = if_.get(components.Else).slice();
        try expectEqual(else_.len, 1);
        const call = else_[0];
        try expectEqual(call.get(components.AstKind), .call);
    }
}

test "codegen if where then branch taken statically" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "i64", "i32", "u64", "u32", "f64", "f32" };
    const const_kinds = [_]components.WasmInstructionKind{
        .i64_const,
        .i32_const,
        .i64_const,
        .i32_const,
        .f64_const,
        .f32_const,
    };
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start() {s} {{
            \\  if 1 {{ 20 }} else {{ 30 }}
            \\}}
        , .{type_of}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        try codegen(module);
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        const start_instructions = start.get(components.WasmInstructions).slice();
        try expectEqual(start_instructions.len, 1);
        const constant = start_instructions[0];
        try expectEqual(constant.get(components.WasmInstructionKind), const_kinds[i]);
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "20");
    }
}

test "codegen if where else branch taken statically" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "i64", "i32", "u64", "u32", "f64", "f32" };
    const const_kinds = [_]components.WasmInstructionKind{
        .i64_const,
        .i32_const,
        .i64_const,
        .i32_const,
        .f64_const,
        .f32_const,
    };
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start() {s} {{
            \\  if 0 {{ 20 }} else {{ 30 }}
            \\}}
        , .{type_of}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        try codegen(module);
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        const start_instructions = start.get(components.WasmInstructions).slice();
        try expectEqual(start_instructions.len, 1);
        const constant = start_instructions[0];
        try expectEqual(constant.get(components.WasmInstructionKind), const_kinds[i]);
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "30");
    }
}

test "codegen if non const conditional" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "i64", "i32", "u64", "u32", "f64", "f32" };
    const b = codebase.get(components.Builtins);
    const builtin_types = [_]Entity{
        b.I64,
        b.I32,
        b.U64,
        b.U32,
        b.F64,
        b.F32,
    };
    const const_kinds = [_]components.WasmInstructionKind{
        .i64_const,
        .i32_const,
        .i64_const,
        .i32_const,
        .f64_const,
        .f32_const,
    };
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start() {s} {{
            \\  if f() {{ 20 }} else {{ 30 }}
            \\}}
            \\
            \\f() i32 {{ 1 }}
        , .{type_of}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        try codegen(module);
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        const start_instructions = start.get(components.WasmInstructions).slice();
        try expectEqual(start_instructions.len, 6);
        const call = start_instructions[0];
        try expectEqual(call.get(components.WasmInstructionKind), .call);
        const f = call.get(components.Callable).entity;
        const if_ = start_instructions[1];
        try expectEqual(if_.get(components.WasmInstructionKind), .if_);
        try expectEqual(if_.get(components.Type).entity, builtin_types[i]);
        const twenty = start_instructions[2];
        try expectEqual(twenty.get(components.WasmInstructionKind), const_kinds[i]);
        try expectEqualStrings(literalOf(twenty.get(components.Constant).entity), "20");
        try expectEqual(start_instructions[3].get(components.WasmInstructionKind), .else_);
        const thirty = start_instructions[4];
        try expectEqual(thirty.get(components.WasmInstructionKind), const_kinds[i]);
        try expectEqualStrings(literalOf(thirty.get(components.Constant).entity), "30");
        try expectEqual(start_instructions[5].get(components.WasmInstructionKind), .end);
        try expectEqualStrings(literalOf(f.get(components.Name).entity), "f");
        const f_instructions = f.get(components.WasmInstructions).slice();
        try expectEqual(f_instructions.len, 1);
        const constant = f_instructions[0];
        try expectEqual(constant.get(components.WasmInstructionKind), .i32_const);
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "1");
    }
}

test "print wasm if where then branch taken statically" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "i64", "i32", "u64", "u32", "f64", "f32" };
    const wasm_types = [_][]const u8{ "i64", "i32", "i64", "i32", "f64", "f32" };
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start() {s} {{
            \\  if 1 {{ 20 }} else {{ 30 }}
            \\}}
        , .{type_of}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        try codegen(module);
        const wasm = try printWasm(module);
        try expectEqualStrings(wasm, try std.fmt.allocPrint(arena.allocator(),
            \\(module
            \\
            \\  (func $foo/start (result {s})
            \\    ({s}.const 20))
            \\
            \\  (export "_start" (func $foo/start)))
        , .{ wasm_types[i], wasm_types[i] }));
    }
}

test "print wasm if where else branch taken statically" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "i64", "i32", "u64", "u32", "f64", "f32" };
    const wasm_types = [_][]const u8{ "i64", "i32", "i64", "i32", "f64", "f32" };
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start() {s} {{
            \\  if 0 {{ 20 }} else {{ 30 }}
            \\}}
        , .{type_of}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        try codegen(module);
        const wasm = try printWasm(module);
        try expectEqualStrings(wasm, try std.fmt.allocPrint(arena.allocator(),
            \\(module
            \\
            \\  (func $foo/start (result {s})
            \\    ({s}.const 30))
            \\
            \\  (export "_start" (func $foo/start)))
        , .{ wasm_types[i], wasm_types[i] }));
    }
}

test "print wasm if non const conditional" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "i64", "i32", "u64", "u32", "f64", "f32" };
    const wasm_types = [_][]const u8{ "i64", "i32", "i64", "i32", "f64", "f32" };
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start() {s} {{
            \\  if f() {{ 20 }} else {{ 30 }}
            \\}}
            \\
            \\f() i32 {{ 1 }}
        , .{type_of}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        try codegen(module);
        const wasm = try printWasm(module);
        try expectEqualStrings(wasm, try std.fmt.allocPrint(arena.allocator(),
            \\(module
            \\
            \\  (func $foo/start (result {s})
            \\    (call $foo/f)
            \\    if (result {s})
            \\    ({s}.const 20)
            \\    else
            \\    ({s}.const 30)
            \\    end)
            \\
            \\  (func $foo/f (result i32)
            \\    (i32.const 1))
            \\
            \\  (export "_start" (func $foo/start)))
        , .{ wasm_types[i], wasm_types[i], wasm_types[i], wasm_types[i] }));
    }
}
