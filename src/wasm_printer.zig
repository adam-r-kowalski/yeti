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
const codegen = @import("codegen.zig").codegen;
const ecs = @import("ecs.zig");
const Entity = ecs.Entity;
const ECS = ecs.ECS;
const components = @import("components.zig");
const test_utils = @import("test_utils.zig");
const literalOf = test_utils.literalOf;
const typeOf = test_utils.typeOf;
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

fn functionName(function: Entity) ![]const u8 {
    if (function.has(components.WasmName)) |name| {
        return name.slice();
    }
    var wasm_name = components.WasmName.init(function.ecs.arena.allocator());
    try wasm_name.append('$');
    try wasm_name.appendSlice(literalOf(function.get(components.Module).entity));
    try wasm_name.append('/');
    try wasm_name.appendSlice(literalOf(function.get(components.Name).entity));
    for (function.get(components.Parameters).slice()) |parameter| {
        try wasm_name.append('.');
        try wasm_name.appendSlice(literalOf(typeOf(parameter)));
    }
    _ = try function.set(.{wasm_name});
    return wasm_name.slice();
}

fn printWasmFunctionName(wasm: *Wasm, function: Entity) !void {
    try wasm.appendSlice("\n\n  (func ");
    try wasm.appendSlice(try functionName(function));
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
    const parameter_names = try function.ecs.arena.allocator().alloc(InternedString, parameters.len);
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

fn printWasmLabel(wasm: *Wasm, wasm_instruction: Entity) !void {
    const label = wasm_instruction.get(components.Label).value;
    const result = try std.fmt.allocPrint(wasm.allocator, "$.label.{}", .{label});
    try wasm.appendSlice(result);
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
        .i64_add => try wasm.appendSlice("\n    i64.add"),
        .i32_add => try wasm.appendSlice("\n    i32.add"),
        .f64_add => try wasm.appendSlice("\n    f64.add"),
        .f32_add => try wasm.appendSlice("\n    f32.add"),
        .i64_sub => try wasm.appendSlice("\n    i64.sub"),
        .i32_sub => try wasm.appendSlice("\n    i32.sub"),
        .f64_sub => try wasm.appendSlice("\n    f64.sub"),
        .f32_sub => try wasm.appendSlice("\n    f32.sub"),
        .i64_mul => try wasm.appendSlice("\n    i64.mul"),
        .i32_mul => try wasm.appendSlice("\n    i32.mul"),
        .f64_mul => try wasm.appendSlice("\n    f64.mul"),
        .f32_mul => try wasm.appendSlice("\n    f32.mul"),
        .i64_div => try wasm.appendSlice("\n    i64.div_s"),
        .i32_div => try wasm.appendSlice("\n    i32.div_s"),
        .u64_div => try wasm.appendSlice("\n    i64.div_u"),
        .u32_div => try wasm.appendSlice("\n    i32.div_u"),
        .f64_div => try wasm.appendSlice("\n    f64.div"),
        .f32_div => try wasm.appendSlice("\n    f32.div"),
        .i64_lt => try wasm.appendSlice("\n    i64.lt_s"),
        .i32_lt => try wasm.appendSlice("\n    i32.lt_s"),
        .u64_lt => try wasm.appendSlice("\n    i64.lt_u"),
        .u32_lt => try wasm.appendSlice("\n    i32.lt_u"),
        .f64_lt => try wasm.appendSlice("\n    f64.lt"),
        .f32_lt => try wasm.appendSlice("\n    f32.lt"),
        .i64_le => try wasm.appendSlice("\n    i64.le_s"),
        .i32_le => try wasm.appendSlice("\n    i32.le_s"),
        .u64_le => try wasm.appendSlice("\n    i64.le_u"),
        .u32_le => try wasm.appendSlice("\n    i32.le_u"),
        .f64_le => try wasm.appendSlice("\n    f64.le"),
        .f32_le => try wasm.appendSlice("\n    f32.le"),
        .i64_gt => try wasm.appendSlice("\n    i64.gt_s"),
        .i32_gt => try wasm.appendSlice("\n    i32.gt_s"),
        .u64_gt => try wasm.appendSlice("\n    i64.gt_u"),
        .u32_gt => try wasm.appendSlice("\n    i32.gt_u"),
        .f64_gt => try wasm.appendSlice("\n    f64.gt"),
        .f32_gt => try wasm.appendSlice("\n    f32.gt"),
        .i64_ge => try wasm.appendSlice("\n    i64.ge_s"),
        .i32_ge => try wasm.appendSlice("\n    i32.ge_s"),
        .u64_ge => try wasm.appendSlice("\n    i64.ge_u"),
        .u32_ge => try wasm.appendSlice("\n    i32.ge_u"),
        .f64_ge => try wasm.appendSlice("\n    f64.ge"),
        .f32_ge => try wasm.appendSlice("\n    f32.ge"),
        .i64_eq => try wasm.appendSlice("\n    i64.eq"),
        .i32_eq => try wasm.appendSlice("\n    i32.eq"),
        .f64_eq => try wasm.appendSlice("\n    f64.eq"),
        .f32_eq => try wasm.appendSlice("\n    f32.eq"),
        .i64_ne => try wasm.appendSlice("\n    i64.ne"),
        .i32_ne => try wasm.appendSlice("\n    i32.ne"),
        .f64_ne => try wasm.appendSlice("\n    f64.ne"),
        .f32_ne => try wasm.appendSlice("\n    f32.ne"),
        .i64_or => try wasm.appendSlice("\n    i64.or"),
        .i32_or => try wasm.appendSlice("\n    i32.or"),
        .i64_and => try wasm.appendSlice("\n    i64.and"),
        .i32_and => try wasm.appendSlice("\n    i32.and"),
        .i64_shl => try wasm.appendSlice("\n    i64.shl"),
        .i32_shl => try wasm.appendSlice("\n    i32.shl"),
        .u64_shl => try wasm.appendSlice("\n    i64.shl"),
        .u32_shl => try wasm.appendSlice("\n    i32.shl"),
        .i64_shr => try wasm.appendSlice("\n    i64.shr_s"),
        .i32_shr => try wasm.appendSlice("\n    i32.shr_s"),
        .u64_shr => try wasm.appendSlice("\n    i64.shr_u"),
        .u32_shr => try wasm.appendSlice("\n    i32.shr_u"),
        .i64_rem => try wasm.appendSlice("\n    i64.rem_s"),
        .i32_rem => try wasm.appendSlice("\n    i32.rem_s"),
        .u64_rem => try wasm.appendSlice("\n    i64.rem_u"),
        .u32_rem => try wasm.appendSlice("\n    i32.rem_u"),
        .i64_xor => try wasm.appendSlice("\n    i64.xor"),
        .i32_xor => try wasm.appendSlice("\n    i32.xor"),
        .i32_eqz => try wasm.appendSlice("\n    i32.eqz"),
        .call => {
            try wasm.appendSlice("\n    (call ");
            const callable = wasm_instruction.get(components.Callable).entity;
            try wasm.appendSlice(try functionName(callable));
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
            try printWasmType(wasm, wasm_instruction.get(components.Type).entity);
            try wasm.append(')');
        },
        .else_ => try wasm.appendSlice("\n    else"),
        .end => {
            try wasm.appendSlice("\n    end");
            if (wasm_instruction.contains(components.Label)) {
                try wasm.append(' ');
                try printWasmLabel(wasm, wasm_instruction);
            }
        },
        .block => {
            try wasm.appendSlice("\n    block ");
            try printWasmLabel(wasm, wasm_instruction);
        },
        .loop => {
            try wasm.appendSlice("\n    loop ");
            try printWasmLabel(wasm, wasm_instruction);
        },
        .br_if => {
            try wasm.appendSlice("\n    br_if ");
            try printWasmLabel(wasm, wasm_instruction);
        },
        .br => {
            try wasm.appendSlice("\n    br ");
            try printWasmLabel(wasm, wasm_instruction);
        },
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
    var wasm = Wasm.init(codebase.arena.allocator());
    try wasm.appendSlice("(module");
    for (codebase.get(components.Functions).slice()) |function| {
        try printWasmFunction(&wasm, function);
    }
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try wasm.appendSlice("\n\n(export \"_start\" (func ");
    try wasm.appendSlice(try functionName(start));
    try wasm.appendSlice(")))");
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
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start = function(): {s}
            \\  5
            \\end
        , .{type_}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti", "start");
        try codegen(module);
        const wasm = try printWasm(module);
        try expectEqualStrings(wasm, try std.fmt.allocPrint(arena.allocator(),
            \\(module
            \\
            \\  (func $foo/start (result {s})
            \\    ({s}.const 5))
            \\
            \\(export "_start" (func $foo/start)))
        , .{ wasm_types[i], wasm_types[i] }));
    }
}

