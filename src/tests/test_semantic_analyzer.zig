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
            \\start = fn(): {s}
            \\  5
            \\end
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
            \\start = fn(): {s}
            \\  5.3
            \\end
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
            \\start = fn(): {s}
            \\  baz()
            \\end
            \\
            \\baz = fn(): {s}
            \\  10
            \\end
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
            \\start = fn(): {s}
            \\  bar.baz()
            \\end
        , .{type_of}));
        _ = try fs.newFile("bar.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\baz = fn(): {s}
            \\  10
            \\end
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
            \\start = fn(): {s}
            \\  x = 10
            \\  x
            \\end
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
            \\start = fn(): {s}
            \\  x = 10
            \\  y = 15
            \\  x
            \\end
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
            \\start = fn(): {s}
            \\  x: {s} = 10
            \\  x
            \\end
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
            \\start = fn(): {s}
            \\  x: {s} = 10
            \\  id(x)
            \\end
            \\
            \\id = fn(x: {s}): {s}
            \\  x
            \\end
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
            \\start = fn(): {s}
            \\  x = id(10)
            \\  id(25)
            \\end
            \\
            \\id = fn(x: {s}): {s}
            \\  x
            \\end
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
                \\start = fn(): {s}
                \\  x: {s} = 10
                \\  y: {s} = 32
                \\  x {s} y
                \\end
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
                \\start = fn(): i32
                \\  x: {s} = 10
                \\  y: {s} = 32
                \\  x {s} y
                \\end
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
            \\start = fn(): {s}
            \\  if 1 then 20 else 30 end
            \\end
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
            \\start = fn(): {s}
            \\  if f() then 20 else 30 end
            \\end
            \\
            \\f = fn(): i32
            \\  1
            \\end
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
            \\start = fn(): {s}
            \\  if 1 then 20 else f() end
            \\end
            \\
            \\f = fn(): {s}
            \\  0
            \\end
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
            \\start = fn(): {s}
            \\  x: {s} = 10
            \\  x = 3
            \\  x
            \\end
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

test "analyze semantics of while loop" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = fn(): i32
        \\  i = 0
        \\  while i < 10 do
        \\      i = i + 1
        \\  end
        \\  i
        \\end
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

test "analyze semantics of for loop" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = fn(): i32
        \\  sum = 0
        \\  for i in 0:10 do
        \\      sum = sum + i
        \\  end
        \\  sum
        \\end
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
    const range = iterator.get(components.Range);
    try expectEqual(typeOf(range.first), builtins.IntLiteral);
    try expectEqualStrings(literalOf(range.first), "0");
    try expectEqual(typeOf(range.last), builtins.IntLiteral);
    try expectEqualStrings(literalOf(range.last), "10");
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

test "analyze semantics of increment" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = fn(): i64
        \\  x = 0
        \\  x = x + 1
        \\  x
        \\end
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
        \\start = fn(): i64
        \\  a: i64 = 10
        \\  b = 0
        \\  b = a + b
        \\  b
        \\end
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

test "analyze semantics of pipeline" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\square = fn(x: i64): i64
        \\  x * x
        \\end
        \\
        \\start = fn(): i64
        \\  5 |> square()
        \\end
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
    const call = body[0];
    try expectEqual(call.get(components.AstKind), .call);
    const arguments = call.get(components.Arguments).slice();
    try expectEqual(arguments.len, 1);
    try expectEqual(typeOf(call), builtins.I64);
    const five = arguments[0];
    try expectEqual(typeOf(five), builtins.I64);
    try expectEqualStrings(literalOf(five), "5");
    const square = call.get(components.Callable).entity;
    try expectEqualStrings(literalOf(square.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(square.get(components.Name).entity), "square");
}

test "analyze semantics of pipeline with parenthesis omitted" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\square = fn(x: i64): i64
        \\  x * x
        \\end
        \\
        \\start = fn(): i64
        \\  5 |> square
        \\end
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
    const call = body[0];
    try expectEqual(call.get(components.AstKind), .call);
    const arguments = call.get(components.Arguments).slice();
    try expectEqual(arguments.len, 1);
    try expectEqual(typeOf(call), builtins.I64);
    const five = arguments[0];
    try expectEqual(typeOf(five), builtins.I64);
    try expectEqualStrings(literalOf(five), "5");
    const square = call.get(components.Callable).entity;
    try expectEqualStrings(literalOf(square.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(square.get(components.Name).entity), "square");
}

test "analyze semantics of pipeline with position specified" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\min = fn(x: i64, y: i64): i64
        \\  if x < y then x else y end
        \\end
        \\
        \\start = fn(): i64
        \\  5 |> min(3, _)
        \\end
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
    const call = body[0];
    try expectEqual(call.get(components.AstKind), .call);
    const arguments = call.get(components.Arguments).slice();
    try expectEqual(arguments.len, 2);
    try expectEqual(typeOf(call), builtins.I64);
    const three = arguments[0];
    try expectEqual(typeOf(three), builtins.I64);
    try expectEqualStrings(literalOf(three), "3");
    const five = arguments[1];
    try expectEqual(typeOf(five), builtins.I64);
    try expectEqualStrings(literalOf(five), "5");
    const min = call.get(components.Callable).entity;
    try expectEqualStrings(literalOf(min.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(min.get(components.Name).entity), "min");
}

test "analyze semantics of pipeline calling imported function" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\math = import("math.yeti")
        \\
        \\start = fn(): i64
        \\  5 |> math.min(3, _)
        \\end
    );
    _ = try fs.newFile("math.yeti",
        \\min = fn(x: i64, y: i64): i64
        \\  if x < y then x else y end
        \\end
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
    const call = body[0];
    try expectEqual(call.get(components.AstKind), .call);
    const arguments = call.get(components.Arguments).slice();
    try expectEqual(arguments.len, 2);
    try expectEqual(typeOf(call), builtins.I64);
    const three = arguments[0];
    try expectEqual(typeOf(three), builtins.I64);
    try expectEqualStrings(literalOf(three), "3");
    const five = arguments[1];
    try expectEqual(typeOf(five), builtins.I64);
    try expectEqualStrings(literalOf(five), "5");
    const min = call.get(components.Callable).entity;
    try expectEqualStrings(literalOf(min.get(components.Module).entity), "math");
    try expectEqualStrings(literalOf(min.get(components.Name).entity), "min");
}

