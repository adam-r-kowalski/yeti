const std = @import("std");
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const Arena = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;
const eql = std.meta.eql;
const panic = std.debug.panic;
const assert = std.debug.assert;

const initCodebase = @import("init_codebase.zig").initCodebase;
const MockFileSystem = @import("file_system.zig").FileSystem;
const analyzeSemantics = @import("semantic_analyzer.zig").analyzeSemantics;
const codegen = @import("codegen_next.zig").codegen;
const ecs = @import("ecs.zig");
const Entity = ecs.Entity;
const ECS = ecs.ECS;
const components = @import("components.zig");
const test_utils = @import("test_utils.zig");
const literalOf = test_utils.literalOf;
const List = @import("list.zig").List;
const strings_module = @import("strings.zig");
const Strings = strings_module.Strings;
const InternedString = strings_module.InternedString;

const Wasm = List(u8, .{ .initial_capacity = 1000 });

fn printWasmType(wasm: *Wasm, type_: Entity) !void {
    const builtins = type_.ecs.get(components.Builtins);
    if (eql(type_, builtins.I64) or eql(type_, builtins.U64)) {
        try wasm.appendSlice("i64");
    } else if (eql(type_, builtins.I32) or eql(type_, builtins.U32)) {
        try wasm.appendSlice("i32");
    } else if (eql(type_, builtins.F64)) {
        try wasm.appendSlice("f64");
    } else if (eql(type_, builtins.F32)) {
        try wasm.appendSlice("f32");
    } else {
        panic("\nwasm wasm unsupported type {s}\n", .{literalOf(type_)});
    }
}

fn printWasmFunctionName(wasm: *Wasm, function: Entity) !void {
    try wasm.appendSlice("\n\n  (func $");
    try wasm.appendSlice(literalOf(function.get(components.Module).entity));
    try wasm.append('/');
    try wasm.appendSlice(literalOf(function.get(components.Name).entity));
}

fn printWasmFunctionParameters(wasm: *Wasm, function: Entity) !void {
    for (function.get(components.Parameters).slice()) |parameter| {
        try wasm.appendSlice(" (param $");
        try wasm.appendSlice(literalOf(parameter.get(components.Name).entity));
        try wasm.append(' ');
        try printWasmType(wasm, parameter.get(components.Type).entity);
        try wasm.append(')');
    }
}

fn printWasmFunctionReturnType(wasm: *Wasm, function: Entity) !void {
    try wasm.appendSlice(" (result ");
    try printWasmType(wasm, function.get(components.ReturnType).entity);
    try wasm.append(')');
}

fn printWasmFunctionLocals(wasm: *Wasm, function: Entity) !void {
    const parameters = function.get(components.Parameters).slice();
    const parameter_names = try function.ecs.arena.allocator.alloc(InternedString, parameters.len);
    for (parameters) |parameter, i| {
        parameter_names[i] = parameter.get(components.Name).entity.get(components.Literal).interned;
    }
    const strings = function.ecs.get(Strings);
    for (function.get(components.Locals).slice()) |local| {
        const local_name = local.get(components.Name).entity.get(components.Literal).interned;
        var found = false;
        for (parameter_names) |parameter_name| {
            if (eql(parameter_name, local_name)) {
                found = true;
            }
        }
        if (found) {
            continue;
        }
        try wasm.appendSlice("\n    (local $");
        try wasm.appendSlice(strings.get(local_name));
        try wasm.append(' ');
        try printWasmType(wasm, local.get(components.Type).entity);
        try wasm.append(')');
    }
}