test "print wasm float literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "F64", "F32" };
    const wasm_types = [_][]const u8{ "f64", "f32" };
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start = function(): {s}
            \\  5.3
            \\end
        , .{type_}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti", "start");
        try codegen(module);
        const wasm = try printWasm(module);
        try expectEqualStrings(wasm, try std.fmt.allocPrint(arena.allocator(),
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
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
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
        try expectEqualStrings(wasm, try std.fmt.allocPrint(arena.allocator(),
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
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
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
        try expectEqualStrings(wasm, try std.fmt.allocPrint(arena.allocator(),
            \\(module
            \\
            \\  (func $foo/start (result {s})
            \\    ({s} 5)
            \\    (call $foo/id.{s}))
            \\
            \\  (func $foo/id.{s} (param $x {s}) (result {s})
            \\    (get_local $x))
            \\
            \\(export "_start" (func $foo/start)))
        , .{ wasm_types[i], const_kinds[i], type_, type_, wasm_types[i], wasm_types[i] }));
    }
}

test "print wasm define int literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "I64", "U64", "F64" };
    const wasm_types = [_][]const u8{ "i64", "i64", "f64" };
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start = function(): {s}
            \\  x = 10
            \\  x
            \\end
        , .{type_}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti", "start");
        try codegen(module);
        const wasm = try printWasm(module);
        try expectEqualStrings(wasm, try std.fmt.allocPrint(arena.allocator(),
            \\(module
            \\
            \\  (func $foo/start (result {s})
            \\    ({s}.const 10))
            \\
            \\(export "_start" (func $foo/start)))
        , .{ wasm_types[i], wasm_types[i] }));
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
    const types = [_][]const u8{ "I64", "I32", "U64", "U32", "F64", "F32" };
    const wasm_types = [_][]const u8{ "i64", "i32", "i64", "i32", "f64", "f32" };
    for (op_strings) |op_string, op_index| {
        for (types) |type_, i| {
            var fs = try MockFileSystem.init(&arena);
            _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
                \\start = function(): {s}
                \\  x: {s} = 8
                \\  y: {s} = 2
                \\  x {s} y
                \\end
            , .{ type_, type_, type_, op_string }));
            const module = try analyzeSemantics(codebase, fs, "foo.yeti", "start");
            try codegen(module);
            const wasm = try printWasm(module);
            try expectEqualStrings(wasm, try std.fmt.allocPrint(arena.allocator(),
                \\(module
                \\
                \\  (func $foo/start (result {s})
                \\    ({s}.const {s}))
                \\
                \\(export "_start" (func $foo/start)))
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
    const types = [_][]const u8{ "I64", "I32", "U64", "U32" };
    const wasm_types = [_][]const u8{ "i64", "i32", "i64", "i32" };
    for (op_strings) |op_string, op_index| {
        for (types) |type_, i| {
            var fs = try MockFileSystem.init(&arena);
            _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
                \\start = function(): {s}
                \\  x: {s} = 8
                \\  y: {s} = 2
                \\  x {s} y
                \\end
            , .{ type_, type_, type_, op_string }));
            const module = try analyzeSemantics(codebase, fs, "foo.yeti", "start");
            try codegen(module);
            const wasm = try printWasm(module);
            try expectEqualStrings(wasm, try std.fmt.allocPrint(arena.allocator(),
                \\(module
                \\
                \\  (func $foo/start (result {s})
                \\    ({s}.const {s}))
                \\
                \\(export "_start" (func $foo/start)))
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
    const types = [_][]const u8{ "I64", "I32", "U64", "U32", "F64", "F32" };
    const wasm_types = [_][]const u8{ "i64", "i32", "i64", "i32", "f64", "f32" };
    for (op_strings) |op_string, op_index| {
        for (types) |type_, i| {
            var fs = try MockFileSystem.init(&arena);
            _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
                \\start = function(): {s}
                \\  id(10) {s} id(25)
                \\end
                \\
                \\id = function(x: {s}): {s}
                \\  x
                \\end
            , .{ type_, op_string, type_, type_ }));
            const module = try analyzeSemantics(codebase, fs, "foo.yeti", "start");
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
                \\    (get_local $x))
                \\
                \\(export "_start" (func $foo/start)))
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

test "print wasm int binary op non constant" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const op_strings = [_][]const u8{ "%", "&", "|", "^", "<<", ">>" };
    const instructions = [_][4][]const u8{
        [_][]const u8{ "i64.rem_s", "i32.rem_s", "i64.rem_u", "i32.rem_u" },
        [_][]const u8{ "i64.and", "i32.and", "i64.and", "i32.and" },
        [_][]const u8{ "i64.or", "i32.or", "i64.or", "i32.or" },
        [_][]const u8{ "i64.xor", "i32.xor", "i64.xor", "i32.xor" },
        [_][]const u8{ "i64.shl", "i32.shl", "i64.shl", "i32.shl" },
        [_][]const u8{ "i64.shr_s", "i32.shr_s", "i64.shr_u", "i32.shr_u" },
    };
    const types = [_][]const u8{ "I64", "I32", "U64", "U32" };
    const wasm_types = [_][]const u8{ "i64", "i32", "i64", "i32" };
    for (op_strings) |op_string, op_index| {
        for (types) |type_, i| {
            var fs = try MockFileSystem.init(&arena);
            _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
                \\start = function(): {s}
                \\  id(10) {s} id(25)
                \\end
                \\
                \\id = function(x: {s}): {s}
                \\  x
                \\end
            , .{ type_, op_string, type_, type_ }));
            const module = try analyzeSemantics(codebase, fs, "foo.yeti", "start");
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
                \\    (get_local $x))
                \\
                \\(export "_start" (func $foo/start)))
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

test "print wasm if then else where then branch taken statically" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "I64", "I32", "U64", "U32", "F64", "F32" };
    const wasm_types = [_][]const u8{ "i64", "i32", "i64", "i32", "f64", "f32" };
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start = function(): {s}
            \\  if 1 then 20 else 30 end
            \\end
        , .{type_of}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti", "start");
        try codegen(module);
        const wasm = try printWasm(module);
        try expectEqualStrings(wasm, try std.fmt.allocPrint(arena.allocator(),
            \\(module
            \\
            \\  (func $foo/start (result {s})
            \\    ({s}.const 20))
            \\
            \\(export "_start" (func $foo/start)))
        , .{ wasm_types[i], wasm_types[i] }));
    }
}