test "analyze semantics of pipeline calling imported function with parenthesis omitted" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\math = import("math.yeti")
        \\
        \\start = fn(): i64
        \\  5 |> math.square
        \\end
    );
    _ = try fs.newFile("math.yeti",
        \\square = fn(x: i64): i64
        \\  x * x
        \\end
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
    const call = body[0];
    try expectEqual(call.get(components.AstKind), .call);
    const arguments = call.get(components.Arguments).slice();
    try expectEqual(arguments.len, 1);
    try expectEqual(typeOf(call), builtins.I64);
    const five = arguments[0];
    try expectEqual(typeOf(five), builtins.I64);
    try expectEqualStrings(literalOf(five), "5");
    const square = call.get(components.Callable).entity;
    try expectEqualStrings(literalOf(square.get(components.Module).entity), "math");
    try expectEqualStrings(literalOf(square.get(components.Name).entity), "square");
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
        \\g = fn(x: i64): i64
        \\  x + x
        \\end
        \\
        \\start = fn(): i64
        \\  bar.f(g(300))
        \\end
    );
    _ = try fs.newFile("bar.yeti",
        \\f = fn(x: i64): i64
        \\  x * x
        \\end
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
        \\start = fn(): i64
        \\  bar.f(bar.f(300))
        \\end
    );
    _ = try fs.newFile("bar.yeti",
        \\f = fn(x: i64): i64
        \\  x * x
        \\end
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

test "analyze semantics of foreign exports" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\square = fn(x: i64): i64
        \\  x * x
        \\end
        \\
        \\foreign_export(square)
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const square = top_level.findString("square").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(square.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(square.get(components.Name).entity), "square");
    try expectEqual(square.get(components.Parameters).len(), 1);
    try expectEqual(square.get(components.ReturnType).entity, builtins.I64);
    const body = square.get(components.Body).slice();
    try expectEqual(body.len, 1);
}

test "analyze semantics of foreign exports with recursion" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\fib = fn(n: i64): i64
        \\  if n < 2 then
        \\    0
        \\  else
        \\    fib(n - 1) + fib(n - 2)
        \\  end
        \\end
        \\
        \\foreign_export(fib)
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const fib = top_level.findString("fib").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(fib.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(fib.get(components.Name).entity), "fib");
    try expectEqual(fib.get(components.Parameters).len(), 1);
    try expectEqual(fib.get(components.ReturnType).entity, builtins.I64);
    const body = fib.get(components.Body).slice();
    try expectEqual(body.len, 1);
}

