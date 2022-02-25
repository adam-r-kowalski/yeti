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

test "tokenize for" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code = "for";
    var tokens = try tokenize(module, code);
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .for_);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 0, .row = 0 },
            .end = .{ .column = 3, .row = 0 },
        });
    }
    try expectEqual(tokens.next(), null);
}

test "parse for loop" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\start(): i32 {
        \\  sum = 0
        \\  for i in 0:10 {
        \\      sum = sum + i
        \\  }
        \\  sum
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
    try expectEqualStrings(literalOf(define.get(components.Name).entity), "sum");
    try expectEqualStrings(literalOf(define.get(components.Value).entity), "0");
    const for_ = body[1];
    try expectEqual(for_.get(components.AstKind), .for_);
    const iterator = for_.get(components.Iterator).entity;
    try expectEqual(iterator.get(components.AstKind), .range);
    try expectEqualStrings(literalOf(iterator.get(components.First).entity), "0");
    try expectEqualStrings(literalOf(iterator.get(components.Last).entity), "10");
    const i = for_.get(components.LoopVariable).entity;
    try expectEqualStrings(literalOf(i), "i");
    const for_body = for_.get(components.Body).slice();
    try expectEqual(for_body.len, 1);
    const assign = for_body[0];
    try expectEqual(assign.get(components.AstKind), .define);
    try expectEqualStrings(literalOf(assign.get(components.Name).entity), "sum");
    const value = assign.get(components.Value).entity;
    try expectEqual(value.get(components.AstKind), .binary_op);
    try expectEqual(value.get(components.BinaryOp), .add);
    const sum = body[2];
    try expectEqual(sum.get(components.AstKind), .symbol);
    try expectEqualStrings(literalOf(sum), "sum");
}

test "analyze semantics of for loop" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start(): i32 {
        \\  sum = 0
        \\  for i in 0:10 {
        \\      sum = sum + i
        \\  }
        \\  sum
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
    const sum = blk: {
        const define = body[0];
        try expectEqual(define.get(components.AstKind), .define);
        try expectEqual(typeOf(define), builtins.Void);
        try expectEqualStrings(literalOf(define.get(components.Value).entity), "0");
        const local = define.get(components.Local).entity;
        try expectEqual(local.get(components.AstKind), .local);
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "sum");
        try expectEqual(typeOf(local), builtins.I32);
        break :blk local;
    };
    const for_ = body[1];
    try expectEqual(for_.get(components.AstKind), .for_);
    try expectEqual(typeOf(for_), builtins.Void);
    const i = blk: {
        const define = for_.get(components.LoopVariable).entity;
        try expectEqual(define.get(components.AstKind), .define);
        try expectEqual(typeOf(define), builtins.Void);
        try expectEqualStrings(literalOf(define.get(components.Value).entity), "0");
        const local = define.get(components.Local).entity;
        try expectEqual(local.get(components.AstKind), .local);
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "i");
        try expectEqual(typeOf(local), builtins.I32);
        break :blk local;
    };
    const iterator = for_.get(components.Iterator).entity;
    try expectEqual(iterator.get(components.AstKind), .range);
    const first = iterator.get(components.First).entity;
    try expectEqual(typeOf(first), builtins.I32);
    try expectEqualStrings(literalOf(first), "0");
    const last = iterator.get(components.Last).entity;
    try expectEqual(typeOf(last), builtins.I32);
    try expectEqualStrings(literalOf(last), "10");
    const for_body = for_.get(components.Body).slice();
    try expectEqual(for_body.len, 1);
    const assign = for_body[0];
    try expectEqual(assign.get(components.AstKind), .assign);
    try expectEqual(typeOf(assign), builtins.Void);
    try expectEqual(assign.get(components.Local).entity, sum);
    const value = assign.get(components.Value).entity;
    try expectEqual(value.get(components.AstKind), .intrinsic);
    try expectEqual(value.get(components.Intrinsic), .add);
    const arguments = value.get(components.Arguments).slice();
    try expectEqual(arguments.len, 2);
    try expectEqual(arguments[0], sum);
    try expectEqual(arguments[1], i);
    try expectEqual(body[2], sum);
}

