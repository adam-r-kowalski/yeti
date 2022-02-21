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

test "tokenize mulitine function with binary op" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\sum_of_squares(x: u64, y: u64): u64 {
        \\  x2 = x * x
        \\  x2 = y * y
        \\  x2 + y2
        \\}
    ;
    var tokens = try tokenize(module, code);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .left_paren);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .colon);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .comma);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .colon);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .right_paren);
    try expectEqual(tokens.next().?.get(components.TokenKind), .colon);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .left_brace);
    try expectEqual(tokens.next().?.get(components.TokenKind), .new_line);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .equal);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .times);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .new_line);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .equal);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .times);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .new_line);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .plus);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .new_line);
    try expectEqual(tokens.next().?.get(components.TokenKind), .right_brace);
    try expectEqual(tokens.next(), null);
}

test "greater operators" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code = "> >= = == : < <= >> <<";
    var tokens = try tokenize(module, code);
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .greater_than);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 0, .row = 0 },
            .end = .{ .column = 1, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .greater_equal);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 2, .row = 0 },
            .end = .{ .column = 4, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .equal);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 5, .row = 0 },
            .end = .{ .column = 6, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .equal_equal);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 7, .row = 0 },
            .end = .{ .column = 9, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .colon);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 10, .row = 0 },
            .end = .{ .column = 11, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .less_than);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 12, .row = 0 },
            .end = .{ .column = 13, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .less_equal);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 14, .row = 0 },
            .end = .{ .column = 16, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .greater_greater);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 17, .row = 0 },
            .end = .{ .column = 19, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .less_less);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 20, .row = 0 },
            .end = .{ .column = 22, .row = 0 },
        });
    }
    try expectEqual(tokens.next(), null);
}

test "parse grouping with parenthesis" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\start(): u64 {
        \\  (5 + 10) * 3
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
    const multiply = body[0];
    try expectEqual(multiply.get(components.AstKind), .binary_op);
    try expectEqual(multiply.get(components.BinaryOp), .multiply);
    const multiply_arguments = multiply.get(components.Arguments).slice();
    const add = multiply_arguments[0];
    try expectEqual(add.get(components.AstKind), .binary_op);
    try expectEqual(add.get(components.BinaryOp), .add);
    const add_arguments = add.get(components.Arguments).slice();
    try expectEqualStrings(literalOf(add_arguments[0]), "5");
    try expectEqualStrings(literalOf(add_arguments[1]), "10");
    try expectEqualStrings(literalOf(multiply_arguments[1]), "3");
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

test "codegen binary op two literals" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "i64", "i32", "i16", "i8", "u64", "u32", "u16", "u8", "f64", "f32" };
    const const_kinds = [_]components.WasmInstructionKind{ .i64_const, .i32_const, .i32_const, .i32_const, .i64_const, .i32_const, .i32_const, .i32_const, .f64_const, .f32_const };
    const op_strings = [_][]const u8{ "+", "-", "*", "/" };
    const results = [_][10][]const u8{
        [_][]const u8{ "10", "10", "10", "10", "10", "10", "10", "10", "1.0e+01", "1.0e+01" },
        [_][]const u8{ "6", "6", "6", "6", "6", "6", "6", "6", "6.0e+00", "6.0e+00" },
        [_][]const u8{ "16", "16", "16", "16", "16", "16", "16", "16", "1.6e+01", "1.6e+01" },
        [_][]const u8{ "4", "4", "4", "4", "4", "4", "4", "4", "4.0e+00", "4.0e+00" },
    };
    for (op_strings) |op_string, op_index| {
        for (types) |type_, i| {
            var fs = try MockFileSystem.init(&arena);
            _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
                \\start(): {s} {{
                \\  8 {s} 2
                \\}}
            , .{ type_, op_string }));
            const module = try analyzeSemantics(codebase, fs, "foo.yeti");
            try codegen(module);
            const top_level = module.get(components.TopLevel);
            const start = top_level.findString("start").get(components.Overloads).slice()[0];
            const start_instructions = start.get(components.WasmInstructions).slice();
            try expectEqual(start_instructions.len, 1);
            const constant = start_instructions[0];
            try expectEqual(constant.get(components.WasmInstructionKind), const_kinds[i]);
            try expectEqualStrings(literalOf(constant.get(components.Constant).entity), results[op_index][i]);
        }
    }
}