test "analyze semantics of foreign import" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\log = foreign_import("console", "log", Fn(value: i64): void)
        \\
        \\start = fn(): void
        \\  log(10)
        \\end
    );
    _ = try analyzeSemantics(codebase, fs, "foo.yeti");
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.Void);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 1);
    const log = body[0];
    try expectEqual(log.get(components.AstKind), .call);
    const arguments = log.get(components.Arguments).slice();
    try expectEqual(arguments.len, 1);
    const callable = log.get(components.Callable).entity;
    try expectEqualStrings(literalOf(callable.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(callable.get(components.Name).entity), "log");
    const parameters = callable.get(components.Parameters).slice();
    try expectEqual(parameters.len, 1);
    try expectEqual(callable.get(components.ReturnType).entity, builtins.Void);
    const parameter = parameters[0];
    try expectEqual(typeOf(parameter), builtins.I64);
    try expectEqualStrings(literalOf(parameter.get(components.Name).entity), "value");
}

test "analyze semantics of casting int literal to *i64" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = fn(): *i64
        \\  cast(*i64, 0)
        \\end
    );
    _ = try analyzeSemantics(codebase, fs, "foo.yeti");
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    const return_type = start.get(components.ReturnType).entity;
    try expectEqualStrings(literalOf(return_type), "*i64");
    try expectEqual(parentType(return_type), builtins.Ptr);
    try expectEqualStrings(literalOf(valueType(return_type)), "i64");
    try expectEqual(valueType(return_type), builtins.I64);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 1);
    const cast = body[0];
    try expectEqual(cast.get(components.AstKind), .cast);
    const pointer_type = typeOf(cast);
    try expectEqual(parentType(pointer_type), builtins.Ptr);
    try expectEqual(valueType(pointer_type), builtins.I64);
    const zero = cast.get(components.Value).entity;
    try expectEqual(zero.get(components.AstKind), .int);
    try expectEqual(typeOf(zero), builtins.I32);
    try expectEqualStrings(literalOf(zero), "0");
}

test "analyze semantics of casting i32 to *i64" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = fn(): *i64
        \\  i: i32 = 0
        \\  cast(*i64, i)
        \\end
    );
    _ = try analyzeSemantics(codebase, fs, "foo.yeti");
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    const return_type = start.get(components.ReturnType).entity;
    try expectEqualStrings(literalOf(return_type), "*i64");
    try expectEqual(parentType(return_type), builtins.Ptr);
    try expectEqualStrings(literalOf(valueType(return_type)), "i64");
    try expectEqual(valueType(return_type), builtins.I64);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 2);
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
    const cast = body[1];
    try expectEqual(cast.get(components.AstKind), .cast);
    const pointer_type = typeOf(cast);
    try expectEqual(parentType(pointer_type), builtins.Ptr);
    try expectEqual(valueType(pointer_type), builtins.I64);
    try expectEqual(cast.get(components.Value).entity, i);
}

test "analyze semantics of pointer store" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = fn(): void
        \\  ptr = cast(*i64, 0)
        \\  *ptr = 10
        \\end
    );
    _ = try analyzeSemantics(codebase, fs, "foo.yeti");
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.Void);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 2);
    const ptr = blk: {
        const define = body[0];
        try expectEqual(define.get(components.AstKind), .define);
        try expectEqual(typeOf(define), builtins.Void);
        const cast = define.get(components.Value).entity;
        try expectEqual(cast.get(components.AstKind), .cast);
        const pointer_type = typeOf(cast);
        try expectEqual(parentType(pointer_type), builtins.Ptr);
        try expectEqual(valueType(pointer_type), builtins.I64);
        const zero = cast.get(components.Value).entity;
        try expectEqual(zero.get(components.AstKind), .int);
        try expectEqual(typeOf(zero), builtins.I32);
        try expectEqualStrings(literalOf(zero), "0");
        const local = define.get(components.Local).entity;
        try expectEqual(local.get(components.AstKind), .local);
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "ptr");
        try expectEqual(typeOf(local), pointer_type);
        break :blk local;
    };
    const store = body[1];
    try expectEqual(store.get(components.AstKind), .intrinsic);
    try expectEqual(store.get(components.Intrinsic), .store);
    try expectEqual(typeOf(store), builtins.Void);
    const arguments = store.get(components.Arguments).slice();
    try expectEqual(arguments.len, 2);
    try expectEqual(arguments[0], ptr);
    const rhs = arguments[1];
    try expectEqual(rhs.get(components.AstKind), .int);
    try expectEqual(typeOf(rhs), builtins.I64);
    try expectEqualStrings(literalOf(rhs), "10");
}

