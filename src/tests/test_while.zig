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

test "tokenize while" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code = "while";
    var tokens = try tokenize(module, code);
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .while_);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 0, .row = 0 },
            .end = .{ .column = 5, .row = 0 },
        });
    }
    try expectEqual(tokens.next(), null);
}

test "parse while" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\start() i32 {
        \\  i = 0
        \\  while(i < 10) {
        \\      i = i + 1
        \\  }
        \\  i
        \\}
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start");
    const overloads = start.get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const body = overloads[0].get(components.Body).slice();
    try expectEqual(body.len, 3);
    const define = body[0];
    try expectEqual(define.get(components.AstKind), .define);
    try expectEqualStrings(literalOf(define.get(components.Name).entity), "i");
    try expectEqualStrings(literalOf(define.get(components.Value).entity), "0");
    const while_ = body[1];
    try expectEqual(while_.get(components.AstKind), .while_);
    const conditional = while_.get(components.Conditional).entity;
    try expectEqual(conditional.get(components.AstKind), .binary_op);
    try expectEqual(conditional.get(components.BinaryOp), .less_than);
    const while_body = while_.get(components.Body).slice();
    try expectEqual(while_body.len, 1);
    const assign = while_body[0];
    try expectEqual(assign.get(components.AstKind), .define);
    try expectEqualStrings(literalOf(assign.get(components.Name).entity), "i");
    const value = assign.get(components.Value).entity;
    try expectEqual(value.get(components.AstKind), .binary_op);
    try expectEqual(value.get(components.BinaryOp), .add);
    const i = body[2];
    try expectEqual(i.get(components.AstKind), .symbol);
    try expectEqualStrings(literalOf(i), "i");
}

test "analyze semantics of while loop" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start() i32 {
        \\  i = 0
        \\  while(i < 10) {
        \\      i = i + 1
        \\  }
        \\  i
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.I32);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 3);
    const i = blk: {
        const define = body[0];
        try expectEqual(define.get(components.AstKind), .define);
        try expectEqual(typeOf(define), builtins.Void);
        try expectEqualStrings(literalOf(define.get(components.Value).entity), "0");
        const local = define.get(components.Local).entity;
        try expectEqual(local.get(components.AstKind), .local);
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "i");
        try expectEqual(typeOf(local), builtins.I32);
        break :blk local;
    };
    const while_ = body[1];
    try expectEqual(while_.get(components.AstKind), .while_);
    try expectEqual(typeOf(while_), builtins.Void);
    const conditional = while_.get(components.Conditional).entity;
    try expectEqual(conditional.get(components.AstKind), .intrinsic);
    try expectEqual(typeOf(conditional), builtins.I32);
    const while_body = while_.get(components.Body).slice();
    try expectEqual(while_body.len, 1);
    const assign = while_body[0];
    try expectEqual(assign.get(components.AstKind), .assign);
    try expectEqual(typeOf(assign), builtins.Void);
    try expectEqual(assign.get(components.Local).entity, i);
    const value = assign.get(components.Value).entity;
    try expectEqual(value.get(components.AstKind), .intrinsic);
    try expectEqual(body[2], i);
}

test "codegen while loop" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start() i32 {
        \\  i = 0
        \\  while(i < 10) {
        \\    i = i + 1
        \\  }
        \\  i
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    const start_instructions = start.get(components.WasmInstructions).slice();
    try expectEqual(start_instructions.len, 17);
    {
        const i32_const = start_instructions[0];
        try expectEqual(i32_const.get(components.WasmInstructionKind), .i32_const);
        try expectEqualStrings(literalOf(i32_const.get(components.Constant).entity), "0");
        const local_set = start_instructions[1];
        try expectEqual(local_set.get(components.WasmInstructionKind), .local_set);
        const local = local_set.get(components.Local).entity;
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "i");
    }
    {
        const block = start_instructions[2];
        try expectEqual(block.get(components.WasmInstructionKind), .block);
        try expectEqual(block.get(components.Label).value, 0);
        const loop = start_instructions[3];
        try expectEqual(loop.get(components.WasmInstructionKind), .loop);
        try expectEqual(loop.get(components.Label).value, 1);
        const local_get = start_instructions[4];
        try expectEqual(local_get.get(components.WasmInstructionKind), .local_get);
        const local = local_get.get(components.Local).entity;
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "i");
        const i32_const = start_instructions[5];
        try expectEqual(i32_const.get(components.WasmInstructionKind), .i32_const);
        try expectEqualStrings(literalOf(i32_const.get(components.Constant).entity), "10");
        try expectEqual(start_instructions[6].get(components.WasmInstructionKind), .i32_lt);
        try expectEqual(start_instructions[7].get(components.WasmInstructionKind), .i32_eqz);
        const br_if = start_instructions[8];
        try expectEqual(br_if.get(components.WasmInstructionKind), .br_if);
        try expectEqual(br_if.get(components.Label).value, 0);
    }
    {
        const local_get = start_instructions[9];
        try expectEqual(local_get.get(components.WasmInstructionKind), .local_get);
        const local = local_get.get(components.Local).entity;
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "i");
        const i32_const = start_instructions[10];
        try expectEqual(i32_const.get(components.WasmInstructionKind), .i32_const);
        try expectEqualStrings(literalOf(i32_const.get(components.Constant).entity), "1");
        try expectEqual(start_instructions[11].get(components.WasmInstructionKind), .i32_add);
        const local_set = start_instructions[12];
        try expectEqual(local_set.get(components.WasmInstructionKind), .local_set);
        try expectEqual(local_set.get(components.Local).entity, local);
        const br = start_instructions[13];
        try expectEqual(br.get(components.WasmInstructionKind), .br);
        try expectEqual(br.get(components.Label).value, 1);
        try expectEqual(start_instructions[14].get(components.WasmInstructionKind), .end);
        try expectEqual(start_instructions[15].get(components.WasmInstructionKind), .end);
    }
    const local_get = start_instructions[16];
    try expectEqual(local_get.get(components.WasmInstructionKind), .local_get);
    const local = local_get.get(components.Local).entity;
    try expectEqualStrings(literalOf(local.get(components.Name).entity), "i");
}