test "codegen arithmetic binary op two local constants" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "i64", "i32", "i16", "i8", "u64", "u32", "u16", "u8", "f64", "f32" };
    const const_kinds = [_]components.WasmInstructionKind{ .i64_const, .i32_const, .i32_const, .i32_const, .i64_const, .i32_const, .i32_const, .i32_const, .f64_const, .f32_const };
    const op_strings = [_][]const u8{ "+", "-", "*", "/" };
    const results = [_][10][]const u8{
        [_][]const u8{ "10", "10", "10", "10", "10", "10", "10", "10", "1.0e+01", "1.0e+01" },
        [_][]const u8{ "6", "6", "6", "6", "6", "6", "6", "6", "6.0e+00", "6.0e+00" },
        [_][]const u8{ "16", "16", "16", "16", "16", "16", "16", "16", "1.6e+01", "1.6e+01" },
        [_][]const u8{ "4", "4", "4", "4", "4", "4", "4", "4", "4.0e+00", "4.0e+00" },
    };
    for (op_strings) |op_string, op_index| {
        for (types) |type_, i| {
            var fs = try MockFileSystem.init(&arena);
            _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
                \\start(): {s} {{
                \\  x: {s} = 8
                \\  y: {s} = 2
                \\  x {s} y
                \\}}
            , .{ type_, type_, type_, op_string }));
            const module = try analyzeSemantics(codebase, fs, "foo.yeti");
            try codegen(module);
            const top_level = module.get(components.TopLevel);
            const start = top_level.findString("start").get(components.Overloads).slice()[0];
            const start_instructions = start.get(components.WasmInstructions).slice();
            try expectEqual(start_instructions.len, 1);
            const constant = start_instructions[0];
            try expectEqual(constant.get(components.WasmInstructionKind), const_kinds[i]);
            try expectEqualStrings(literalOf(constant.get(components.Constant).entity), results[op_index][i]);
        }
    }
}

test "codegen int binary op two local constants" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "i64", "i32", "u64", "u32" };
    const const_kinds = [_]components.WasmInstructionKind{ .i64_const, .i32_const, .i64_const, .i32_const };
    const op_strings = [_][]const u8{ "%", "&", "|", "^", "<<", ">>" };
    const results = [_][4][]const u8{
        [_][]const u8{ "0", "0", "0", "0" },
        [_][]const u8{ "0", "0", "0", "0" },
        [_][]const u8{ "10", "10", "10", "10" },
        [_][]const u8{ "10", "10", "10", "10" },
        [_][]const u8{ "32", "32", "32", "32" },
        [_][]const u8{ "2", "2", "2", "2" },
    };
    for (op_strings) |op_string, op_index| {
        for (types) |type_, i| {
            var fs = try MockFileSystem.init(&arena);
            _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
                \\start(): {s} {{
                \\  x: {s} = 8
                \\  y: {s} = 2
                \\  x {s} y
                \\}}
            , .{ type_, type_, type_, op_string }));
            const module = try analyzeSemantics(codebase, fs, "foo.yeti");
            try codegen(module);
            const top_level = module.get(components.TopLevel);
            const start = top_level.findString("start").get(components.Overloads).slice()[0];
            const start_instructions = start.get(components.WasmInstructions).slice();
            try expectEqual(start_instructions.len, 1);
            const constant = start_instructions[0];
            try expectEqual(constant.get(components.WasmInstructionKind), const_kinds[i]);
            try expectEqualStrings(literalOf(constant.get(components.Constant).entity), results[op_index][i]);
        }
    }
}