fn printWasmInstruction(wasm: *Wasm, wasm_instruction: Entity) !void {
    switch (wasm_instruction.get(components.WasmInstructionKind)) {
        .i64_const => {
            try wasm.appendSlice("\n    (i64.const ");
            try wasm.appendSlice(literalOf(wasm_instruction.get(components.Constant).entity));
            try wasm.append(')');
        },
        .i32_const => {
            try wasm.appendSlice("\n    (i32.const ");
            try wasm.appendSlice(literalOf(wasm_instruction.get(components.Constant).entity));
            try wasm.append(')');
        },
        .f64_const => {
            try wasm.appendSlice("\n    (f64.const ");
            try wasm.appendSlice(literalOf(wasm_instruction.get(components.Constant).entity));
            try wasm.append(')');
        },
        .f32_const => {
            try wasm.appendSlice("\n    (f32.const ");
            try wasm.appendSlice(literalOf(wasm_instruction.get(components.Constant).entity));
            try wasm.append(')');
        },
        .i64_add => try wasm.appendSlice("\n    (i64.add)"),
        .i32_add => try wasm.appendSlice("\n    (i32.add)"),
        .f64_add => try wasm.appendSlice("\n    (f64.add)"),
        .f32_add => try wasm.appendSlice("\n    (f32.add)"),
        .i64_sub => try wasm.appendSlice("\n    (i64.sub)"),
        .i32_sub => try wasm.appendSlice("\n    (i32.sub)"),
        .f64_sub => try wasm.appendSlice("\n    (f64.sub)"),
        .f32_sub => try wasm.appendSlice("\n    (f32.sub)"),
        .i64_mul => try wasm.appendSlice("\n    (i64.mul)"),
        .i32_mul => try wasm.appendSlice("\n    (i32.mul)"),
        .f64_mul => try wasm.appendSlice("\n    (f64.mul)"),
        .f32_mul => try wasm.appendSlice("\n    (f32.mul)"),
        .i64_div => try wasm.appendSlice("\n    (i64.div_s)"),
        .i32_div => try wasm.appendSlice("\n    (i32.div_s)"),
        .u64_div => try wasm.appendSlice("\n    (i64.div_u)"),
        .u32_div => try wasm.appendSlice("\n    (i32.div_u)"),
        .f64_div => try wasm.appendSlice("\n    (f64.div)"),
        .f32_div => try wasm.appendSlice("\n    (f32.div)"),
        .i64_lt => try wasm.appendSlice("\n    (i64.lt_s)"),
        .i32_lt => try wasm.appendSlice("\n    (i32.lt_s)"),
        .u64_lt => try wasm.appendSlice("\n    (i64.lt_u)"),
        .u32_lt => try wasm.appendSlice("\n    (i32.lt_u)"),
        .f64_lt => try wasm.appendSlice("\n    (f64.lt)"),
        .f32_lt => try wasm.appendSlice("\n    (f32.lt)"),
        .i64_le => try wasm.appendSlice("\n    (i64.le_s)"),
        .i32_le => try wasm.appendSlice("\n    (i32.le_s)"),
        .u64_le => try wasm.appendSlice("\n    (i64.le_u)"),
        .u32_le => try wasm.appendSlice("\n    (i32.le_u)"),
        .f64_le => try wasm.appendSlice("\n    (f64.le)"),
        .f32_le => try wasm.appendSlice("\n    (f32.le)"),
        .i64_gt => try wasm.appendSlice("\n    (i64.gt_s)"),
        .i32_gt => try wasm.appendSlice("\n    (i32.gt_s)"),
        .u64_gt => try wasm.appendSlice("\n    (i64.gt_u)"),
        .u32_gt => try wasm.appendSlice("\n    (i32.gt_u)"),
        .f64_gt => try wasm.appendSlice("\n    (f64.gt)"),
        .f32_gt => try wasm.appendSlice("\n    (f32.gt)"),
        .i64_ge => try wasm.appendSlice("\n    (i64.ge_s)"),
        .i32_ge => try wasm.appendSlice("\n    (i32.ge_s)"),
        .u64_ge => try wasm.appendSlice("\n    (i64.ge_u)"),
        .u32_ge => try wasm.appendSlice("\n    (i32.ge_u)"),
        .f64_ge => try wasm.appendSlice("\n    (f64.ge)"),
        .f32_ge => try wasm.appendSlice("\n    (f32.ge)"),
        .i64_eq => try wasm.appendSlice("\n    (i64.eq)"),
        .i32_eq => try wasm.appendSlice("\n    (i32.eq)"),
        .f64_eq => try wasm.appendSlice("\n    (f64.eq)"),
        .f32_eq => try wasm.appendSlice("\n    (f32.eq)"),
        .i64_ne => try wasm.appendSlice("\n    (i64.ne)"),
        .i32_ne => try wasm.appendSlice("\n    (i32.ne)"),
        .f64_ne => try wasm.appendSlice("\n    (f64.ne)"),
        .f32_ne => try wasm.appendSlice("\n    (f32.ne)"),
        .i64_or => try wasm.appendSlice("\n    (i64.or)"),
        .i32_or => try wasm.appendSlice("\n    (i32.or)"),
        .i64_and => try wasm.appendSlice("\n    (i64.and)"),
        .i32_and => try wasm.appendSlice("\n    (i32.and)"),
        .i64_shl => try wasm.appendSlice("\n    (i64.shl)"),
        .i32_shl => try wasm.appendSlice("\n    (i32.shl)"),
        .u64_shl => try wasm.appendSlice("\n    (i64.shl)"),
        .u32_shl => try wasm.appendSlice("\n    (i32.shl)"),
        .i64_shr => try wasm.appendSlice("\n    (i64.shr_s)"),
        .i32_shr => try wasm.appendSlice("\n    (i32.shr_s)"),
        .u64_shr => try wasm.appendSlice("\n    (i64.shr_u)"),
        .u32_shr => try wasm.appendSlice("\n    (i32.shr_u)"),
        .i64_rem => try wasm.appendSlice("\n    (i64.rem_s)"),
        .i32_rem => try wasm.appendSlice("\n    (i32.rem_s)"),
        .u64_rem => try wasm.appendSlice("\n    (i64.rem_u)"),
        .u32_rem => try wasm.appendSlice("\n    (i32.rem_u)"),
        .i64_xor => try wasm.appendSlice("\n    (i64.xor)"),
        .i32_xor => try wasm.appendSlice("\n    (i32.xor)"),
        .call => {
            try wasm.appendSlice("\n    (call $");
            const callable = wasm_instruction.get(components.Callable).entity;
            try wasm.appendSlice(literalOf(callable.get(components.Module).entity));
            try wasm.append('/');
            try wasm.appendSlice(literalOf(callable.get(components.Name).entity));
            try wasm.append(')');
        },
        .get_local => {
            try wasm.appendSlice("\n    (get_local $");
            const local = wasm_instruction.get(components.Local).entity;
            try wasm.appendSlice(literalOf(local.get(components.Name).entity));
            try wasm.append(')');
        },
        .set_local => {
            try wasm.appendSlice("\n    (set_local $");
            const local = wasm_instruction.get(components.Local).entity;
            try wasm.appendSlice(literalOf(local.get(components.Name).entity));
            try wasm.append(')');
        },
        .if_ => {
            try wasm.appendSlice("\n    if (result ");
            const result = wasm_instruction.get(components.Result).entity;
            try printWasmType(wasm, result.get(components.Type).entity);
            try wasm.append(')');
        },
        .else_ => try wasm.appendSlice("\n    else"),
        .end => try wasm.appendSlice("\n    end"),
    }
}