test "analyze semantics of pointer load" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = fn(): i64
        \\  ptr = cast(*i64, 0)
        \\  *ptr
        \\end
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
    try expectEqual(body.len, 2);
    const ptr = blk: {
        const define = body[0];
        try expectEqual(define.get(components.AstKind), .define);
        try expectEqual(typeOf(define), builtins.Void);
        const cast = define.get(components.Value).entity;
        try expectEqual(cast.get(components.AstKind), .cast);
        const pointer_type = typeOf(cast);
        try expectEqual(parentType(pointer_type), builtins.Ptr);
        try expectEqual(valueType(pointer_type), builtins.I64);
        const zero = cast.get(components.Value).entity;
        try expectEqual(zero.get(components.AstKind), .int);
        try expectEqual(typeOf(zero), builtins.I32);
        try expectEqualStrings(literalOf(zero), "0");
        const local = define.get(components.Local).entity;
        try expectEqual(local.get(components.AstKind), .local);
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "ptr");
        try expectEqual(typeOf(local), pointer_type);
        break :blk local;
    };
    const load = body[1];
    try expectEqual(load.get(components.AstKind), .intrinsic);
    try expectEqual(load.get(components.Intrinsic), .load);
    try expectEqual(typeOf(load), builtins.I64);
    const arguments = load.get(components.Arguments).slice();
    try expectEqual(arguments.len, 1);
    try expectEqual(arguments[0], ptr);
}

test "analyze semantics of adding *i64 and int literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = fn(): *i64
        \\  ptr = cast(*i64, 0)
        \\  ptr + 1
        \\end
    );
    _ = try analyzeSemantics(codebase, fs, "foo.yeti");
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    const return_type = start.get(components.ReturnType).entity;
    try expectEqual(valueType(return_type), builtins.I64);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 2);
    {
        const define = body[0];
        try expectEqual(define.get(components.AstKind), .define);
        try expectEqual(typeOf(define), builtins.Void);
        const cast = define.get(components.Value).entity;
        try expectEqual(cast.get(components.AstKind), .cast);
        const pointer_type = typeOf(cast);
        try expectEqual(parentType(pointer_type), builtins.Ptr);
        try expectEqual(valueType(pointer_type), builtins.I64);
        const zero = cast.get(components.Value).entity;
        try expectEqual(zero.get(components.AstKind), .int);
        try expectEqual(typeOf(zero), builtins.I32);
        try expectEqualStrings(literalOf(zero), "0");
        const local = define.get(components.Local).entity;
        try expectEqual(local.get(components.AstKind), .local);
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "ptr");
        try expectEqual(typeOf(local), pointer_type);
    }
    const add = body[1];
    try expectEqual(add.get(components.AstKind), .intrinsic);
    try expectEqual(add.get(components.Intrinsic), .add_ptr_i32);
    try expectEqual(typeOf(add), return_type);
}

test "analyze semantics of subtracting *i64 and int literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = fn(): *i64
        \\  ptr = cast(*i64, 0)
        \\  ptr - 1
        \\end
    );
    _ = try analyzeSemantics(codebase, fs, "foo.yeti");
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    const return_type = start.get(components.ReturnType).entity;
    try expectEqual(valueType(return_type), builtins.I64);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 2);
    {
        const define = body[0];
        try expectEqual(define.get(components.AstKind), .define);
        try expectEqual(typeOf(define), builtins.Void);
        const cast = define.get(components.Value).entity;
        try expectEqual(cast.get(components.AstKind), .cast);
        const pointer_type = typeOf(cast);
        try expectEqual(parentType(pointer_type), builtins.Ptr);
        try expectEqual(valueType(pointer_type), builtins.I64);
        const zero = cast.get(components.Value).entity;
        try expectEqual(zero.get(components.AstKind), .int);
        try expectEqual(typeOf(zero), builtins.I32);
        try expectEqualStrings(literalOf(zero), "0");
        const local = define.get(components.Local).entity;
        try expectEqual(local.get(components.AstKind), .local);
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "ptr");
        try expectEqual(typeOf(local), pointer_type);
    }
    const add = body[1];
    try expectEqual(add.get(components.AstKind), .intrinsic);
    try expectEqual(add.get(components.Intrinsic), .subtract_ptr_i32);
    try expectEqual(typeOf(add), return_type);
}

