const std = @import("std");
const Arena = std.heap.ArenaAllocator;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const yeti = @import("yeti");
const initCodebase = yeti.initCodebase;
const MockFileSystem = yeti.FileSystem;
const components = yeti.components;
const analyzeSemantics = yeti.analyzeSemantics;
const literalOf = yeti.test_utils.literalOf;
const typeOf = yeti.test_utils.typeOf;
const parentType = yeti.test_utils.parentType;
const valueType = yeti.test_utils.valueType;
const Entity = yeti.ecs.Entity;

test "analyze semantics int literal" {
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
            \\  5
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
        const int_literal = body[0];
        try expectEqual(int_literal.get(components.AstKind), .int);
        try expectEqual(typeOf(int_literal), builtin_types[i]);
        try expectEqualStrings(literalOf(int_literal), "5");
    }
}

test "analyze semantics float literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    const types = [_][]const u8{ "f64", "f32" };
    const builtin_types = [_]Entity{ builtins.F64, builtins.F32 };
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start(): {s} {{
            \\  5.3
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
        const float_literal = body[0];
        try expectEqual(float_literal.get(components.AstKind), .float);
        try expectEqual(typeOf(float_literal), builtin_types[i]);
        try expectEqualStrings(literalOf(float_literal), "5.3");
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

test "analyze semantics define" {
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
            \\  x = 10
            \\  x
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
        try expectEqual(body.len, 2);
        const define = body[0];
        try expectEqual(define.get(components.AstKind), .define);
        try expectEqual(typeOf(define), builtins.Void);
        try expectEqualStrings(literalOf(define.get(components.Value).entity), "10");
        const x = define.get(components.Local).entity;
        try expectEqualStrings(literalOf(x.get(components.Name).entity), "x");
        try expectEqual(typeOf(x), builtin_types[i]);
        try expectEqual(body[1], x);
    }
}

test "analyze semantics two defines" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    const types = [_][]const u8{ "f64", "f32" };
    const builtin_types = [_]Entity{ builtins.F64, builtins.F32 };
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start(): {s} {{
            \\  x = 10
            \\  y = 15
            \\  x
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
        {
            const define = body[1];
            try expectEqual(define.get(components.AstKind), .define);
            try expectEqual(typeOf(define), builtins.Void);
            try expectEqualStrings(literalOf(define.get(components.Value).entity), "15");
            const local = define.get(components.Local).entity;
            try expectEqual(local.get(components.AstKind), .local);
            try expectEqualStrings(literalOf(local.get(components.Name).entity), "y");
            try expectEqual(typeOf(local), builtins.I32);
        }
        try expectEqual(body[2], x);
    }
}

test "analyze semantics define with explicit float type" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    const types = [_][]const u8{ "f64", "f32" };
    const builtin_types = [_]Entity{ builtins.F64, builtins.F32 };
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start(): {s} {{
            \\  x: {s} = 10
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
        try expectEqual(body.len, 2);
        const define = body[0];
        try expectEqual(define.get(components.AstKind), .define);
        try expectEqual(typeOf(define), builtins.Void);
        try expectEqualStrings(literalOf(define.get(components.Value).entity), "10");
        const x = define.get(components.Local).entity;
        try expectEqual(x.get(components.AstKind), .local);
        try expectEqualStrings(literalOf(x.get(components.Name).entity), "x");
        try expectEqual(typeOf(x), builtin_types[i]);
        try expectEqual(body[1], x);
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

test "analyze semantics binary op two comptime known" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    const types = [_][]const u8{ "i64", "i32", "i16", "i8", "u64", "u32", "u16", "u8", "f64", "f32" };
    const builtin_types = [_]Entity{ builtins.I64, builtins.I32, builtins.I16, builtins.I8, builtins.U64, builtins.U32, builtins.U16, builtins.U8, builtins.F64, builtins.F32 };
    const op_strings = [_][]const u8{ "+", "-", "*", "/" };
    const intrinsics = [_]components.Intrinsic{ .add, .subtract, .multiply, .divide };
    for (op_strings) |op_string, op_index| {
        for (types) |type_of, i| {
            var fs = try MockFileSystem.init(&arena);
            _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
                \\start(): {s} {{
                \\  x: {s} = 10
                \\  y: {s} = 32
                \\  x {s} y
                \\}}
            , .{ type_of, type_of, type_of, op_string }));
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
            const y = blk: {
                const define = body[1];
                try expectEqual(define.get(components.AstKind), .define);
                try expectEqual(typeOf(define), builtins.Void);
                try expectEqualStrings(literalOf(define.get(components.Value).entity), "32");
                const local = define.get(components.Local).entity;
                try expectEqual(local.get(components.AstKind), .local);
                try expectEqualStrings(literalOf(local.get(components.Name).entity), "y");
                try expectEqual(typeOf(local), builtin_types[i]);
                break :blk local;
            };
            const intrinsic = body[2];
            try expectEqual(intrinsic.get(components.AstKind), .intrinsic);
            try expectEqual(intrinsic.get(components.Intrinsic), intrinsics[op_index]);
            try expectEqual(typeOf(intrinsic), builtin_types[i]);
            const arguments = intrinsic.get(components.Arguments).slice();
            try expectEqual(arguments.len, 2);
            try expectEqual(arguments[0], x);
            try expectEqual(arguments[1], y);
        }
    }
}

