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
const literalOf = yeti.test_utils.literalOf;
const typeOf = yeti.test_utils.typeOf;
const MockFileSystem = yeti.FileSystem;

test "codegen of loading i64x2 through pointer" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start(): i64x2 {
        \\  ptr = cast(*i64x2, 0)
        \\  *ptr
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    const wasm_instructions = start.get(components.WasmInstructions).slice();
    try expectEqual(wasm_instructions.len, 4);
    {
        const constant = wasm_instructions[0];
        try expectEqual(constant.get(components.WasmInstructionKind), .i32_const);
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "0");
    }
    {
        const local_set = wasm_instructions[1];
        try expectEqual(local_set.get(components.WasmInstructionKind), .local_set);
        const local = local_set.get(components.Local).entity;
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "ptr");
    }
    {
        const local_get = wasm_instructions[2];
        try expectEqual(local_get.get(components.WasmInstructionKind), .local_get);
        const local = local_get.get(components.Local).entity;
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "ptr");
    }
    try expectEqual(wasm_instructions[3].get(components.WasmInstructionKind), .v128_load);
}

test "codegen of binary op on two int vectors" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const type_strings = [_][]const u8{ "i64x2", "i32x4", "i16x8", "i8x16", "u64x2", "u32x4", "u16x8", "u8x16" };
    const op_strings = [_][]const u8{ "+", "-", "*" };
    const kinds = [_][3]components.WasmInstructionKind{
        .{ .i64x2_add, .i64x2_sub, .i64x2_mul },
        .{ .i32x4_add, .i32x4_sub, .i32x4_mul },
        .{ .i16x8_add, .i16x8_sub, .i16x8_mul },
        .{ .i8x16_add, .i8x16_sub, .i8x16_mul },
        .{ .i64x2_add, .i64x2_sub, .i64x2_mul },
        .{ .i32x4_add, .i32x4_sub, .i32x4_mul },
        .{ .i16x8_add, .i16x8_sub, .i16x8_mul },
        .{ .i8x16_add, .i8x16_sub, .i8x16_mul },
    };
    for (type_strings) |type_string, type_index| {
        for (op_strings) |op_string, i| {
            var fs = try MockFileSystem.init(&arena);
            _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
                \\start(): {s} {{
                \\  v = *cast(*{s}, 0)
                \\  v {s} v
                \\}}
            , .{ type_string, type_string, op_string }));
            const module = try analyzeSemantics(codebase, fs, "foo.yeti");
            try codegen(module);
            const top_level = module.get(components.TopLevel);
            const start = top_level.findString("start").get(components.Overloads).slice()[0];
            const wasm_instructions = start.get(components.WasmInstructions).slice();
            try expectEqual(wasm_instructions.len, 6);
            {
                const constant = wasm_instructions[0];
                try expectEqual(constant.get(components.WasmInstructionKind), .i32_const);
                try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "0");
            }
            try expectEqual(wasm_instructions[1].get(components.WasmInstructionKind), .v128_load);
            {
                const local_set = wasm_instructions[2];
                try expectEqual(local_set.get(components.WasmInstructionKind), .local_set);
                const local = local_set.get(components.Local).entity;
                try expectEqualStrings(literalOf(local.get(components.Name).entity), "v");
            }
            {
                const local_get = wasm_instructions[3];
                try expectEqual(local_get.get(components.WasmInstructionKind), .local_get);
                const local = local_get.get(components.Local).entity;
                try expectEqualStrings(literalOf(local.get(components.Name).entity), "v");
            }
            {
                const local_get = wasm_instructions[4];
                try expectEqual(local_get.get(components.WasmInstructionKind), .local_get);
                const local = local_get.get(components.Local).entity;
                try expectEqualStrings(literalOf(local.get(components.Name).entity), "v");
            }
            try expectEqual(wasm_instructions[5].get(components.WasmInstructionKind), kinds[type_index][i]);
        }
    }
}