test "analyze semantics of comparing two *i64" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = fn(): i32
        \\  ptr = cast(*i64, 0)
        \\  ptr == ptr
        \\end
    );
    _ = try analyzeSemantics(codebase, fs, "foo.yeti");
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    const return_type = start.get(components.ReturnType).entity;
    try expectEqual(return_type, builtins.I32);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 2);
    {
        const define = body[0];
        try expectEqual(define.get(components.AstKind), .define);
        try expectEqual(typeOf(define), builtins.Void);
        const cast = define.get(components.Value).entity;
        try expectEqual(cast.get(components.AstKind), .cast);
        const pointer_type = typeOf(cast);
        try expectEqual(parentType(pointer_type), builtins.Ptr);
        try expectEqual(valueType(pointer_type), builtins.I64);
        const zero = cast.get(components.Value).entity;
        try expectEqual(zero.get(components.AstKind), .int);
        try expectEqual(typeOf(zero), builtins.I32);
        try expectEqualStrings(literalOf(zero), "0");
        const local = define.get(components.Local).entity;
        try expectEqual(local.get(components.AstKind), .local);
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "ptr");
        try expectEqual(typeOf(local), pointer_type);
    }
    const equal = body[1];
    try expectEqual(equal.get(components.AstKind), .intrinsic);
    try expectEqual(equal.get(components.Intrinsic), .equal);
    try expectEqual(typeOf(equal), builtins.I32);
}

test "analyze semantics of vector load" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = fn(): i64x2
        \\  ptr = cast(*i64x2, 0)
        \\  *ptr
        \\end
    );
    _ = try analyzeSemantics(codebase, fs, "foo.yeti");
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.I64X2);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 2);
    const ptr = blk: {
        const define = body[0];
        try expectEqual(define.get(components.AstKind), .define);
        try expectEqual(typeOf(define), builtins.Void);
        const cast = define.get(components.Value).entity;
        try expectEqual(cast.get(components.AstKind), .cast);
        const pointer_type = typeOf(cast);
        try expectEqual(parentType(pointer_type), builtins.Ptr);
        try expectEqual(valueType(pointer_type), builtins.I64X2);
        const zero = cast.get(components.Value).entity;
        try expectEqual(zero.get(components.AstKind), .int);
        try expectEqual(typeOf(zero), builtins.I32);
        try expectEqualStrings(literalOf(zero), "0");
        const local = define.get(components.Local).entity;
        try expectEqual(local.get(components.AstKind), .local);
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "ptr");
        try expectEqual(typeOf(local), pointer_type);
        break :blk local;
    };
    const load = body[1];
    try expectEqual(load.get(components.AstKind), .intrinsic);
    try expectEqual(load.get(components.Intrinsic), .v128_load);
    try expectEqual(typeOf(load), builtins.I64X2);
    const arguments = load.get(components.Arguments).slice();
    try expectEqual(arguments.len, 1);
    try expectEqual(arguments[0], ptr);
}

