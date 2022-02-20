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