test "analyze semantics of for loop implicit range start" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start(): i32 {
        \\  sum = 0
        \\  for i in :10 {
        \\      sum = sum + i
        \\  }
        \\  sum
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
    const sum = blk: {
        const define = body[0];
        try expectEqual(define.get(components.AstKind), .define);
        try expectEqual(typeOf(define), builtins.Void);
        try expectEqualStrings(literalOf(define.get(components.Value).entity), "0");
        const local = define.get(components.Local).entity;
        try expectEqual(local.get(components.AstKind), .local);
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "sum");
        try expectEqual(typeOf(local), builtins.I32);
        break :blk local;
    };
    const for_ = body[1];
    try expectEqual(for_.get(components.AstKind), .for_);
    try expectEqual(typeOf(for_), builtins.Void);
    const i = blk: {
        const define = for_.get(components.LoopVariable).entity;
        try expectEqual(define.get(components.AstKind), .define);
        try expectEqual(typeOf(define), builtins.Void);
        try expectEqualStrings(literalOf(define.get(components.Value).entity), "0");
        const local = define.get(components.Local).entity;
        try expectEqual(local.get(components.AstKind), .local);
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "i");
        try expectEqual(typeOf(local), builtins.I32);
        break :blk local;
    };
    const iterator = for_.get(components.Iterator).entity;
    try expectEqual(iterator.get(components.AstKind), .range);
    const first = iterator.get(components.First).entity;
    try expectEqual(typeOf(first), builtins.I32);
    try expectEqualStrings(literalOf(first), "0");
    const last = iterator.get(components.Last).entity;
    try expectEqual(typeOf(last), builtins.I32);
    try expectEqualStrings(literalOf(last), "10");
    const for_body = for_.get(components.Body).slice();
    try expectEqual(for_body.len, 1);
    const assign = for_body[0];
    try expectEqual(assign.get(components.AstKind), .assign);
    try expectEqual(typeOf(assign), builtins.Void);
    try expectEqual(assign.get(components.Local).entity, sum);
    const value = assign.get(components.Value).entity;
    try expectEqual(value.get(components.AstKind), .intrinsic);
    try expectEqual(value.get(components.Intrinsic), .add);
    const arguments = value.get(components.Arguments).slice();
    try expectEqual(arguments.len, 2);
    try expectEqual(arguments[0], sum);
    try expectEqual(arguments[1], i);
    try expectEqual(body[2], sum);
}

test "analyze semantics of for loop non int literal last" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start(): i32 {
        \\  sum = 0
        \\  n = 10
        \\  for i in 0:n {
        \\      sum = sum + i
        \\  }
        \\  sum
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
    try expectEqual(body.len, 4);
    const sum = blk: {
        const define = body[0];
        try expectEqual(define.get(components.AstKind), .define);
        try expectEqual(typeOf(define), builtins.Void);
        try expectEqualStrings(literalOf(define.get(components.Value).entity), "0");
        const local = define.get(components.Local).entity;
        try expectEqual(local.get(components.AstKind), .local);
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "sum");
        try expectEqual(typeOf(local), builtins.I32);
        break :blk local;
    };
    const n = blk: {
        const define = body[1];
        try expectEqual(define.get(components.AstKind), .define);
        try expectEqual(typeOf(define), builtins.Void);
        try expectEqualStrings(literalOf(define.get(components.Value).entity), "10");
        const local = define.get(components.Local).entity;
        try expectEqual(local.get(components.AstKind), .local);
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "n");
        try expectEqual(typeOf(local), builtins.I32);
        break :blk local;
    };
    const for_ = body[2];
    try expectEqual(for_.get(components.AstKind), .for_);
    try expectEqual(typeOf(for_), builtins.Void);
    const i = blk: {
        const define = for_.get(components.LoopVariable).entity;
        try expectEqual(define.get(components.AstKind), .define);
        try expectEqual(typeOf(define), builtins.Void);
        try expectEqualStrings(literalOf(define.get(components.Value).entity), "0");
        const local = define.get(components.Local).entity;
        try expectEqual(local.get(components.AstKind), .local);
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "i");
        try expectEqual(typeOf(local), builtins.I32);
        break :blk local;
    };
    const iterator = for_.get(components.Iterator).entity;
    try expectEqual(iterator.get(components.AstKind), .range);
    const first = iterator.get(components.First).entity;
    try expectEqual(typeOf(first), builtins.I32);
    try expectEqualStrings(literalOf(first), "0");
    try expectEqual(iterator.get(components.Last).entity, n);
    const for_body = for_.get(components.Body).slice();
    try expectEqual(for_body.len, 1);
    const assign = for_body[0];
    try expectEqual(assign.get(components.AstKind), .assign);
    try expectEqual(typeOf(assign), builtins.Void);
    try expectEqual(assign.get(components.Local).entity, sum);
    const value = assign.get(components.Value).entity;
    try expectEqual(value.get(components.AstKind), .intrinsic);
    try expectEqual(value.get(components.Intrinsic), .add);
    const arguments = value.get(components.Arguments).slice();
    try expectEqual(arguments.len, 2);
    try expectEqual(arguments[0], sum);
    try expectEqual(arguments[1], i);
    try expectEqual(body[3], sum);
}