test "codegen of binary op on two float vectors" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const type_strings = [_][]const u8{ "f64x2", "f32x4" };
    const op_strings = [_][]const u8{ "+", "-", "*", "/" };
    const kinds = [_][4]components.WasmInstructionKind{
        .{ .f64x2_add, .f64x2_sub, .f64x2_mul, .f64x2_div },
        .{ .f32x4_add, .f32x4_sub, .f32x4_mul, .f32x4_div },
    };
    for (type_strings) |type_string, type_index| {
        for (op_strings) |op_string, i| {
            var fs = try MockFileSystem.init(&arena);
            _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
                \\start(): {s} {{
                \\  v = *cast(*{s}, 0)
                \\  v {s} v
                \\}}
            , .{ type_string, type_string, op_string }));
            const module = try analyzeSemantics(codebase, fs, "foo.yeti");
            try codegen(module);
            const top_level = module.get(components.TopLevel);
            const start = top_level.findString("start").get(components.Overloads).slice()[0];
            const wasm_instructions = start.get(components.WasmInstructions).slice();
            try expectEqual(wasm_instructions.len, 6);
            {
                const constant = wasm_instructions[0];
                try expectEqual(constant.get(components.WasmInstructionKind), .i32_const);
                try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "0");
            }
            try expectEqual(wasm_instructions[1].get(components.WasmInstructionKind), .v128_load);
            {
                const local_set = wasm_instructions[2];
                try expectEqual(local_set.get(components.WasmInstructionKind), .local_set);
                const local = local_set.get(components.Local).entity;
                try expectEqualStrings(literalOf(local.get(components.Name).entity), "v");
            }
            {
                const local_get = wasm_instructions[3];
                try expectEqual(local_get.get(components.WasmInstructionKind), .local_get);
                const local = local_get.get(components.Local).entity;
                try expectEqualStrings(literalOf(local.get(components.Name).entity), "v");
            }
            {
                const local_get = wasm_instructions[4];
                try expectEqual(local_get.get(components.WasmInstructionKind), .local_get);
                const local = local_get.get(components.Local).entity;
                try expectEqualStrings(literalOf(local.get(components.Name).entity), "v");
            }
            try expectEqual(wasm_instructions[5].get(components.WasmInstructionKind), kinds[type_index][i]);
        }
    }
}

test "codegen of storing i64x2 through pointer" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start(): void {
        \\  ptr = cast(*i64x2, 0)
        \\  *ptr = *ptr
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
        try expectEqual(constant.get(components.WasmInstructionKind), .i32_const);
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "0");
    }
    {
        const local_set = wasm_instructions[1];
        try expectEqual(local_set.get(components.WasmInstructionKind), .local_set);
        const local = local_set.get(components.Local).entity;
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "ptr");
    }
    {
        const local_get = wasm_instructions[2];
        try expectEqual(local_get.get(components.WasmInstructionKind), .local_get);
        const local = local_get.get(components.Local).entity;
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "ptr");
    }
    {
        const local_get = wasm_instructions[3];
        try expectEqual(local_get.get(components.WasmInstructionKind), .local_get);
        const local = local_get.get(components.Local).entity;
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "ptr");
    }
    try expectEqual(wasm_instructions[4].get(components.WasmInstructionKind), .v128_load);
    try expectEqual(wasm_instructions[5].get(components.WasmInstructionKind), .v128_store);
}

test "print wasm pointer v128 load" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start(): i64x2 {
        \\  ptr = cast(*i64x2, 0)
        \\  *ptr
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/start (result v128)
        \\    (local $ptr i32)
        \\    (i32.const 0)
        \\    (local.set $ptr)
        \\    (local.get $ptr)
        \\    v128.load)
        \\
        \\  (export "_start" (func $foo/start))
        \\
        \\  (memory 1)
        \\  (export "memory" (memory 0)))
    );
}

