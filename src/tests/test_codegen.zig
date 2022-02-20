const std = @import("std");
const Arena = std.heap.ArenaAllocator;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const yeti = @import("yeti");
const initCodebase = yeti.initCodebase;
const MockFileSystem = yeti.FileSystem;
const components = yeti.components;
const analyzeSemantics = yeti.analyzeSemantics;
const codegen = yeti.codegen;
const literalOf = yeti.test_utils.literalOf;
const Entity = yeti.ecs.Entity;

test "codegen int literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "i64", "i32", "u64", "u32", "f64", "f32" };
    const const_kinds = [_]components.WasmInstructionKind{ .i64_const, .i32_const, .i64_const, .i32_const, .f64_const, .f32_const };
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start(): {s} {{
            \\  5
            \\}}
        , .{type_}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        try codegen(module);
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        const wasm_instructions = start.get(components.WasmInstructions).slice();
        try expectEqual(wasm_instructions.len, 1);
        const constant = wasm_instructions[0];
        try expectEqual(constant.get(components.WasmInstructionKind), const_kinds[i]);
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "5");
    }
}

test "codegen float literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "i64", "i32", "u64", "u32", "f64", "f32" };
    const const_kinds = [_]components.WasmInstructionKind{ .i64_const, .i32_const, .i64_const, .i32_const, .f64_const, .f32_const };
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start(): {s} {{
            \\  5
            \\}}
        , .{type_}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        try codegen(module);
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        const wasm_instructions = start.get(components.WasmInstructions).slice();
        try expectEqual(wasm_instructions.len, 1);
        const constant = wasm_instructions[0];
        try expectEqual(constant.get(components.WasmInstructionKind), const_kinds[i]);
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "5");
    }
}

test "codegen call local function" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "i64", "i32", "u64", "u32", "f64", "f32" };
    const const_kinds = [_]components.WasmInstructionKind{ .i64_const, .i32_const, .i64_const, .i32_const, .f64_const, .f32_const };
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start(): {s} {{
            \\  baz()
            \\}}
            \\
            \\baz(): {s} {{
            \\  10
            \\}}
        , .{ type_, type_ }));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        try codegen(module);
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        const start_instructions = start.get(components.WasmInstructions).slice();
        try expectEqual(start_instructions.len, 1);
        const call = start_instructions[0];
        try expectEqual(call.get(components.WasmInstructionKind), .call);
        const baz = call.get(components.Callable).entity;
        const baz_instructions = baz.get(components.WasmInstructions).slice();
        try expectEqual(baz_instructions.len, 1);
        const constant = baz_instructions[0];
        try expectEqual(constant.get(components.WasmInstructionKind), const_kinds[i]);
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "10");
    }
}

test "codegen assign" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "i64", "i32", "u64", "u32", "f64", "f32" };
    const const_kinds = [_]components.WasmInstructionKind{ .i64_const, .i32_const, .i64_const, .i32_const, .f64_const, .f32_const };
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start(): {s} {{
            \\  x: {s} = 10
            \\  x
            \\}}
        , .{ type_, type_ }));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        try codegen(module);
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        const start_instructions = start.get(components.WasmInstructions).slice();
        try expectEqual(start_instructions.len, 1);
        const constant = start_instructions[0];
        try expectEqual(constant.get(components.WasmInstructionKind), const_kinds[i]);
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "10");
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