test "print wasm if then else where else branch taken statically" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "I64", "I32", "U64", "U32", "F64", "F32" };
    const wasm_types = [_][]const u8{ "i64", "i32", "i64", "i32", "f64", "f32" };
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start = function(): {s}
            \\  if 0 then 20 else 30 end
            \\end
        , .{type_of}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti", "start");
        try codegen(module);
        const wasm = try printWasm(module);
        try expectEqualStrings(wasm, try std.fmt.allocPrint(arena.allocator(),
            \\(module
            \\
            \\  (func $foo/start (result {s})
            \\    ({s}.const 30))
            \\
            \\(export "_start" (func $foo/start)))
        , .{ wasm_types[i], wasm_types[i] }));
    }
}

test "print wasm if then else non const conditional" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "I64", "I32", "U64", "U32", "F64", "F32" };
    const wasm_types = [_][]const u8{ "i64", "i32", "i64", "i32", "f64", "f32" };
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start = function(): {s}
            \\  if f() then 20 else 30 end
            \\end
            \\
            \\f = function(): I32 1 end
        , .{type_of}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti", "start");
        try codegen(module);
        const wasm = try printWasm(module);
        try expectEqualStrings(wasm, try std.fmt.allocPrint(arena.allocator(),
            \\(module
            \\
            \\  (func $foo/start (result {s})
            \\    (call $foo/f)
            \\    if (result {s})
            \\    ({s}.const 20)
            \\    else
            \\    ({s}.const 30)
            \\    end)
            \\
            \\  (func $foo/f (result i32)
            \\    (i32.const 1))
            \\
            \\(export "_start" (func $foo/start)))
        , .{ wasm_types[i], wasm_types[i], wasm_types[i], wasm_types[i] }));
    }
}