test "analyze semantics comparison op two comptime known" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    const types = [_][]const u8{ "i64", "i32", "i16", "i8", "u64", "u32", "u16", "u8", "f64", "f32" };
    const builtin_types = [_]Entity{ builtins.I64, builtins.I32, builtins.I16, builtins.I8, builtins.U64, builtins.U32, builtins.U16, builtins.U8, builtins.F64, builtins.F32 };
    const op_strings = [_][]const u8{ "==", "!=", "<", "<=", ">", ">=" };
    const intrinsics = [_]components.Intrinsic{
        .equal,
        .not_equal,
        .less_than,
        .less_equal,
        .greater_than,
        .greater_equal,
    };
    for (op_strings) |op_string, op_index| {
        for (types) |type_of, i| {
            var fs = try MockFileSystem.init(&arena);
            _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
                \\start(): i32 {{
                \\  x: {s} = 10
                \\  y: {s} = 32
                \\  x {s} y
                \\}}
            , .{ type_of, type_of, op_string }));
            const module = try analyzeSemantics(codebase, fs, "foo.yeti");
            const top_level = module.get(components.TopLevel);
            const start = top_level.findString("start").get(components.Overloads).slice()[0];
            try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
            try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
            try expectEqual(start.get(components.Parameters).len(), 0);
            try expectEqual(start.get(components.ReturnType).entity, builtins.I32);
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
            const y = blk: {
                const define = body[1];
                try expectEqual(define.get(components.AstKind), .define);
                try expectEqual(typeOf(define), builtins.Void);
                try expectEqualStrings(literalOf(define.get(components.Value).entity), "32");
                const local = define.get(components.Local).entity;
                try expectEqual(local.get(components.AstKind), .local);
                try expectEqualStrings(literalOf(local.get(components.Name).entity), "y");
                try expectEqual(typeOf(local), builtin_types[i]);
                break :blk local;
            };
            const intrinsic = body[2];
            try expectEqual(intrinsic.get(components.AstKind), .intrinsic);
            try expectEqual(intrinsic.get(components.Intrinsic), intrinsics[op_index]);
            try expectEqual(typeOf(intrinsic), builtins.I32);
            const arguments = intrinsic.get(components.Arguments).slice();
            try expectEqual(arguments.len, 2);
            try expectEqual(arguments[0], x);
            try expectEqual(arguments[1], y);
        }
    }
}

test "analyze semantics if then else" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    const types = [_][]const u8{"i64"};
    const builtin_types = [_]Entity{builtins.I64};
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start(): {s} {{
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

test "analyze semantics if then else non constant conditional" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    const types = [_][]const u8{"i64"};
    const builtin_types = [_]Entity{builtins.I64};
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start(): {s} {{
            \\  if f() {{ 20 }} else {{ 30 }}
            \\}}
            \\
            \\f(): i32 {{
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

test "analyze semantics if then else with different type branches" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    const types = [_][]const u8{"i64"};
    const builtin_types = [_]Entity{builtins.I64};
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start(): {s} {{
            \\  if 1 then 20 else f() end
            \\}}
            \\
            \\f(): {s} {{
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

test "analyze semantics of char literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start(): u8 {
        \\  'h'
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
    try expectEqual(body.len, 1);
    const h = body[0];
    try expectEqual(h.get(components.AstKind), .int);
    try expectEqual(typeOf(h), builtins.U8);
    try expectEqualStrings(literalOf(h), "104");
}