test "codegen if then else where then branch taken statically" {
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
            \\start(): {s} {{
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

test "codegen if then else where else branch taken statically" {
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
            \\start(): {s} {{
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

test "codegen if then else non const conditional" {
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
            \\start(): {s} {{
            \\  if f() {{ 20 }} else {{ 30 }}
            \\}}
            \\
            \\f(): i32 {{ 1 }}
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

test "codegen assignment" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "i64", "i32", "u64", "u32", "f64", "f32" };
    const const_kinds = [_]components.WasmInstructionKind{ .i64_const, .i32_const, .i64_const, .i32_const, .f64_const, .f32_const };
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start(): {s} {{
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

test "codegen while loop" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start(): i32 {
        \\  i = 0
        \\  while i < 10 {
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
        \\start(): i64 {
        \\  i = 0
        \\  while i < 10 {
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

test "codegen of casting int literal to *i64" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start(): *i64 {
        \\  cast(*i64, 0)
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    const wasm_instructions = start.get(components.WasmInstructions).slice();
    try expectEqual(wasm_instructions.len, 1);
    const constant = wasm_instructions[0];
    try expectEqual(constant.get(components.WasmInstructionKind), .i32_const);
    try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "0");
}

test "codegen of storing through pointer" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start(): void {
        \\  ptr = cast(*i64, 0)
        \\  *ptr = 10
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    const wasm_instructions = start.get(components.WasmInstructions).slice();
    try expectEqual(wasm_instructions.len, 5);
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
        const constant = wasm_instructions[3];
        try expectEqual(constant.get(components.WasmInstructionKind), .i64_const);
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "10");
    }
    {
        try expectEqual(wasm_instructions[4].get(components.WasmInstructionKind), .i64_store);
    }
}

test "codegen of loading through pointer" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start(): i64 {
        \\  ptr = cast(*i64, 0)
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
    try expectEqual(wasm_instructions[3].get(components.WasmInstructionKind), .i64_load);
}

test "codegen of adding pointer and int literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start(): *i64 {
        \\  ptr = cast(*i64, 0)
        \\  ptr + 1
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    const wasm_instructions = start.get(components.WasmInstructions).slice();
    try expectEqual(wasm_instructions.len, 5);
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
        const constant = wasm_instructions[3];
        try expectEqual(constant.get(components.WasmInstructionKind), .i32_const);
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "8");
    }
    try expectEqual(wasm_instructions[4].get(components.WasmInstructionKind), .i32_add);
}

test "codegen of subtracting pointer and int literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start(): *i64 {
        \\  ptr = cast(*i64, 0)
        \\  ptr - 1
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    const wasm_instructions = start.get(components.WasmInstructions).slice();
    try expectEqual(wasm_instructions.len, 5);
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
        const constant = wasm_instructions[3];
        try expectEqual(constant.get(components.WasmInstructionKind), .i32_const);
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "8");
    }
    try expectEqual(wasm_instructions[4].get(components.WasmInstructionKind), .i32_sub);
}

test "codegen of comparing two *i64" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const op_strings = [_][]const u8{ "==", "!=", ">=", ">", "<=", "<" };
    const ops = [_]components.WasmInstructionKind{ .i32_eq, .i32_ne, .i32_ge, .i32_gt, .i32_le, .i32_lt };
    for (op_strings) |op_string, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start(): i32 {{
            \\  ptr = cast(*i64, 0)
            \\  ptr {s} ptr
            \\}}
        , .{op_string}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        try codegen(module);
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        const wasm_instructions = start.get(components.WasmInstructions).slice();
        try expectEqual(wasm_instructions.len, 5);
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
        try expectEqual(wasm_instructions[4].get(components.WasmInstructionKind), ops[i]);
    }
}

test "codegen of subtracting two *i64" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start(): i32 {
        \\  ptr = cast(*i64, 0)
        \\  ptr - ptr
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    const wasm_instructions = start.get(components.WasmInstructions).slice();
    try expectEqual(wasm_instructions.len, 7);
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
    try expectEqual(wasm_instructions[4].get(components.WasmInstructionKind), .i32_sub);
    {
        const constant = wasm_instructions[5];
        try expectEqual(constant.get(components.WasmInstructionKind), .i32_const);
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "8");
    }
    try expectEqual(wasm_instructions[6].get(components.WasmInstructionKind), .i32_div);
}

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

test "codegen of string literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start(): []u8 {
        \\  "hello world"
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
        try expectEqual(constant.get(components.WasmInstructionKind), .i32_const);
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "0");
    }
    {
        const constant = wasm_instructions[1];
        try expectEqual(constant.get(components.WasmInstructionKind), .i32_const);
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "11");
    }
    const data_segment = codebase.get(components.DataSegment);
    try expectEqual(data_segment.end, 88);
    const entities = data_segment.entities.slice();
    try expectEqual(entities.len, 1);
    try expectEqualStrings(literalOf(entities[0]), "hello world");
}

test "codegen of array index" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start(): u8 {
        \\  text = "hello world"
        \\  text[0]
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    const wasm_instructions = start.get(components.WasmInstructions).slice();
    try expectEqual(wasm_instructions.len, 9);
    {
        const constant = wasm_instructions[0];
        try expectEqual(constant.get(components.WasmInstructionKind), .i32_const);
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "0");
    }
    {
        const constant = wasm_instructions[1];
        try expectEqual(constant.get(components.WasmInstructionKind), .i32_const);
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "11");
    }
    {
        const local_set = wasm_instructions[2];
        try expectEqual(local_set.get(components.WasmInstructionKind), .local_set);
        try expectEqualStrings(literalOf(local_set.get(components.Local).entity.get(components.Name).entity), "text");
    }
    {
        const field = wasm_instructions[3];
        try expectEqual(field.get(components.WasmInstructionKind), .field);
        try expectEqualStrings(literalOf(field.get(components.Local).entity.get(components.Name).entity), "text");
        try expectEqualStrings(literalOf(field.get(components.Field).entity), "ptr");
    }
    {
        const constant = wasm_instructions[4];
        try expectEqual(constant.get(components.WasmInstructionKind), .i32_const);
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "0");
    }
    {
        const constant = wasm_instructions[5];
        try expectEqual(constant.get(components.WasmInstructionKind), .i32_const);
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "1");
    }
    try expectEqual(wasm_instructions[6].get(components.WasmInstructionKind), .i32_mul);
    try expectEqual(wasm_instructions[7].get(components.WasmInstructionKind), .i32_add);
    try expectEqual(wasm_instructions[8].get(components.WasmInstructionKind), .i32_load8_u);
    const data_segment = codebase.get(components.DataSegment);
    try expectEqual(data_segment.end, 88);
    const entities = data_segment.entities.slice();
    try expectEqual(entities.len, 1);
    try expectEqualStrings(literalOf(entities[0]), "hello world");
}