test "codegen int comparison op two local constants" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "i64", "i32", "i16", "i8", "u64", "u32", "u16", "u8", "f64", "f32" };
    const const_kinds = [_]components.WasmInstructionKind{ .i32_const, .i32_const, .i32_const, .i32_const, .i32_const, .i32_const, .i32_const, .i32_const, .i32_const, .i32_const };
    const op_strings = [_][]const u8{ "==", "!=", "<", "<=", ">", ">=" };
    const results = [_][10][]const u8{
        [_][]const u8{ "0", "0", "0", "0", "0", "0", "0", "0", "0", "0" },
        [_][]const u8{ "1", "1", "1", "1", "1", "1", "1", "1", "1", "1" },
        [_][]const u8{ "0", "0", "0", "0", "0", "0", "0", "0", "0", "0" },
        [_][]const u8{ "0", "0", "0", "0", "0", "0", "0", "0", "0", "0" },
        [_][]const u8{ "1", "1", "1", "1", "1", "1", "1", "1", "1", "1" },
        [_][]const u8{ "1", "1", "1", "1", "1", "1", "1", "1", "1", "1" },
    };
    for (op_strings) |op_string, op_index| {
        for (types) |type_, i| {
            var fs = try MockFileSystem.init(&arena);
            _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
                \\start(): i32 {{
                \\  x: {s} = 8
                \\  y: {s} = 2
                \\  x {s} y
                \\}}
            , .{ type_, type_, op_string }));
            const module = try analyzeSemantics(codebase, fs, "foo.yeti");
            try codegen(module);
            const top_level = module.get(components.TopLevel);
            const start = top_level.findString("start").get(components.Overloads).slice()[0];
            const start_instructions = start.get(components.WasmInstructions).slice();
            try expectEqual(start_instructions.len, 1);
            const constant = start_instructions[0];
            try expectEqual(constant.get(components.WasmInstructionKind), const_kinds[i]);
            try expectEqualStrings(literalOf(constant.get(components.Constant).entity), results[op_index][i]);
        }
    }
}

test "codegen int comparison op two local constants one unused" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start(): i32 {
        \\  a = 8
        \\  b = 2
        \\  c = a == b
        \\  a
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    const start_instructions = start.get(components.WasmInstructions).slice();
    try expectEqual(start_instructions.len, 3);
    {
        const constant = start_instructions[0];
        try expectEqual(constant.get(components.WasmInstructionKind), .i32_const);
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "0");
    }
    {
        const local_set = start_instructions[1];
        try expectEqual(local_set.get(components.WasmInstructionKind), .local_set);
        try expectEqualStrings(literalOf(local_set.get(components.Local).entity.get(components.Name).entity), "c");
    }
    {
        const constant = start_instructions[2];
        try expectEqual(constant.get(components.WasmInstructionKind), .i32_const);
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "8");
    }
}

test "codegen arithmethic binary op non constant" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "i64", "i32", "i16", "i8", "u64", "u32", "u16", "u8", "f64", "f32" };
    const const_kinds = [_]components.WasmInstructionKind{ .i64_const, .i32_const, .i32_const, .i32_const, .i64_const, .i32_const, .i32_const, .i32_const, .f64_const, .f32_const };
    const op_kinds = [_][10]components.WasmInstructionKind{
        [_]components.WasmInstructionKind{ .i64_add, .i32_add, .i32_add_mod_16, .i32_add_mod_8, .i64_add, .i32_add, .i32_add_mod_16, .i32_add_mod_8, .f64_add, .f32_add },
        [_]components.WasmInstructionKind{ .i64_sub, .i32_sub, .i32_sub_mod_16, .i32_sub_mod_8, .i64_sub, .i32_sub, .i32_sub_mod_16, .i32_sub_mod_8, .f64_sub, .f32_sub },
        [_]components.WasmInstructionKind{ .i64_mul, .i32_mul, .i32_mul_mod_16, .i32_mul_mod_8, .i64_mul, .i32_mul, .i32_mul_mod_16, .i32_mul_mod_8, .f64_mul, .f32_mul },
        [_]components.WasmInstructionKind{ .i64_div, .i32_div, .i32_div, .i32_div, .u64_div, .u32_div, .u32_div, .u32_div, .f64_div, .f32_div },
    };
    const op_strings = [_][]const u8{ "+", "-", "*", "/" };
    for (op_strings) |op_string, op_index| {
        for (types) |type_, i| {
            var fs = try MockFileSystem.init(&arena);
            _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
                \\start(): {s} {{
                \\  id(10) {s} id(25)
                \\}}
                \\
                \\id(x: {s}): {s} {{
                \\  x
                \\}}
            , .{ type_, op_string, type_, type_ }));
            const module = try analyzeSemantics(codebase, fs, "foo.yeti");
            try codegen(module);
            const top_level = module.get(components.TopLevel);
            const start = top_level.findString("start").get(components.Overloads).slice()[0];
            const start_instructions = start.get(components.WasmInstructions).slice();
            try expectEqual(start_instructions.len, 5);
            const id = blk: {
                const constant = start_instructions[0];
                try expectEqual(constant.get(components.WasmInstructionKind), const_kinds[i]);
                try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "10");
                const call = start_instructions[1];
                try expectEqual(call.get(components.WasmInstructionKind), .call);
                const callable = call.get(components.Callable).entity;
                try expectEqualStrings(literalOf(callable.get(components.Name).entity), "id");
                break :blk callable;
            };
            {
                const constant = start_instructions[2];
                try expectEqual(constant.get(components.WasmInstructionKind), const_kinds[i]);
                try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "25");
                const call = start_instructions[3];
                try expectEqual(call.get(components.WasmInstructionKind), .call);
                const callable = call.get(components.Callable).entity;
                try expectEqual(callable, id);
            }
            const op = start_instructions[4];
            try expectEqual(op.get(components.WasmInstructionKind), op_kinds[op_index][i]);
            const id_instructions = id.get(components.WasmInstructions).slice();
            try expectEqual(id_instructions.len, 1);
            const local_get = id_instructions[0];
            try expectEqual(local_get.get(components.WasmInstructionKind), .local_get);
            const local = local_get.get(components.Local).entity;
            try expectEqualStrings(literalOf(local), "x");
        }
    }
}