test "print wasm assignment" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "I64", "I32", "U64", "U32", "F64", "F32" };
    const wasm_types = [_][]const u8{ "i64", "i32", "i64", "i32", "f64", "f32" };
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start = function(): {s}
            \\  x: {s} = 10
            \\  x := 3
            \\  x
            \\end
        , .{ type_of, type_of }));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti", "start");
        try codegen(module);
        const wasm = try printWasm(module);
        try expectEqualStrings(wasm, try std.fmt.allocPrint(arena.allocator(),
            \\(module
            \\
            \\  (func $foo/start (result {s})
            \\    (local $x {s})
            \\    ({s}.const 10)
            \\    (set_local $x)
            \\    ({s}.const 3)
            \\    (set_local $x)
            \\    (get_local $x))
            \\
            \\(export "_start" (func $foo/start)))
        , .{ wasm_types[i], wasm_types[i], wasm_types[i], wasm_types[i] }));
    }
}

test "print wasm while loop" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = function(): I32
        \\  i = 0
        \\  while i < 10 then
        \\      i := i + 1
        \\  end
        \\  i
        \\end
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti", "start");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/start (result i32)
        \\    (local $i i32)
        \\    (i32.const 0)
        \\    (set_local $i)
        \\    block $.label.0
        \\    loop $.label.1
        \\    (get_local $i)
        \\    (i32.const 10)
        \\    i32.lt_s
        \\    i32.eqz
        \\    br_if $.label.0
        \\    (get_local $i)
        \\    (i32.const 1)
        \\    i32.add
        \\    (set_local $i)
        \\    br $.label.1
        \\    end $.label.1
        \\    end $.label.0
        \\    (get_local $i))
        \\
        \\(export "_start" (func $foo/start)))
    );
}