fn printWasmFunction(wasm: *Wasm, function: Entity) !void {
    try printWasmFunctionName(wasm, function);
    try printWasmFunctionParameters(wasm, function);
    try printWasmFunctionReturnType(wasm, function);
    try printWasmFunctionLocals(wasm, function);
    for (function.get(components.WasmInstructions).slice()) |wasm_instruction| {
        try printWasmInstruction(wasm, wasm_instruction);
    }
    try wasm.append(')');
}

pub fn printWasm(module: Entity) ![]u8 {
    const codebase = module.ecs;
    var wasm = Wasm.init(&codebase.arena.allocator);
    try wasm.appendSlice("(module");
    for (codebase.get(components.Functions).slice()) |function| {
        try printWasmFunction(&wasm, function);
    }
    try wasm.appendSlice("\n\n(export \"_start\" (func $");
    try wasm.appendSlice(literalOf(module));
    try wasm.appendSlice("/start)))");
    return wasm.mutSlice();
}

test "print wasm int literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "I64", "I32", "U64", "U32", "F64", "F32" };
    const wasm_types = [_][]const u8{ "i64", "i32", "i64", "i32", "f64", "f32" };
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(&arena.allocator,
            \\start = function(): {s}
            \\  5
            \\end
        , .{type_}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti", "start");
        try codegen(module);
        const wasm = try printWasm(module);
        try expectEqualStrings(wasm, try std.fmt.allocPrint(&arena.allocator,
            \\(module
            \\
            \\  (func $foo/start (result {s})
            \\    ({s}.const 5))
            \\
            \\(export "_start" (func $foo/start)))
        , .{ wasm_types[i], wasm_types[i] }));
    }
}