test "codegen int binary op non constant" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "i64", "i32", "u64", "u32" };
    const const_kinds = [_]components.WasmInstructionKind{ .i64_const, .i32_const, .i64_const, .i32_const };
    const op_kinds = [_][4]components.WasmInstructionKind{
        [_]components.WasmInstructionKind{ .i64_and, .i32_and, .i64_and, .i32_and },
        [_]components.WasmInstructionKind{ .i64_or, .i32_or, .i64_or, .i32_or },
        [_]components.WasmInstructionKind{ .i64_xor, .i32_xor, .i64_xor, .i32_xor },
        [_]components.WasmInstructionKind{ .i64_shl, .i32_shl, .u64_shl, .u32_shl },
        [_]components.WasmInstructionKind{ .i64_shr, .i32_shr, .u64_shr, .u32_shr },
        [_]components.WasmInstructionKind{ .i64_rem, .i32_rem, .u64_rem, .u32_rem },
    };
    const op_strings = [_][]const u8{ "&", "|", "^", "<<", ">>", "%" };
    for (op_strings) |op_string, op_index| {
        for (types) |type_, i| {
            var fs = try MockFileSystem.init(&arena);
            _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
                \\start(): {s} {{
                \\  id(10) {s} id(25)
                \\}}
                \\
                \\id(x: {s}): {s} {{
                \\  x
                \\}}
            , .{ type_, op_string, type_, type_ }));
            const module = try analyzeSemantics(codebase, fs, "foo.yeti");
            try codegen(module);
            const top_level = module.get(components.TopLevel);
            const start = top_level.findString("start").get(components.Overloads).slice()[0];
            const start_instructions = start.get(components.WasmInstructions).slice();
            try expectEqual(start_instructions.len, 5);
            const id = blk: {
                const constant = start_instructions[0];
                try expectEqual(constant.get(components.WasmInstructionKind), const_kinds[i]);
                try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "10");
                const call = start_instructions[1];
                try expectEqual(call.get(components.WasmInstructionKind), .call);
                const callable = call.get(components.Callable).entity;
                try expectEqualStrings(literalOf(callable.get(components.Name).entity), "id");
                break :blk callable;
            };
            {
                const constant = start_instructions[2];
                try expectEqual(constant.get(components.WasmInstructionKind), const_kinds[i]);
                try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "25");
                const call = start_instructions[3];
                try expectEqual(call.get(components.WasmInstructionKind), .call);
                const callable = call.get(components.Callable).entity;
                try expectEqual(callable, id);
            }
            const op = start_instructions[4];
            try expectEqual(op.get(components.WasmInstructionKind), op_kinds[op_index][i]);
            const id_instructions = id.get(components.WasmInstructions).slice();
            try expectEqual(id_instructions.len, 1);
            const local = id_instructions[0];
            try expectEqual(local.get(components.WasmInstructionKind), .local_get);
            try expectEqualStrings(literalOf(local.get(components.Local).entity), "x");
        }
    }
}