test "print wasm pointer v128 store" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start(): void {
        \\  ptr = cast(*i64x2, 0)
        \\  *ptr = *ptr
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/start
        \\    (local $ptr i32)
        \\    (i32.const 0)
        \\    (local.set $ptr)
        \\    (local.get $ptr)
        \\    (local.get $ptr)
        \\    v128.load
        \\    v128.store)
        \\
        \\  (export "_start" (func $foo/start))
        \\
        \\  (memory 1)
        \\  (export "memory" (memory 0)))
    );
}

test "print wasm binary op on two int vectors" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const type_strings = [_][]const u8{ "i64x2", "i32x4", "i16x8", "i8x16", "u64x2", "u32x4", "u16x8", "u8x16" };
    const op_strings = [_][]const u8{ "+", "-", "*" };
    const instructions = [_][3][]const u8{
        .{ "i64x2.add", "i64x2.sub", "i64x2.mul" },
        .{ "i32x4.add", "i32x4.sub", "i32x4.mul" },
        .{ "i16x8.add", "i16x8.sub", "i16x8.mul" },
        .{ "i8x16.add", "i8x16.sub", "i8x16.mul" },
        .{ "i64x2.add", "i64x2.sub", "i64x2.mul" },
        .{ "i32x4.add", "i32x4.sub", "i32x4.mul" },
        .{ "i16x8.add", "i16x8.sub", "i16x8.mul" },
        .{ "i8x16.add", "i8x16.sub", "i8x16.mul" },
    };
    for (type_strings) |type_string, type_index| {
        for (op_strings) |op_string, i| {
            var fs = try MockFileSystem.init(&arena);
            _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
                \\start(): {s} {{
                \\  v = *cast(*{s}, 0)
                \\  v {s} v
                \\}}
            , .{ type_string, type_string, op_string }));
            const module = try analyzeSemantics(codebase, fs, "foo.yeti");
            try codegen(module);
            const wasm = try printWasm(module);
            try expectEqualStrings(wasm, try std.fmt.allocPrint(arena.allocator(),
                \\(module
                \\
                \\  (func $foo/start (result v128)
                \\    (local $v v128)
                \\    (i32.const 0)
                \\    v128.load
                \\    (local.set $v)
                \\    (local.get $v)
                \\    (local.get $v)
                \\    {s})
                \\
                \\  (export "_start" (func $foo/start))
                \\
                \\  (memory 1)
                \\  (export "memory" (memory 0)))
            , .{instructions[type_index][i]}));
        }
    }
}

test "print wasm binary op on two float vectors" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const type_strings = [_][]const u8{ "f64x2", "f32x4" };
    const op_strings = [_][]const u8{ "+", "-", "*", "/" };
    const instructions = [_][4][]const u8{
        .{ "f64x2.add", "f64x2.sub", "f64x2.mul", "f64x2.div" },
        .{ "f32x4.add", "f32x4.sub", "f32x4.mul", "f32x4.div" },
    };
    for (type_strings) |type_string, type_index| {
        for (op_strings) |op_string, i| {
            var fs = try MockFileSystem.init(&arena);
            _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
                \\start(): {s} {{
                \\  v = *cast(*{s}, 0)
                \\  v {s} v
                \\}}
            , .{ type_string, type_string, op_string }));
            const module = try analyzeSemantics(codebase, fs, "foo.yeti");
            try codegen(module);
            const wasm = try printWasm(module);
            try expectEqualStrings(wasm, try std.fmt.allocPrint(arena.allocator(),
                \\(module
                \\
                \\  (func $foo/start (result v128)
                \\    (local $v v128)
                \\    (i32.const 0)
                \\    v128.load
                \\    (local.set $v)
                \\    (local.get $v)
                \\    (local.get $v)
                \\    {s})
                \\
                \\  (export "_start" (func $foo/start))
                \\
                \\  (memory 1)
                \\  (export "memory" (memory 0)))
            , .{instructions[type_index][i]}));
        }
    }
}