test "print wasm int literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "F64", "F32" };
    const wasm_types = [_][]const u8{ "f64", "f32" };
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(&arena.allocator,
            \\start = function(): {s}
            \\  5.3
            \\end
        , .{type_}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti", "start");
        try codegen(module);
        const wasm = try printWasm(module);
        try expectEqualStrings(wasm, try std.fmt.allocPrint(&arena.allocator,
            \\(module
            \\
            \\  (func $foo/start (result {s})
            \\    ({s}.const 5.3))
            \\
            \\(export "_start" (func $foo/start)))
        , .{ wasm_types[i], wasm_types[i] }));
    }
}

test "print wasm call local function" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "F64", "F32" };
    const wasm_types = [_][]const u8{ "f64", "f32" };
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(&arena.allocator,
            \\start = function(): {s}
            \\  baz()
            \\end
            \\
            \\baz = function(): {s}
            \\  10
            \\end
        , .{ type_, type_ }));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti", "start");
        try codegen(module);
        const wasm = try printWasm(module);
        try expectEqualStrings(wasm, try std.fmt.allocPrint(&arena.allocator,
            \\(module
            \\
            \\  (func $foo/start (result {s})
            \\    (call $foo/baz))
            \\
            \\  (func $foo/baz (result {s})
            \\    ({s}.const 10))
            \\
            \\(export "_start" (func $foo/start)))
        , .{ wasm_types[i], wasm_types[i], wasm_types[i] }));
    }
}

test "print wasm call local function with argument" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "I64", "I32", "U64", "U32", "F64", "F32" };
    const wasm_types = [_][]const u8{ "i64", "i32", "i64", "i32", "f64", "f32" };
    const const_kinds = [_][]const u8{ "i64.const", "i32.const", "i64.const", "i32.const", "f64.const", "f32.const" };
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(&arena.allocator,
            \\start = function(): {s}
            \\  id(5)
            \\end
            \\
            \\id = function(x: {s}): {s}
            \\  x
            \\end
        , .{ type_, type_, type_ }));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti", "start");
        try codegen(module);
        const wasm = try printWasm(module);
        try expectEqualStrings(wasm, try std.fmt.allocPrint(&arena.allocator,
            \\(module
            \\
            \\  (func $foo/start (result {s})
            \\    ({s} 5)
            \\    (call $foo/id))
            \\
            \\  (func $foo/id (param $x {s}) (result {s})
            \\    (get_local $x))
            \\
            \\(export "_start" (func $foo/start)))
        , .{ wasm_types[i], const_kinds[i], wasm_types[i], wasm_types[i] }));
    }
}

test "print wasm assignment" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "I64", "U64", "F64" };
    const wasm_types = [_][]const u8{ "i64", "i64", "f64" };
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(&arena.allocator,
            \\start = function(): {s}
            \\  x = 10
            \\  x
            \\end
        , .{type_}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti", "start");
        try codegen(module);
        const wasm = try printWasm(module);
        try expectEqualStrings(wasm, try std.fmt.allocPrint(&arena.allocator,
            \\(module
            \\
            \\  (func $foo/start (result {s})
            \\    ({s}.const 10))
            \\
            \\(export "_start" (func $foo/start)))
        , .{ wasm_types[i], wasm_types[i] }));
    }
}

test "print wasm add" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "I64", "U64", "F64" };
    const wasm_types = [_][]const u8{ "i64", "i64", "f64" };
    const answers = [_][]const u8{ "42", "42", "4.2e+01" };
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(&arena.allocator,
            \\start = function(): {s}
            \\  x: {s} = 10
            \\  y: {s} = 32
            \\  x + y
            \\end
        , .{ type_, type_, type_ }));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti", "start");
        try codegen(module);
        const wasm = try printWasm(module);
        try expectEqualStrings(wasm, try std.fmt.allocPrint(&arena.allocator,
            \\(module
            \\
            \\  (func $foo/start (result {s})
            \\    ({s}.const {s}))
            \\
            \\(export "_start" (func $foo/start)))
        , .{ wasm_types[i], wasm_types[i], answers[i] }));
    }
}