test "codegen comparison binary op non constant" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "i64", "i32", "u64", "u32", "f64", "f32" };
    const const_kinds = [_]components.WasmInstructionKind{ .i64_const, .i32_const, .i64_const, .i32_const, .f64_const, .f32_const };
    const op_kinds = [_][6]components.WasmInstructionKind{
        [_]components.WasmInstructionKind{ .i64_eq, .i32_eq, .i64_eq, .i32_eq, .f64_eq, .f32_eq },
        [_]components.WasmInstructionKind{ .i64_ne, .i32_ne, .i64_ne, .i32_ne, .f64_ne, .f32_ne },
        [_]components.WasmInstructionKind{ .i64_lt, .i32_lt, .i64_lt, .i32_lt, .f64_lt, .f32_lt },
        [_]components.WasmInstructionKind{ .i64_le, .i32_le, .i64_le, .i32_le, .f64_le, .f32_le },
        [_]components.WasmInstructionKind{ .i64_gt, .i32_gt, .i64_gt, .i32_gt, .f64_gt, .f32_gt },
        [_]components.WasmInstructionKind{ .i64_ge, .i32_ge, .i64_ge, .i32_ge, .f64_ge, .f32_ge },
    };
    const op_strings = [_][]const u8{ "==", "!=", "<", "<=", ">", ">=" };
    for (op_strings) |op_string, op_index| {
        for (types) |type_, i| {
            var fs = try MockFileSystem.init(&arena);
            _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
                \\start(): i32 {{
                \\  id(10) {s} id(25)
                \\}}
                \\
                \\id(x: {s}): {s} {{
                \\  x
                \\}}
            , .{ op_string, type_, type_ }));
            const module = try analyzeSemantics(codebase, fs, "foo.yeti");
            try codegen(module);
            const top_level = module.get(components.TopLevel);
            const start = top_level.findString("start").get(components.Overloads).slice()[0];
            const start_instructions = start.get(components.WasmInstructions).slice();
            try expectEqual(start_instructions.len, 5);
            const id = blk: {
                const constant = start_instructions[0];
                try expectEqual(constant.get(components.WasmInstructionKind), const_kinds[i]);
                try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "10");
                const call = start_instructions[1];
                try expectEqual(call.get(components.WasmInstructionKind), .call);
                const callable = call.get(components.Callable).entity;
                try expectEqualStrings(literalOf(callable.get(components.Name).entity), "id");
                break :blk callable;
            };
            {
                const constant = start_instructions[2];
                try expectEqual(constant.get(components.WasmInstructionKind), const_kinds[i]);
                try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "25");
                const call = start_instructions[3];
                try expectEqual(call.get(components.WasmInstructionKind), .call);
                const callable = call.get(components.Callable).entity;
                try expectEqual(callable, id);
            }
            const op = start_instructions[4];
            try expectEqual(op.get(components.WasmInstructionKind), op_kinds[op_index][i]);
            const id_instructions = id.get(components.WasmInstructions).slice();
            try expectEqual(id_instructions.len, 1);
            const local = id_instructions[0];
            try expectEqual(local.get(components.WasmInstructionKind), .local_get);
            try expectEqualStrings(literalOf(local.get(components.Local).entity), "x");
        }
    }
}

test "print wasm arithmetic binary op" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const op_strings = [_][]const u8{ "+", "-", "*", "/" };
    const results = [_][6][]const u8{
        [_][]const u8{ "10", "10", "10", "10", "1.0e+01", "1.0e+01" },
        [_][]const u8{ "6", "6", "6", "6", "6.0e+00", "6.0e+00" },
        [_][]const u8{ "16", "16", "16", "16", "1.6e+01", "1.6e+01" },
        [_][]const u8{ "4", "4", "4", "4", "4.0e+00", "4.0e+00" },
    };
    const types = [_][]const u8{ "i64", "i32", "u64", "u32", "f64", "f32" };
    const wasm_types = [_][]const u8{ "i64", "i32", "i64", "i32", "f64", "f32" };
    for (op_strings) |op_string, op_index| {
        for (types) |type_, i| {
            var fs = try MockFileSystem.init(&arena);
            _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
                \\start(): {s} {{
                \\  x: {s} = 8
                \\  y: {s} = 2
                \\  x {s} y
                \\}}
            , .{ type_, type_, type_, op_string }));
            const module = try analyzeSemantics(codebase, fs, "foo.yeti");
            try codegen(module);
            const wasm = try printWasm(module);
            try expectEqualStrings(wasm, try std.fmt.allocPrint(arena.allocator(),
                \\(module
                \\
                \\  (func $foo/start (result {s})
                \\    ({s}.const {s}))
                \\
                \\  (export "_start" (func $foo/start)))
            , .{ wasm_types[i], wasm_types[i], results[op_index][i] }));
        }
    }
}