test "codegen for loop" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start(): i32 {
        \\  sum = 0
        \\  for i in 0:10 {
        \\    sum = sum + i
        \\  }
        \\  sum 
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    const start_instructions = start.get(components.WasmInstructions).slice();
    try expectEqual(start_instructions.len, 22);
    // TODO: test that proper for loop instructions are generated
}

test "print wasm for loop" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start(): i32 {
        \\  sum = 0
        \\  for i in 0:10 {
        \\    sum = sum + i
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
        \\  (func $foo/start (result i32)
        \\    (local $sum i32)
        \\    (local $i i32)
        \\    (i32.const 0)
        \\    (local.set $sum)
        \\    (i32.const 0)
        \\    (local.set $i)
        \\    block $.label.0
        \\    loop $.label.1
        \\    (local.get $i)
        \\    (i32.const 10)
        \\    i32.ge_s
        \\    br_if $.label.0
        \\    (local.get $sum)
        \\    (local.get $i)
        \\    i32.add
        \\    (local.set $sum)
        \\    (i32.const 1)
        \\    (local.get $i)
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

test "print wasm properly infer type for for loop" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start(): i64 {
        \\  sum = 0
        \\  for i in 0:10 {
        \\    sum += 1
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
        \\    i32.ge_s
        \\    br_if $.label.0
        \\    (local.get $sum)
        \\    (i64.const 1)
        \\    i64.add
        \\    (local.set $sum)
        \\    (i32.const 1)
        \\    (local.get $i)
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

test "print wasm for loop non int literal last" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start(): i64 {
        \\  sum = 0
        \\  n = 10
        \\  for i in 0:n {
        \\    sum += 1
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
        \\    i32.ge_s
        \\    br_if $.label.0
        \\    (local.get $sum)
        \\    (i64.const 1)
        \\    i64.add
        \\    (local.set $sum)
        \\    (i32.const 1)
        \\    (local.get $i)
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

test "print wasm for loop non int literal last implicit range start" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start(): i64 {
        \\  sum = 0
        \\  n = 10
        \\  for i in :n {
        \\    sum += 1
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
        \\    i32.ge_s
        \\    br_if $.label.0
        \\    (local.get $sum)
        \\    (i64.const 1)
        \\    i64.add
        \\    (local.set $sum)
        \\    (i32.const 1)
        \\    (local.get $i)
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

test "print wasm for loop non int literal first" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start(): i64 {
        \\  sum = 0
        \\  n = 0
        \\  for i in n:10 {
        \\    sum += 1
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
        \\    i32.ge_s
        \\    br_if $.label.0
        \\    (local.get $sum)
        \\    (i64.const 1)
        \\    i64.add
        \\    (local.set $sum)
        \\    (i32.const 1)
        \\    (local.get $i)
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

test "print wasm for loop non int literal first and last" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start(): i64 {
        \\  sum = 0
        \\  first = 0
        \\  last = 10
        \\  for i in first:last {
        \\    sum += 1
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
        \\    i32.ge_s
        \\    br_if $.label.0
        \\    (local.get $sum)
        \\    (i64.const 1)
        \\    i64.add
        \\    (local.set $sum)
        \\    (i32.const 1)
        \\    (local.get $i)
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