test "analyze semantics of binary operators on two int vectors" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const b = codebase.get(components.Builtins);
    const type_strings = [_][]const u8{ "i64x2", "i32x4", "i16x8", "i8x16", "u64x2", "u32x4", "u16x8", "u8x16" };
    const builtins = [_]Entity{ b.I64X2, b.I32X4, b.I16X8, b.I8X16, b.U64X2, b.U32X4, b.U16X8, b.U8X16 };
    const op_strings = [_][]const u8{ "+", "-", "*" };
    const intrinsics = [_]components.Intrinsic{ .add, .subtract, .multiply };
    for (type_strings) |type_string, type_index| {
        for (op_strings) |op_string, i| {
            var fs = try MockFileSystem.init(&arena);
            _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
                \\start = fn(): {s}
                \\  v = *cast(*{s}, 0)
                \\  v {s} v
                \\end
            , .{ type_string, type_string, op_string }));
            _ = try analyzeSemantics(codebase, fs, "foo.yeti");
            const module = try analyzeSemantics(codebase, fs, "foo.yeti");
            const top_level = module.get(components.TopLevel);
            const start = top_level.findString("start").get(components.Overloads).slice()[0];
            try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
            try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
            try expectEqual(start.get(components.Parameters).len(), 0);
            try expectEqual(start.get(components.ReturnType).entity, builtins[type_index]);
            const body = start.get(components.Body).slice();
            try expectEqual(body.len, 2);
            const v = blk: {
                const define = body[0];
                try expectEqual(define.get(components.AstKind), .define);
                try expectEqual(typeOf(define), b.Void);
                const load = define.get(components.Value).entity;
                try expectEqual(load.get(components.AstKind), .intrinsic);
                try expectEqual(load.get(components.Intrinsic), .v128_load);
                try expectEqual(typeOf(load), builtins[type_index]);
                const arguments = load.get(components.Arguments).slice();
                try expectEqual(arguments.len, 1);
                const cast = arguments[0];
                try expectEqual(cast.get(components.AstKind), .cast);
                const pointer_type = typeOf(cast);
                try expectEqual(parentType(pointer_type), b.Ptr);
                try expectEqual(valueType(pointer_type), builtins[type_index]);
                const zero = cast.get(components.Value).entity;
                try expectEqual(zero.get(components.AstKind), .int);
                try expectEqual(typeOf(zero), b.I32);
                try expectEqualStrings(literalOf(zero), "0");
                const local = define.get(components.Local).entity;
                try expectEqual(local.get(components.AstKind), .local);
                try expectEqualStrings(literalOf(local.get(components.Name).entity), "v");
                try expectEqual(typeOf(local), builtins[type_index]);
                break :blk local;
            };
            const intrinsic = body[1];
            try expectEqual(intrinsic.get(components.AstKind), .intrinsic);
            try expectEqual(intrinsic.get(components.Intrinsic), intrinsics[i]);
            try expectEqual(typeOf(intrinsic), builtins[type_index]);
            const intrinsic_arguments = intrinsic.get(components.Arguments).slice();
            try expectEqual(intrinsic_arguments.len, 2);
            try expectEqual(intrinsic_arguments[0], v);
            try expectEqual(intrinsic_arguments[1], v);
        }
    }
}

test "analyze semantics of binary operators on two float vectors" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const b = codebase.get(components.Builtins);
    const type_strings = [_][]const u8{ "f64x2", "f32x4" };
    const builtins = [_]Entity{ b.F64X2, b.F32X4 };
    const op_strings = [_][]const u8{ "+", "-", "*", "/" };
    const intrinsics = [_]components.Intrinsic{ .add, .subtract, .multiply, .divide };
    for (type_strings) |type_string, type_index| {
        for (op_strings) |op_string, i| {
            var fs = try MockFileSystem.init(&arena);
            _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
                \\start = fn(): {s}
                \\  v = *cast(*{s}, 0)
                \\  v {s} v
                \\end
            , .{ type_string, type_string, op_string }));
            _ = try analyzeSemantics(codebase, fs, "foo.yeti");
            const module = try analyzeSemantics(codebase, fs, "foo.yeti");
            const top_level = module.get(components.TopLevel);
            const start = top_level.findString("start").get(components.Overloads).slice()[0];
            try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
            try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
            try expectEqual(start.get(components.Parameters).len(), 0);
            try expectEqual(start.get(components.ReturnType).entity, builtins[type_index]);
            const body = start.get(components.Body).slice();
            try expectEqual(body.len, 2);
            const v = blk: {
                const define = body[0];
                try expectEqual(define.get(components.AstKind), .define);
                try expectEqual(typeOf(define), b.Void);
                const load = define.get(components.Value).entity;
                try expectEqual(load.get(components.AstKind), .intrinsic);
                try expectEqual(load.get(components.Intrinsic), .v128_load);
                try expectEqual(typeOf(load), builtins[type_index]);
                const arguments = load.get(components.Arguments).slice();
                try expectEqual(arguments.len, 1);
                const cast = arguments[0];
                try expectEqual(cast.get(components.AstKind), .cast);
                const pointer_type = typeOf(cast);
                try expectEqual(parentType(pointer_type), b.Ptr);
                try expectEqual(valueType(pointer_type), builtins[type_index]);
                const zero = cast.get(components.Value).entity;
                try expectEqual(zero.get(components.AstKind), .int);
                try expectEqual(typeOf(zero), b.I32);
                try expectEqualStrings(literalOf(zero), "0");
                const local = define.get(components.Local).entity;
                try expectEqual(local.get(components.AstKind), .local);
                try expectEqualStrings(literalOf(local.get(components.Name).entity), "v");
                try expectEqual(typeOf(local), builtins[type_index]);
                break :blk local;
            };
            const intrinsic = body[1];
            try expectEqual(intrinsic.get(components.AstKind), .intrinsic);
            try expectEqual(intrinsic.get(components.Intrinsic), intrinsics[i]);
            try expectEqual(typeOf(intrinsic), builtins[type_index]);
            const intrinsic_arguments = intrinsic.get(components.Arguments).slice();
            try expectEqual(intrinsic_arguments.len, 2);
            try expectEqual(intrinsic_arguments[0], v);
            try expectEqual(intrinsic_arguments[1], v);
        }
    }
}

