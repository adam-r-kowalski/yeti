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
        \\start() i32 {
        \\  sum = 0
        \\  for(0:10) {
        \\      sum += it
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
    const for_body = for_.get(components.Body).slice();
    try expectEqual(for_body.len, 1);
    const plus_equal = for_body[0];
    const arguments = plus_equal.get(components.Arguments).slice();
    try expectEqualStrings(literalOf(arguments[0]), "sum");
    try expectEqualStrings(literalOf(arguments[1]), "it");
    const sum = body[2];
    try expectEqual(sum.get(components.AstKind), .symbol);
    try expectEqualStrings(literalOf(sum), "sum");
}

test "parse for loop named loop variable" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\start() i32 {
        \\  sum = 0
        \\  for(0:10) (i) {
        \\    sum += i
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
    const plus_equal = for_body[0];
    const arguments = plus_equal.get(components.Arguments).slice();
    try expectEqualStrings(literalOf(arguments[0]), "sum");
    try expectEqualStrings(literalOf(arguments[1]), "i");
    const sum = body[2];
    try expectEqual(sum.get(components.AstKind), .symbol);
    try expectEqualStrings(literalOf(sum), "sum");
}

test "parse for loop named loop variable omit parens" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\start() i32 {
        \\  sum = 0
        \\  for(0:10) i {
        \\    sum += i
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
    const plus_equal = for_body[0];
    const arguments = plus_equal.get(components.Arguments).slice();
    try expectEqualStrings(literalOf(arguments[0]), "sum");
    try expectEqualStrings(literalOf(arguments[1]), "i");
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
        \\start() i32 {
        \\  sum = 0
        \\  for(0:10) {
        \\    sum += it
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
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "it");
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

test "analyze semantics of for loop explicit loop variable" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start() i32 {
        \\  sum = 0
        \\  for(0:10) (i) {
        \\    sum += i
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

test "analyze semantics of for loop explicit loop variable omit paren" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start() i32 {
        \\  sum = 0
        \\  for(0:10) i {
        \\    sum += i
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
        \\start() i32 {
        \\  sum = 0
        \\  for(:10) {
        \\    sum += it
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
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "it");
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
        \\start() i32 {
        \\  sum = 0
        \\  n = 10
        \\  for(0:n) {
        \\    sum += it
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
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "it");
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
        \\start() i32 {
        \\  sum = 0
        \\  for(0:10) {
        \\    sum += it
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
    {
        const i32_const = start_instructions[0];
        try expectEqual(i32_const.get(components.WasmInstructionKind), .i32_const);
        try expectEqualStrings(literalOf(i32_const.get(components.Constant).entity), "0");
        const local_set = start_instructions[1];
        try expectEqual(local_set.get(components.WasmInstructionKind), .local_set);
        const local = local_set.get(components.Local).entity;
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "sum");
    }
    {
        const i32_const = start_instructions[2];
        try expectEqual(i32_const.get(components.WasmInstructionKind), .i32_const);
        try expectEqualStrings(literalOf(i32_const.get(components.Constant).entity), "0");
        const local_set = start_instructions[3];
        try expectEqual(local_set.get(components.WasmInstructionKind), .local_set);
        const local = local_set.get(components.Local).entity;
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "it");
    }
    {
        const block = start_instructions[4];
        try expectEqual(block.get(components.WasmInstructionKind), .block);
        try expectEqual(block.get(components.Label).value, 0);
        const loop = start_instructions[5];
        try expectEqual(loop.get(components.WasmInstructionKind), .loop);
        try expectEqual(loop.get(components.Label).value, 1);
        const local_get = start_instructions[6];
        try expectEqual(local_get.get(components.WasmInstructionKind), .local_get);
        const local = local_get.get(components.Local).entity;
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "it");
        const i32_const = start_instructions[7];
        try expectEqual(i32_const.get(components.WasmInstructionKind), .i32_const);
        try expectEqualStrings(literalOf(i32_const.get(components.Constant).entity), "10");
        try expectEqual(start_instructions[8].get(components.WasmInstructionKind), .i32_ge);
        const br_if = start_instructions[9];
        try expectEqual(br_if.get(components.WasmInstructionKind), .br_if);
        try expectEqual(br_if.get(components.Label).value, 0);
    }
    const sum = blk: {
        const local_get = start_instructions[10];
        try expectEqual(local_get.get(components.WasmInstructionKind), .local_get);
        const local = local_get.get(components.Local).entity;
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "sum");
        break :blk local;
    };
    {
        const local_get = start_instructions[11];
        try expectEqual(local_get.get(components.WasmInstructionKind), .local_get);
        const local = local_get.get(components.Local).entity;
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "it");
    }
    try expectEqual(start_instructions[12].get(components.WasmInstructionKind), .i32_add);
    {
        const local_set = start_instructions[13];
        try expectEqual(local_set.get(components.WasmInstructionKind), .local_set);
        try expectEqual(local_set.get(components.Local).entity, sum);
    }
    {
        const i32_const = start_instructions[14];
        try expectEqual(i32_const.get(components.WasmInstructionKind), .i32_const);
        try expectEqualStrings(literalOf(i32_const.get(components.Constant).entity), "1");
    }
    const i = blk: {
        const local_get = start_instructions[15];
        try expectEqual(local_get.get(components.WasmInstructionKind), .local_get);
        const local = local_get.get(components.Local).entity;
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "it");
        break :blk local;
    };
    try expectEqual(start_instructions[16].get(components.WasmInstructionKind), .i32_add);
    {
        const local_set = start_instructions[17];
        try expectEqual(local_set.get(components.WasmInstructionKind), .local_set);
        try expectEqual(local_set.get(components.Local).entity, i);
    }
    {
        const br = start_instructions[18];
        try expectEqual(br.get(components.WasmInstructionKind), .br);
        try expectEqual(br.get(components.Label).value, 1);
    }
    try expectEqual(start_instructions[19].get(components.WasmInstructionKind), .end);
    try expectEqual(start_instructions[20].get(components.WasmInstructionKind), .end);
    const local_get = start_instructions[21];
    try expectEqual(local_get.get(components.WasmInstructionKind), .local_get);
    const local = local_get.get(components.Local).entity;
    try expectEqualStrings(literalOf(local.get(components.Name).entity), "sum");
}

test "print wasm for loop" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start() i32 {
        \\  sum = 0
        \\  for(0:10) {
        \\    sum += it
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
        \\    (local $it i32)
        \\    (i32.const 0)
        \\    (local.set $sum)
        \\    (i32.const 0)
        \\    (local.set $it)
        \\    block $.label.0
        \\    loop $.label.1
        \\    (local.get $it)
        \\    (i32.const 10)
        \\    i32.ge_s
        \\    br_if $.label.0
        \\    (local.get $sum)
        \\    (local.get $it)
        \\    i32.add
        \\    (local.set $sum)
        \\    (i32.const 1)
        \\    (local.get $it)
        \\    i32.add
        \\    (local.set $it)
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
        \\start() i64 {
        \\  sum = 0
        \\  for(0:10) {
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
        \\    (local $it i32)
        \\    (i64.const 0)
        \\    (local.set $sum)
        \\    (i32.const 0)
        \\    (local.set $it)
        \\    block $.label.0
        \\    loop $.label.1
        \\    (local.get $it)
        \\    (i32.const 10)
        \\    i32.ge_s
        \\    br_if $.label.0
        \\    (local.get $sum)
        \\    (i64.const 1)
        \\    i64.add
        \\    (local.set $sum)
        \\    (i32.const 1)
        \\    (local.get $it)
        \\    i32.add
        \\    (local.set $it)
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
        \\start() i64 {
        \\  sum = 0
        \\  n = 10
        \\  for(0:n) {
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
        \\    (local $it i32)
        \\    (i64.const 0)
        \\    (local.set $sum)
        \\    (i32.const 0)
        \\    (local.set $it)
        \\    block $.label.0
        \\    loop $.label.1
        \\    (local.get $it)
        \\    (i32.const 10)
        \\    i32.ge_s
        \\    br_if $.label.0
        \\    (local.get $sum)
        \\    (i64.const 1)
        \\    i64.add
        \\    (local.set $sum)
        \\    (i32.const 1)
        \\    (local.get $it)
        \\    i32.add
        \\    (local.set $it)
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
        \\start() i64 {
        \\  sum = 0
        \\  n = 10
        \\  for(:n) {
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
        \\    (local $it i32)
        \\    (i64.const 0)
        \\    (local.set $sum)
        \\    (i32.const 0)
        \\    (local.set $it)
        \\    block $.label.0
        \\    loop $.label.1
        \\    (local.get $it)
        \\    (i32.const 10)
        \\    i32.ge_s
        \\    br_if $.label.0
        \\    (local.get $sum)
        \\    (i64.const 1)
        \\    i64.add
        \\    (local.set $sum)
        \\    (i32.const 1)
        \\    (local.get $it)
        \\    i32.add
        \\    (local.set $it)
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
        \\start() i64 {
        \\  sum = 0
        \\  n = 0
        \\  for(n:10) {
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
        \\    (local $it i32)
        \\    (i64.const 0)
        \\    (local.set $sum)
        \\    (i32.const 0)
        \\    (local.set $it)
        \\    block $.label.0
        \\    loop $.label.1
        \\    (local.get $it)
        \\    (i32.const 10)
        \\    i32.ge_s
        \\    br_if $.label.0
        \\    (local.get $sum)
        \\    (i64.const 1)
        \\    i64.add
        \\    (local.set $sum)
        \\    (i32.const 1)
        \\    (local.get $it)
        \\    i32.add
        \\    (local.set $it)
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
        \\start() i64 {
        \\  sum = 0
        \\  first = 0
        \\  last = 10
        \\  for(first:last) {
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
        \\    (local $it i32)
        \\    (i64.const 0)
        \\    (local.set $sum)
        \\    (i32.const 0)
        \\    (local.set $it)
        \\    block $.label.0
        \\    loop $.label.1
        \\    (local.get $it)
        \\    (i32.const 10)
        \\    i32.ge_s
        \\    br_if $.label.0
        \\    (local.get $sum)
        \\    (i64.const 1)
        \\    i64.add
        \\    (local.set $sum)
        \\    (i32.const 1)
        \\    (local.get $it)
        \\    i32.add
        \\    (local.set $it)
        \\    br $.label.1
        \\    end $.label.1
        \\    end $.label.0
        \\    (local.get $sum))
        \\
        \\  (export "_start" (func $foo/start)))
    );
}
