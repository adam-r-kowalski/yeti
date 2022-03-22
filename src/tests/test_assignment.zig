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

test "parse plus equal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\start() u64 {
        \\  x = 10
        \\  x += 1
        \\  x
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
    try expectEqualStrings(literalOf(define.get(components.Name).entity), "x");
    try expectEqualStrings(literalOf(define.get(components.Value).entity), "10");
    const plus_equal = body[1];
    try expectEqual(plus_equal.get(components.AstKind), .plus_equal);
    const arguments = plus_equal.get(components.Arguments).slice();
    try expectEqualStrings(literalOf(arguments[0]), "x");
    try expectEqualStrings(literalOf(arguments[1]), "1");
    const x = body[2];
    try expectEqual(x.get(components.AstKind), .symbol);
    try expectEqualStrings(literalOf(x), "x");
}

test "parse times equal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\start() u64 {
        \\  x = 10
        \\  x *= 1
        \\  x
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
    try expectEqualStrings(literalOf(define.get(components.Name).entity), "x");
    try expectEqualStrings(literalOf(define.get(components.Value).entity), "10");
    const times_equal = body[1];
    try expectEqual(times_equal.get(components.AstKind), .times_equal);
    const arguments = times_equal.get(components.Arguments).slice();
    try expectEqualStrings(literalOf(arguments[0]), "x");
    try expectEqualStrings(literalOf(arguments[1]), "1");
    const x = body[2];
    try expectEqual(x.get(components.AstKind), .symbol);
    try expectEqualStrings(literalOf(x), "x");
}

test "analyze semantics of assignment" {
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
            \\  x: {s} = 10
            \\  x = 3
            \\  x
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
        try expectEqual(body.len, 3);
        const x = blk: {
            const define = body[0];
            try expectEqual(define.get(components.AstKind), .define);
            try expectEqual(typeOf(define), builtins.Void);
            try expectEqualStrings(literalOf(define.get(components.Value).entity), "10");
            const local = define.get(components.Local).entity;
            try expectEqual(local.get(components.AstKind), .local);
            try expectEqualStrings(literalOf(local.get(components.Name).entity), "x");
            try expectEqual(typeOf(local), builtin_types[i]);
            break :blk local;
        };
        const assign = body[1];
        try expectEqual(assign.get(components.AstKind), .assign);
        try expectEqual(typeOf(assign), builtins.Void);
        try expectEqual(assign.get(components.Local).entity, x);
        try expectEqualStrings(literalOf(assign.get(components.Value).entity), "3");
        try expectEqual(body[2], x);
    }
}

test "analyze semantics of increment" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start() i64 {
        \\  x = 0
        \\  x = x + 1
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
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 3);
    const x = blk: {
        const define = body[0];
        try expectEqual(define.get(components.AstKind), .define);
        try expectEqual(typeOf(define), builtins.Void);
        try expectEqualStrings(literalOf(define.get(components.Value).entity), "0");
        const local = define.get(components.Local).entity;
        try expectEqual(local.get(components.AstKind), .local);
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "x");
        try expectEqual(typeOf(local), builtins.I64);
        break :blk local;
    };
    const assign = body[1];
    try expectEqual(assign.get(components.AstKind), .assign);
    try expectEqual(typeOf(assign), builtins.Void);
    try expectEqual(assign.get(components.Local).entity, x);
    const intrinsic = assign.get(components.Value).entity;
    try expectEqual(intrinsic.get(components.AstKind), .intrinsic);
    try expectEqual(intrinsic.get(components.Intrinsic), .add);
    try expectEqual(typeOf(intrinsic), builtins.I64);
    const arguments = intrinsic.get(components.Arguments).slice();
    try expectEqual(arguments.len, 2);
    try expectEqual(arguments[0], x);
    const rhs = arguments[1];
    try expectEqual(rhs.get(components.AstKind), .int);
    try expectEqualStrings(literalOf(rhs), "1");
    try expectEqual(body[2], x);
}

test "analyze semantics of add between typed and inferred" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start() i64 {
        \\  a: i64 = 10
        \\  b = 0
        \\  b = a + b
        \\  b
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
    try expectEqual(body.len, 4);
    const a = blk: {
        const define = body[0];
        try expectEqual(define.get(components.AstKind), .define);
        try expectEqual(typeOf(define), builtins.Void);
        try expectEqualStrings(literalOf(define.get(components.Value).entity), "10");
        const local = define.get(components.Local).entity;
        try expectEqual(local.get(components.AstKind), .local);
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "a");
        try expectEqual(typeOf(local), builtins.I64);
        break :blk local;
    };
    const b = blk: {
        const define = body[1];
        try expectEqual(define.get(components.AstKind), .define);
        try expectEqual(typeOf(define), builtins.Void);
        try expectEqualStrings(literalOf(define.get(components.Value).entity), "0");
        const local = define.get(components.Local).entity;
        try expectEqual(local.get(components.AstKind), .local);
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "b");
        try expectEqual(typeOf(local), builtins.I64);
        break :blk local;
    };
    const assign = body[2];
    try expectEqual(assign.get(components.AstKind), .assign);
    try expectEqual(typeOf(assign), builtins.Void);
    try expectEqual(assign.get(components.Local).entity, b);
    const intrinsic = assign.get(components.Value).entity;
    try expectEqual(intrinsic.get(components.AstKind), .intrinsic);
    try expectEqual(intrinsic.get(components.Intrinsic), .add);
    try expectEqual(typeOf(intrinsic), builtins.I64);
    const arguments = intrinsic.get(components.Arguments).slice();
    try expectEqual(arguments.len, 2);
    try expectEqual(arguments[0], a);
    try expectEqual(arguments[1], b);
    try expectEqual(body[3], b);
}