test "analyze semantics of vector store" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = fn(): void
        \\  ptr = cast(*i64x2, 0)
        \\  *ptr = *ptr
        \\end
    );
    _ = try analyzeSemantics(codebase, fs, "foo.yeti");
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.Void);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 2);
    const ptr = blk: {
        const define = body[0];
        try expectEqual(define.get(components.AstKind), .define);
        try expectEqual(typeOf(define), builtins.Void);
        const cast = define.get(components.Value).entity;
        try expectEqual(cast.get(components.AstKind), .cast);
        const pointer_type = typeOf(cast);
        try expectEqual(parentType(pointer_type), builtins.Ptr);
        try expectEqual(valueType(pointer_type), builtins.I64X2);
        const zero = cast.get(components.Value).entity;
        try expectEqual(zero.get(components.AstKind), .int);
        try expectEqual(typeOf(zero), builtins.I32);
        try expectEqualStrings(literalOf(zero), "0");
        const local = define.get(components.Local).entity;
        try expectEqual(local.get(components.AstKind), .local);
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "ptr");
        try expectEqual(typeOf(local), pointer_type);
        break :blk local;
    };
    const store = body[1];
    try expectEqual(store.get(components.AstKind), .intrinsic);
    try expectEqual(store.get(components.Intrinsic), .v128_store);
    try expectEqual(typeOf(store), builtins.Void);
    const arguments = store.get(components.Arguments).slice();
    try expectEqual(arguments.len, 2);
    try expectEqual(arguments[0], ptr);
    const load = arguments[1];
    try expectEqual(load.get(components.AstKind), .intrinsic);
    try expectEqual(load.get(components.Intrinsic), .v128_load);
    try expectEqual(typeOf(load), builtins.I64X2);
    const load_arguments = load.get(components.Arguments).slice();
    try expectEqual(load_arguments.len, 1);
    try expectEqual(load_arguments[0], ptr);
}

test "analyze semantics of struct" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\Rectangle = struct
        \\  width: f64
        \\  height: f64
        \\end
        \\
        \\start = fn(): Rectangle
        \\  Rectangle(10, 30)
        \\end
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
        \\Rectangle = struct
        \\  width: f64
        \\  height: f64
        \\end
        \\
        \\start = fn(): f64
        \\  r = Rectangle(10, 30)
        \\  r.width
        \\end
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
        \\Rectangle = struct
        \\  width: f64
        \\  height: f64
        \\end
        \\
        \\start = fn(): Rectangle
        \\  r = Rectangle(10, 30)
        \\  r.width = 45
        \\  r
        \\end
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

test "analyze semantics of plus equal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    const builtins = codebase.get(components.Builtins);
    _ = try fs.newFile("foo.yeti",
        \\start = fn(): i64
        \\  x = 0
        \\  x += 1
        \\  x
        \\end
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
        \\start = fn(): i64
        \\  x = 0
        \\  x *= 1
        \\  x
        \\end
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

test "analyze semantics of string literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = fn(): []u8
        \\  "hello world"
        \\end
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

test "analyze semantics of char literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = fn(): u8
        \\  'h'
        \\end
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