test "print wasm int binary op" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const op_strings = [_][]const u8{ "%", "&", "|", "^", "<<", ">>" };
    const results = [_][4][]const u8{
        [_][]const u8{ "0", "0", "0", "0" },
        [_][]const u8{ "0", "0", "0", "0" },
        [_][]const u8{ "10", "10", "10", "10" },
        [_][]const u8{ "10", "10", "10", "10" },
        [_][]const u8{ "32", "32", "32", "32" },
        [_][]const u8{ "2", "2", "2", "2" },
    };
    const types = [_][]const u8{ "i64", "i32", "u64", "u32" };
    const wasm_types = [_][]const u8{ "i64", "i32", "i64", "i32" };
    for (op_strings) |op_string, op_index| {
        for (types) |type_, i| {
            var fs = try MockFileSystem.init(&arena);
            _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
                \\start(): {s} {{
                \\  x: {s} = 8
                \\  y: {s} = 2
                \\  x {s} y
                \\}}
            , .{ type_, type_, type_, op_string }));
            const module = try analyzeSemantics(codebase, fs, "foo.yeti");
            try codegen(module);
            const wasm = try printWasm(module);
            try expectEqualStrings(wasm, try std.fmt.allocPrint(arena.allocator(),
                \\(module
                \\
                \\  (func $foo/start (result {s})
                \\    ({s}.const {s}))
                \\
                \\  (export "_start" (func $foo/start)))
            , .{ wasm_types[i], wasm_types[i], results[op_index][i] }));
        }
    }
}

test "print wasm arithmetic binary op non constant" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const op_strings = [_][]const u8{ "+", "-", "*", "/" };
    const instructions = [_][6][]const u8{
        [_][]const u8{ "i64.add", "i32.add", "i64.add", "i32.add", "f64.add", "f32.add" },
        [_][]const u8{ "i64.sub", "i32.sub", "i64.sub", "i32.sub", "f64.sub", "f32.sub" },
        [_][]const u8{ "i64.mul", "i32.mul", "i64.mul", "i32.mul", "f64.mul", "f32.mul" },
        [_][]const u8{ "i64.div_s", "i32.div_s", "i64.div_u", "i32.div_u", "f64.div", "f32.div" },
    };
    const types = [_][]const u8{ "i64", "i32", "u64", "u32", "f64", "f32" };
    const wasm_types = [_][]const u8{ "i64", "i32", "i64", "i32", "f64", "f32" };
    for (op_strings) |op_string, op_index| {
        for (types) |type_, i| {
            var fs = try MockFileSystem.init(&arena);
            _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
                \\start(): {s} {{
                \\  id(10) {s} id(25)
                \\}}
                \\
                \\id(x: {s}): {s} {{
                \\  x
                \\}}
            , .{ type_, op_string, type_, type_ }));
            const module = try analyzeSemantics(codebase, fs, "foo.yeti");
            try codegen(module);
            const wasm = try printWasm(module);
            try expectEqualStrings(wasm, try std.fmt.allocPrint(arena.allocator(),
                \\(module
                \\
                \\  (func $foo/start (result {s})
                \\    ({s}.const 10)
                \\    (call $foo/id.{s})
                \\    ({s}.const 25)
                \\    (call $foo/id.{s})
                \\    {s})
                \\
                \\  (func $foo/id.{s} (param $x {s}) (result {s})
                \\    (local.get $x))
                \\
                \\  (export "_start" (func $foo/start)))
            , .{
                wasm_types[i],
                wasm_types[i],
                type_,
                wasm_types[i],
                type_,
                instructions[op_index][i],
                type_,
                wasm_types[i],
                wasm_types[i],
            }));
        }
    }
}