test "analyze semantics of plus equal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    const builtins = codebase.get(components.Builtins);
    _ = try fs.newFile("foo.yeti",
        \\start() i64 {
        \\  x = 0
        \\  x += 1
        \\  x
        \\}
    );
    _ = try analyzeSemantics(codebase, fs, "foo.yeti");
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.I64);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 3);
    const x = blk: {
        const define = body[0];
        try expectEqual(define.get(components.AstKind), .define);
        try expectEqual(typeOf(define), builtins.Void);
        const local = define.get(components.Local).entity;
        try expectEqual(local.get(components.AstKind), .local);
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "x");
        try expectEqualStrings(literalOf(define.get(components.Value).entity), "0");
        break :blk local;
    };
    const assign = body[1];
    try expectEqual(assign.get(components.AstKind), .assign);
    try expectEqual(typeOf(assign), builtins.Void);
    try expectEqual(assign.get(components.Local).entity, x);
    const add = assign.get(components.Value).entity;
    try expectEqual(add.get(components.AstKind), .intrinsic);
    try expectEqual(add.get(components.Intrinsic), .add);
    const arguments = add.get(components.Arguments).slice();
    try expectEqual(arguments[0], x);
    try expectEqualStrings(literalOf(arguments[1]), "1");
    try expectEqual(body[2], x);
}

test "analyze semantics of times equal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    const builtins = codebase.get(components.Builtins);
    _ = try fs.newFile("foo.yeti",
        \\start() i64 {
        \\  x = 0
        \\  x *= 1
        \\  x
        \\}
    );
    _ = try analyzeSemantics(codebase, fs, "foo.yeti");
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.I64);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 3);
    const x = blk: {
        const define = body[0];
        try expectEqual(define.get(components.AstKind), .define);
        try expectEqual(typeOf(define), builtins.Void);
        const local = define.get(components.Local).entity;
        try expectEqual(local.get(components.AstKind), .local);
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "x");
        try expectEqualStrings(literalOf(define.get(components.Value).entity), "0");
        break :blk local;
    };
    const assign = body[1];
    try expectEqual(assign.get(components.AstKind), .assign);
    try expectEqual(typeOf(assign), builtins.Void);
    try expectEqual(assign.get(components.Local).entity, x);
    const multiply = assign.get(components.Value).entity;
    try expectEqual(multiply.get(components.AstKind), .intrinsic);
    try expectEqual(multiply.get(components.Intrinsic), .multiply);
    const arguments = multiply.get(components.Arguments).slice();
    try expectEqual(arguments[0], x);
    try expectEqualStrings(literalOf(arguments[1]), "1");
    try expectEqual(body[2], x);
}

test "codegen assignment" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "i64", "i32", "u64", "u32", "f64", "f32" };
    const const_kinds = [_]components.WasmInstructionKind{ .i64_const, .i32_const, .i64_const, .i32_const, .f64_const, .f32_const };
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start() {s} {{
            \\  x: {s} = 10
            \\  x = 3
            \\  x
            \\}}
        , .{ type_, type_ }));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        try codegen(module);
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        const start_instructions = start.get(components.WasmInstructions).slice();
        try expectEqual(start_instructions.len, 5);
        {
            const constant = start_instructions[0];
            try expectEqual(constant.get(components.WasmInstructionKind), const_kinds[i]);
            try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "10");
        }
        {
            const local_set = start_instructions[1];
            try expectEqual(local_set.get(components.WasmInstructionKind), .local_set);
            const local = local_set.get(components.Local).entity;
            try expectEqualStrings(literalOf(local.get(components.Name).entity), "x");
        }
        {
            const constant = start_instructions[2];
            try expectEqual(constant.get(components.WasmInstructionKind), const_kinds[i]);
            try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "3");
        }
        {
            const local_set = start_instructions[3];
            try expectEqual(local_set.get(components.WasmInstructionKind), .local_set);
            const local = local_set.get(components.Local).entity;
            try expectEqualStrings(literalOf(local.get(components.Name).entity), "x");
        }
        const local_get = start_instructions[4];
        try expectEqual(local_get.get(components.WasmInstructionKind), .local_get);
        const local = local_get.get(components.Local).entity;
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "x");
    }
}

test "print wasm assignment" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "i64", "i32", "u64", "u32", "f64", "f32" };
    const wasm_types = [_][]const u8{ "i64", "i32", "i64", "i32", "f64", "f32" };
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start() {s} {{
            \\  x: {s} = 10
            \\  x = 3
            \\  x
            \\}}
        , .{ type_of, type_of }));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        try codegen(module);
        const wasm = try printWasm(module);
        try expectEqualStrings(wasm, try std.fmt.allocPrint(arena.allocator(),
            \\(module
            \\
            \\  (func $foo/start (result {s})
            \\    (local $x {s})
            \\    ({s}.const 10)
            \\    (local.set $x)
            \\    ({s}.const 3)
            \\    (local.set $x)
            \\    (local.get $x))
            \\
            \\  (export "_start" (func $foo/start)))
        , .{ wasm_types[i], wasm_types[i], wasm_types[i], wasm_types[i] }));
    }
}