test "codegen while loop proper type inference" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start() i64 {
        \\  i = 0
        \\  while(i < 10) {
        \\    i = i + 1
        \\  }
        \\  i
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    const start_instructions = start.get(components.WasmInstructions).slice();
    try expectEqual(start_instructions.len, 17);
    {
        const i64_const = start_instructions[0];
        try expectEqual(i64_const.get(components.WasmInstructionKind), .i64_const);
        try expectEqualStrings(literalOf(i64_const.get(components.Constant).entity), "0");
        const local_set = start_instructions[1];
        try expectEqual(local_set.get(components.WasmInstructionKind), .local_set);
        const local = local_set.get(components.Local).entity;
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "i");
    }
    {
        const block = start_instructions[2];
        try expectEqual(block.get(components.WasmInstructionKind), .block);
        try expectEqual(block.get(components.Label).value, 0);
        const loop = start_instructions[3];
        try expectEqual(loop.get(components.WasmInstructionKind), .loop);
        try expectEqual(loop.get(components.Label).value, 1);
        const local_get = start_instructions[4];
        try expectEqual(local_get.get(components.WasmInstructionKind), .local_get);
        const local = local_get.get(components.Local).entity;
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "i");
        const i64_const = start_instructions[5];
        try expectEqual(i64_const.get(components.WasmInstructionKind), .i64_const);
        try expectEqualStrings(literalOf(i64_const.get(components.Constant).entity), "10");
        try expectEqual(start_instructions[6].get(components.WasmInstructionKind), .i64_lt);
        try expectEqual(start_instructions[7].get(components.WasmInstructionKind), .i32_eqz);
        const br_if = start_instructions[8];
        try expectEqual(br_if.get(components.WasmInstructionKind), .br_if);
        try expectEqual(br_if.get(components.Label).value, 0);
    }
    {
        const local_get = start_instructions[9];
        try expectEqual(local_get.get(components.WasmInstructionKind), .local_get);
        const local = local_get.get(components.Local).entity;
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "i");
        const i64_const = start_instructions[10];
        try expectEqual(i64_const.get(components.WasmInstructionKind), .i64_const);
        try expectEqualStrings(literalOf(i64_const.get(components.Constant).entity), "1");
        try expectEqual(start_instructions[11].get(components.WasmInstructionKind), .i64_add);
        const local_set = start_instructions[12];
        try expectEqual(local_set.get(components.WasmInstructionKind), .local_set);
        try expectEqual(local_set.get(components.Local).entity, local);
        const br = start_instructions[13];
        try expectEqual(br.get(components.WasmInstructionKind), .br);
        try expectEqual(br.get(components.Label).value, 1);
        try expectEqual(start_instructions[14].get(components.WasmInstructionKind), .end);
        try expectEqual(start_instructions[15].get(components.WasmInstructionKind), .end);
    }
    const local_get = start_instructions[16];
    try expectEqual(local_get.get(components.WasmInstructionKind), .local_get);
    const local = local_get.get(components.Local).entity;
    try expectEqualStrings(literalOf(local.get(components.Name).entity), "i");
}

test "print wasm while loop" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start() i32 {
        \\  i = 0
        \\  while(i < 10) {
        \\      i = i + 1
        \\  }
        \\  i
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/start (result i32)
        \\    (local $i i32)
        \\    (i32.const 0)
        \\    (local.set $i)
        \\    block $.label.0
        \\    loop $.label.1
        \\    (local.get $i)
        \\    (i32.const 10)
        \\    i32.lt_s
        \\    i32.eqz
        \\    br_if $.label.0
        \\    (local.get $i)
        \\    (i32.const 1)
        \\    i32.add
        \\    (local.set $i)
        \\    br $.label.1
        \\    end $.label.1
        \\    end $.label.0
        \\    (local.get $i))
        \\
        \\  (export "_start" (func $foo/start)))
    );
}

test "print wasm properly infer type for while loop" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start() i64 {
        \\  sum = 0
        \\  i = 0
        \\  while(i < 10) {
        \\    sum += 1
        \\    i += 1
        \\  }
        \\  sum
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/start (result i64)
        \\    (local $sum i64)
        \\    (local $i i32)
        \\    (i64.const 0)
        \\    (local.set $sum)
        \\    (i32.const 0)
        \\    (local.set $i)
        \\    block $.label.0
        \\    loop $.label.1
        \\    (local.get $i)
        \\    (i32.const 10)
        \\    i32.lt_s
        \\    i32.eqz
        \\    br_if $.label.0
        \\    (local.get $sum)
        \\    (i64.const 1)
        \\    i64.add
        \\    (local.set $sum)
        \\    (local.get $i)
        \\    (i32.const 1)
        \\    i32.add
        \\    (local.set $i)
        \\    br $.label.1
        \\    end $.label.1
        \\    end $.label.0
        \\    (local.get $sum))
        \\
        \\  (export "_start" (func $foo/start)))
    );
}