test "print wasm arithmetic binary op non constant modulo" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const op_strings = [_][]const u8{ "+", "-", "*" };
    const instructions = [_][4][]const u8{
        [_][]const u8{ "i32.add", "i32.add", "i32.add", "i32.add" },
        [_][]const u8{ "i32.sub", "i32.sub", "i32.sub", "i32.sub" },
        [_][]const u8{ "i32.mul", "i32.mul", "i32.mul", "i32.mul" },
    };
    const types = [_][]const u8{ "i16", "i8", "u16", "u8" };
    const wasm_types = [_][]const u8{ "i32", "i32", "i32", "i32" };
    const constants = [_][]const u8{ "65535", "255", "65535", "255" };
    for (op_strings) |op_string, op_index| {
        for (types) |type_, i| {
            var fs = try MockFileSystem.init(&arena);
            _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
                \\start(): {s} {{
                \\  id(10) {s} id(25)
                \\}}
                \\
                \\id(x: {s}): {s} {{
                \\  x
                \\}}
            , .{ type_, op_string, type_, type_ }));
            const module = try analyzeSemantics(codebase, fs, "foo.yeti");
            try codegen(module);
            const wasm = try printWasm(module);
            try expectEqualStrings(wasm, try std.fmt.allocPrint(arena.allocator(),
                \\(module
                \\
                \\  (func $foo/start (result {s})
                \\    ({s}.const 10)
                \\    (call $foo/id.{s})
                \\    ({s}.const 25)
                \\    (call $foo/id.{s})
                \\    {s}
                \\    (i32.const {s})
                \\    i32.and)
                \\
                \\  (func $foo/id.{s} (param $x {s}) (result {s})
                \\    (local.get $x))
                \\
                \\  (export "_start" (func $foo/start)))
            , .{
                wasm_types[i],
                wasm_types[i],
                type_,
                wasm_types[i],
                type_,
                instructions[op_index][i],
                constants[i],
                type_,
                wasm_types[i],
                wasm_types[i],
            }));
        }
    }
}

test "print wasm int binary op non constant" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const op_strings = [_][]const u8{ "%", "&", "|", "^", "<<", ">>" };
    const instructions = [_][8][]const u8{
        [_][]const u8{ "i64.rem_s", "i32.rem_s", "i32.rem_s", "i32.rem_s", "i64.rem_u", "i32.rem_u", "i32.rem_u", "i32.rem_u" },
        [_][]const u8{ "i64.and", "i32.and", "i32.and", "i32.and", "i64.and", "i32.and", "i32.and", "i32.and" },
        [_][]const u8{ "i64.or", "i32.or", "i32.or", "i32.or", "i64.or", "i32.or", "i32.or", "i32.or" },
        [_][]const u8{ "i64.xor", "i32.xor", "i32.xor", "i32.xor", "i64.xor", "i32.xor", "i32.xor", "i32.xor" },
        [_][]const u8{ "i64.shl", "i32.shl", "i32.shl", "i32.shl", "i64.shl", "i32.shl", "i32.shl", "i32.shl" },
        [_][]const u8{ "i64.shr_s", "i32.shr_s", "i32.shr_s", "i32.shr_s", "i64.shr_u", "i32.shr_u", "i32.shr_u", "i32.shr_u" },
    };
    const types = [_][]const u8{ "i64", "i32", "i16", "i8", "u64", "u32", "u16", "u8" };
    const wasm_types = [_][]const u8{ "i64", "i32", "i32", "i32", "i64", "i32", "i32", "i32" };
    for (op_strings) |op_string, op_index| {
        for (types) |type_, i| {
            var fs = try MockFileSystem.init(&arena);
            _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
                \\start(): {s} {{
                \\  id(10) {s} id(25)
                \\}}
                \\
                \\id(x: {s}): {s} {{
                \\  x
                \\}}
            , .{ type_, op_string, type_, type_ }));
            const module = try analyzeSemantics(codebase, fs, "foo.yeti");
            try codegen(module);
            const wasm = try printWasm(module);
            try expectEqualStrings(wasm, try std.fmt.allocPrint(arena.allocator(),
                \\(module
                \\
                \\  (func $foo/start (result {s})
                \\    ({s}.const 10)
                \\    (call $foo/id.{s})
                \\    ({s}.const 25)
                \\    (call $foo/id.{s})
                \\    {s})
                \\
                \\  (func $foo/id.{s} (param $x {s}) (result {s})
                \\    (local.get $x))
                \\
                \\  (export "_start" (func $foo/start)))
            , .{
                wasm_types[i],
                wasm_types[i],
                type_,
                wasm_types[i],
                type_,
                instructions[op_index][i],
                type_,
                wasm_types[i],
                wasm_types[i],
            }));
        }
    }
}
