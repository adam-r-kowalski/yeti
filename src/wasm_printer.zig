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

fn printWasmType(wasm: *Wasm, type_of: Entity) error{OutOfMemory}!void {
    const b = type_of.ecs.get(components.Builtins);
    const builtins = [_]Entity{ b.I64, b.U64, b.I32, b.U32, b.I16, b.U16, b.I8, b.U8, b.F64, b.F32, b.I64X2, b.I32X4, b.I16X8, b.I8X16, b.U64X2, b.U32X4, b.U16X8, b.U8X16, b.F64X2, b.F32X4 };
    const strings = [_][]const u8{ "i64", "i64", "i32", "i32", "i32", "i32", "i32", "i32", "f64", "f32", "v128", "v128", "v128", "v128", "v128", "v128", "v128", "v128", "v128", "v128" };
    for (builtins) |builtin, i| {
        if (eql(type_of, builtin)) {
            return try wasm.appendSlice(strings[i]);
        }
    }
    if (type_of.has(components.ParentType)) |parent_type| {
        assert(eql(parent_type.entity, b.Ptr));
        return try wasm.appendSlice("i32");
    }
    if (type_of.has(components.Fields)) |field_component| {
        const fields = field_component.slice();
        const last = fields.len - 1;
        for (fields) |field, i| {
            try printWasmType(wasm, typeOf(field));
            if (i < last) {
                try wasm.append(' ');
            }
        }
        return;
    }
    panic("\nwasm wasm unsupported type {s}\n", .{literalOf(type_of)});
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
    const builtins = function.ecs.get(components.Builtins);
    for (function.get(components.Parameters).slice()) |parameter| {
        try wasm_name.append('.');
        const type_of = typeOf(parameter);
        const literal = literalOf(type_of);
        if (type_of.has(components.ParentType)) |parent_type| {
            assert(eql(parent_type.entity, builtins.Ptr));
            for (literal) |c| {
                switch (c) {
                    '(' => try wasm_name.append('.'),
                    ')' => continue,
                    else => try wasm_name.append(c),
                }
            }
        } else {
            try wasm_name.appendSlice(literal);
        }
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
        const type_of = typeOf(parameter);
        const literal = literalOf(parameter.get(components.Name).entity);
        if (type_of.has(components.AstKind)) |ast_kind| {
            if (ast_kind == .struct_) {
                for (type_of.get(components.Fields).slice()) |field| {
                    try wasm.appendSlice(" (param $");
                    try wasm.appendSlice(literal);
                    try wasm.append('.');
                    try wasm.appendSlice(literalOf(field));
                    try wasm.append(' ');
                    try printWasmType(wasm, typeOf(field));
                    try wasm.append(')');
                }
                return;
            }
        }
        try wasm.appendSlice(" (param $");
        try wasm.appendSlice(literal);
        try wasm.append(' ');
        try printWasmType(wasm, type_of);
        try wasm.append(')');
    }
}

fn printWasmFunctionReturnType(wasm: *Wasm, function: Entity) !void {
    const return_type = function.get(components.ReturnType).entity;
    if (eql(return_type, function.ecs.get(components.Builtins).Void)) {
        return;
    }
    try wasm.appendSlice(" (result ");
    try printWasmType(wasm, return_type);
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
        const type_of = typeOf(local);
        if (type_of.has(components.AstKind)) |ast_kind| {
            if (ast_kind == .struct_) {
                for (type_of.get(components.Fields).slice()) |field| {
                    try wasm.appendSlice("\n    (local $");
                    try wasm.appendSlice(strings.get(local_name));
                    try wasm.append('.');
                    try wasm.appendSlice(literalOf(field));
                    try wasm.append(' ');
                    try printWasmType(wasm, typeOf(field));
                    try wasm.append(')');
                }
                continue;
            }
        }
        try wasm.appendSlice("\n    (local $");
        try wasm.appendSlice(strings.get(local_name));
        try wasm.append(' ');
        try printWasmType(wasm, type_of);
        try wasm.append(')');
    }
}

fn printWasmLabel(wasm: *Wasm, wasm_instruction: Entity) !void {
    const label = wasm_instruction.get(components.Label).value;
    const result = try std.fmt.allocPrint(wasm.allocator, "$.label.{}", .{label});
    try wasm.appendSlice(result);
}

fn printWasmLocalSet(wasm: *Wasm, wasm_instruction: Entity) !void {
    const local = wasm_instruction.get(components.Local).entity;
    const type_of = typeOf(local);
    const literal = literalOf(local.get(components.Name).entity);
    if (type_of.has(components.AstKind)) |ast_kind| {
        if (ast_kind == .struct_) {
            const fields = type_of.get(components.Fields).slice();
            var i = fields.len;
            while (i > 0) : (i -= 1) {
                try wasm.appendSlice("\n    (local.set $");
                try wasm.appendSlice(literal);
                try wasm.append('.');
                try wasm.appendSlice(literalOf(fields[i - 1].get(components.Name).entity));
                try wasm.append(')');
            }
            return;
        }
    }
    try wasm.appendSlice("\n    (local.set $");
    try wasm.appendSlice(literal);
    try wasm.append(')');
}

fn printWasmLocalGet(wasm: *Wasm, wasm_instruction: Entity) !void {
    const local = wasm_instruction.get(components.Local).entity;
    const type_of = typeOf(local);
    const literal = literalOf(local.get(components.Name).entity);
    if (type_of.has(components.AstKind)) |ast_kind| {
        if (ast_kind == .struct_) {
            for (type_of.get(components.Fields).slice()) |field| {
                try wasm.appendSlice("\n    (local.get $");
                try wasm.appendSlice(literal);
                try wasm.append('.');
                try wasm.appendSlice(literalOf(field.get(components.Name).entity));
                try wasm.append(')');
            }
            return;
        }
    }
    try wasm.appendSlice("\n    (local.get $");
    try wasm.appendSlice(literal);
    try wasm.append(')');
}

fn printWasmField(wasm: *Wasm, wasm_instruction: Entity) !void {
    const local = wasm_instruction.get(components.Local).entity;
    try wasm.appendSlice("\n    (local.get $");
    try wasm.appendSlice(literalOf(local.get(components.Name).entity));
    try wasm.append('.');
    try wasm.appendSlice(literalOf(wasm_instruction.get(components.Field).entity));
    try wasm.append(')');
}

fn printWasmAssignField(wasm: *Wasm, wasm_instruction: Entity) !void {
    const local = wasm_instruction.get(components.Local).entity;
    try wasm.appendSlice("\n    (local.set $");
    try wasm.appendSlice(literalOf(local.get(components.Name).entity));
    try wasm.append('.');
    try wasm.appendSlice(literalOf(wasm_instruction.get(components.Field).entity));
    try wasm.append(')');
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
        .i32_add_mod_16 => {
            try wasm.appendSlice("\n    i32.add");
            try wasm.appendSlice("\n    (i32.const 65535)");
            try wasm.appendSlice("\n    i32.and");
        },
        .i32_add_mod_8 => {
            try wasm.appendSlice("\n    i32.add");
            try wasm.appendSlice("\n    (i32.const 255)");
            try wasm.appendSlice("\n    i32.and");
        },
        .f64_add => try wasm.appendSlice("\n    f64.add"),
        .f32_add => try wasm.appendSlice("\n    f32.add"),
        .i64_sub => try wasm.appendSlice("\n    i64.sub"),
        .i32_sub => try wasm.appendSlice("\n    i32.sub"),
        .i32_sub_mod_16 => {
            try wasm.appendSlice("\n    i32.sub");
            try wasm.appendSlice("\n    (i32.const 65535)");
            try wasm.appendSlice("\n    i32.and");
        },
        .i32_sub_mod_8 => {
            try wasm.appendSlice("\n    i32.sub");
            try wasm.appendSlice("\n    (i32.const 255)");
            try wasm.appendSlice("\n    i32.and");
        },
        .f64_sub => try wasm.appendSlice("\n    f64.sub"),
        .f32_sub => try wasm.appendSlice("\n    f32.sub"),
        .i64_mul => try wasm.appendSlice("\n    i64.mul"),
        .i32_mul => try wasm.appendSlice("\n    i32.mul"),
        .i32_mul_mod_16 => {
            try wasm.appendSlice("\n    i32.mul");
            try wasm.appendSlice("\n    (i32.const 65535)");
            try wasm.appendSlice("\n    i32.and");
        },
        .i32_mul_mod_8 => {
            try wasm.appendSlice("\n    i32.mul");
            try wasm.appendSlice("\n    (i32.const 255)");
            try wasm.appendSlice("\n    i32.and");
        },
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
        .local_get => try printWasmLocalGet(wasm, wasm_instruction),
        .local_set => try printWasmLocalSet(wasm, wasm_instruction),
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
        .i64_store => try wasm.appendSlice("\n    i64.store"),
        .i32_store => try wasm.appendSlice("\n    i32.store"),
        .f64_store => try wasm.appendSlice("\n    f64.store"),
        .f32_store => try wasm.appendSlice("\n    f32.store"),
        .i64_load => try wasm.appendSlice("\n    i64.load"),
        .i32_load => try wasm.appendSlice("\n    i32.load"),
        .f64_load => try wasm.appendSlice("\n    f64.load"),
        .f32_load => try wasm.appendSlice("\n    f32.load"),
        .v128_load => try wasm.appendSlice("\n    v128.load"),
        .v128_store => try wasm.appendSlice("\n    v128.store"),
        .i64x2_add => try wasm.appendSlice("\n    i64x2.add"),
        .i32x4_add => try wasm.appendSlice("\n    i32x4.add"),
        .i16x8_add => try wasm.appendSlice("\n    i16x8.add"),
        .i8x16_add => try wasm.appendSlice("\n    i8x16.add"),
        .f64x2_add => try wasm.appendSlice("\n    f64x2.add"),
        .f32x4_add => try wasm.appendSlice("\n    f32x4.add"),
        .i64x2_sub => try wasm.appendSlice("\n    i64x2.sub"),
        .i32x4_sub => try wasm.appendSlice("\n    i32x4.sub"),
        .i16x8_sub => try wasm.appendSlice("\n    i16x8.sub"),
        .i8x16_sub => try wasm.appendSlice("\n    i8x16.sub"),
        .f64x2_sub => try wasm.appendSlice("\n    f64x2.sub"),
        .f32x4_sub => try wasm.appendSlice("\n    f32x4.sub"),
        .i64x2_mul => try wasm.appendSlice("\n    i64x2.mul"),
        .i32x4_mul => try wasm.appendSlice("\n    i32x4.mul"),
        .i16x8_mul => try wasm.appendSlice("\n    i16x8.mul"),
        .i8x16_mul => try wasm.appendSlice("\n    i8x16.mul"),
        .f64x2_mul => try wasm.appendSlice("\n    f64x2.mul"),
        .f32x4_mul => try wasm.appendSlice("\n    f32x4.mul"),
        .f64x2_div => try wasm.appendSlice("\n    f64x2.div"),
        .f32x4_div => try wasm.appendSlice("\n    f32x4.div"),
        .field => try printWasmField(wasm, wasm_instruction),
        .assign_field => try printWasmAssignField(wasm, wasm_instruction),
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

fn printWasmForeignImport(wasm: *Wasm, function: Entity) !void {
    try wasm.appendSlice("\n\n  (import \"");
    try wasm.appendSlice(literalOf(function.get(components.ForeignModule).entity));
    try wasm.appendSlice("\" \"");
    try wasm.appendSlice(literalOf(function.get(components.ForeignName).entity));
    try wasm.appendSlice("\" (func ");
    try wasm.appendSlice(try functionName(function));
    try printWasmFunctionParameters(wasm, function);
    try printWasmFunctionReturnType(wasm, function);
    try wasm.appendSlice("))");
}

pub fn printWasm(module: Entity) ![]u8 {
    const codebase = module.ecs;
    var wasm = Wasm.init(codebase.arena.allocator());
    try wasm.appendSlice("(module");
    for (codebase.get(components.ForeignImports).slice()) |foreign_import| {
        try printWasmForeignImport(&wasm, foreign_import);
    }
    for (codebase.get(components.Functions).slice()) |function| {
        try printWasmFunction(&wasm, function);
    }
    const top_level = module.get(components.TopLevel);
    const foreign_exports = module.get(components.ForeignExports).slice();
    if (foreign_exports.len > 0) {
        for (foreign_exports) |foreign_export| {
            const literal = foreign_export.get(components.Literal);
            const overload = top_level.findLiteral(literal).get(components.Overloads).slice()[0];
            try wasm.appendSlice("\n\n  (export \"");
            try wasm.appendSlice(literalOf(overload.get(components.Name).entity));
            try wasm.appendSlice("\" (func ");
            try wasm.appendSlice(try functionName(overload));
            try wasm.appendSlice("))");
        }
    } else {
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        try wasm.appendSlice("\n\n  (export \"_start\" (func ");
        try wasm.appendSlice(try functionName(start));
        try wasm.appendSlice("))");
    }

    if (module.ecs.contains(components.UsesMemory)) {
        try wasm.appendSlice("\n\n  (memory 1)");
    }
    try wasm.append(')');
    return wasm.mutSlice();
}

test "print wasm int literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "i64", "i32", "i16", "i8", "u64", "u32", "u16", "u8", "f64", "f32" };
    const wasm_types = [_][]const u8{ "i64", "i32", "i32", "i32", "i64", "i32", "i32", "i32", "f64", "f32" };
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start = fn(): {s}
            \\  5
            \\end
        , .{type_}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        try codegen(module);
        const wasm = try printWasm(module);
        try expectEqualStrings(wasm, try std.fmt.allocPrint(arena.allocator(),
            \\(module
            \\
            \\  (func $foo/start (result {s})
            \\    ({s}.const 5))
            \\
            \\  (export "_start" (func $foo/start)))
        , .{ wasm_types[i], wasm_types[i] }));
    }
}

test "print wasm float literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "f64", "f32" };
    const wasm_types = [_][]const u8{ "f64", "f32" };
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start = fn(): {s}
            \\  5.3
            \\end
        , .{type_}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        try codegen(module);
        const wasm = try printWasm(module);
        try expectEqualStrings(wasm, try std.fmt.allocPrint(arena.allocator(),
            \\(module
            \\
            \\  (func $foo/start (result {s})
            \\    ({s}.const 5.3))
            \\
            \\  (export "_start" (func $foo/start)))
        , .{ wasm_types[i], wasm_types[i] }));
    }
}

test "print wasm call local function" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "f64", "f32" };
    const wasm_types = [_][]const u8{ "f64", "f32" };
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start = fn(): {s}
            \\  baz()
            \\end
            \\
            \\baz = fn(): {s}
            \\  10
            \\end
        , .{ type_, type_ }));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
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
            \\  (export "_start" (func $foo/start)))
        , .{ wasm_types[i], wasm_types[i], wasm_types[i] }));
    }
}

test "print wasm call local function with argument" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "i64", "i32", "u64", "u32", "f64", "f32" };
    const wasm_types = [_][]const u8{ "i64", "i32", "i64", "i32", "f64", "f32" };
    const const_kinds = [_][]const u8{ "i64.const", "i32.const", "i64.const", "i32.const", "f64.const", "f32.const" };
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start = fn(): {s}
            \\  id(5)
            \\end
            \\
            \\id = fn(x: {s}): {s}
            \\  x
            \\end
        , .{ type_, type_, type_ }));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
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
            \\    (local.get $x))
            \\
            \\  (export "_start" (func $foo/start)))
        , .{ wasm_types[i], const_kinds[i], type_, type_, wasm_types[i], wasm_types[i] }));
    }
}

test "print wasm define int literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "i64", "u64", "f64" };
    const wasm_types = [_][]const u8{ "i64", "i64", "f64" };
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start = fn(): {s}
            \\  x = 10
            \\  x
            \\end
        , .{type_}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        try codegen(module);
        const wasm = try printWasm(module);
        try expectEqualStrings(wasm, try std.fmt.allocPrint(arena.allocator(),
            \\(module
            \\
            \\  (func $foo/start (result {s})
            \\    ({s}.const 10))
            \\
            \\  (export "_start" (func $foo/start)))
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
    const types = [_][]const u8{ "i64", "i32", "u64", "u32", "f64", "f32" };
    const wasm_types = [_][]const u8{ "i64", "i32", "i64", "i32", "f64", "f32" };
    for (op_strings) |op_string, op_index| {
        for (types) |type_, i| {
            var fs = try MockFileSystem.init(&arena);
            _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
                \\start = fn(): {s}
                \\  x: {s} = 8
                \\  y: {s} = 2
                \\  x {s} y
                \\end
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
                \\start = fn(): {s}
                \\  x: {s} = 8
                \\  y: {s} = 2
                \\  x {s} y
                \\end
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
                \\start = fn(): {s}
                \\  id(10) {s} id(25)
                \\end
                \\
                \\id = fn(x: {s}): {s}
                \\  x
                \\end
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
                \\start = fn(): {s}
                \\  id(10) {s} id(25)
                \\end
                \\
                \\id = fn(x: {s}): {s}
                \\  x
                \\end
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
                \\start = fn(): {s}
                \\  id(10) {s} id(25)
                \\end
                \\
                \\id = fn(x: {s}): {s}
                \\  x
                \\end
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

test "print wasm if then else where then branch taken statically" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "i64", "i32", "u64", "u32", "f64", "f32" };
    const wasm_types = [_][]const u8{ "i64", "i32", "i64", "i32", "f64", "f32" };
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start = fn(): {s}
            \\  if 1 then 20 else 30 end
            \\end
        , .{type_of}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        try codegen(module);
        const wasm = try printWasm(module);
        try expectEqualStrings(wasm, try std.fmt.allocPrint(arena.allocator(),
            \\(module
            \\
            \\  (func $foo/start (result {s})
            \\    ({s}.const 20))
            \\
            \\  (export "_start" (func $foo/start)))
        , .{ wasm_types[i], wasm_types[i] }));
    }
}

test "print wasm if then else where else branch taken statically" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "i64", "i32", "u64", "u32", "f64", "f32" };
    const wasm_types = [_][]const u8{ "i64", "i32", "i64", "i32", "f64", "f32" };
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start = fn(): {s}
            \\  if 0 then 20 else 30 end
            \\end
        , .{type_of}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        try codegen(module);
        const wasm = try printWasm(module);
        try expectEqualStrings(wasm, try std.fmt.allocPrint(arena.allocator(),
            \\(module
            \\
            \\  (func $foo/start (result {s})
            \\    ({s}.const 30))
            \\
            \\  (export "_start" (func $foo/start)))
        , .{ wasm_types[i], wasm_types[i] }));
    }
}

test "print wasm if then else non const conditional" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "i64", "i32", "u64", "u32", "f64", "f32" };
    const wasm_types = [_][]const u8{ "i64", "i32", "i64", "i32", "f64", "f32" };
    for (types) |type_of, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start = fn(): {s}
            \\  if f() then 20 else 30 end
            \\end
            \\
            \\f = fn(): i32 1 end
        , .{type_of}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
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
            \\  (export "_start" (func $foo/start)))
        , .{ wasm_types[i], wasm_types[i], wasm_types[i], wasm_types[i] }));
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
            \\start = fn(): {s}
            \\  x: {s} = 10
            \\  x = 3
            \\  x
            \\end
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

test "print wasm while loop" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = fn(): i32
        \\  i = 0
        \\  while i < 10 then
        \\      i = i + 1
        \\  end
        \\  i
        \\end
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/start (result i32)
        \\    (local $i i32)
        \\    (i32.const 0)
        \\    (local.set $i)
        \\    block $.label.0
        \\    loop $.label.1
        \\    (local.get $i)
        \\    (i32.const 10)
        \\    i32.lt_s
        \\    i32.eqz
        \\    br_if $.label.0
        \\    (local.get $i)
        \\    (i32.const 1)
        \\    i32.add
        \\    (local.set $i)
        \\    br $.label.1
        \\    end $.label.1
        \\    end $.label.0
        \\    (local.get $i))
        \\
        \\  (export "_start" (func $foo/start)))
    );
}

test "print wasm foreign export" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\square = fn(x: i64): i64
        \\  x * x
        \\end
        \\
        \\area = fn(width: f64, height: f64): f64
        \\  width * height
        \\end
        \\
        \\foreign_export(square)
        \\
        \\foreign_export(area)
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/square.i64 (param $x i64) (result i64)
        \\    (local.get $x)
        \\    (local.get $x)
        \\    i64.mul)
        \\
        \\  (func $foo/area.f64.f64 (param $width f64) (param $height f64) (result f64)
        \\    (local.get $width)
        \\    (local.get $height)
        \\    f64.mul)
        \\
        \\  (export "square" (func $foo/square.i64))
        \\
        \\  (export "area" (func $foo/area.f64.f64)))
    );
}

test "print wasm foreign import" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\log = foreign_import("console", "log", Fn(value: i64): void)
        \\
        \\start = fn(): void
        \\  log(10)
        \\end
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (import "console" "log" (func $foo/log.i64 (param $value i64)))
        \\
        \\  (func $foo/start
        \\    (i64.const 10)
        \\    (call $foo/log.i64))
        \\
        \\  (export "_start" (func $foo/start)))
    );
}

test "print wasm pointer" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = fn(): *i64
        \\  cast(*i64, 0)
        \\end
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/start (result i32)
        \\    (i32.const 0))
        \\
        \\  (export "_start" (func $foo/start)))
    );
}

test "print wasm pointer store" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = fn(): void
        \\  ptr = cast(*i64, 0)
        \\  *ptr = 10
        \\end
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
        \\    (i64.const 10)
        \\    i64.store)
        \\
        \\  (export "_start" (func $foo/start))
        \\
        \\  (memory 1))
    );
}

test "print wasm pointer load" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = fn(): i64
        \\  ptr = cast(*i64, 0)
        \\  *ptr
        \\end
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/start (result i64)
        \\    (local $ptr i32)
        \\    (i32.const 0)
        \\    (local.set $ptr)
        \\    (local.get $ptr)
        \\    i64.load)
        \\
        \\  (export "_start" (func $foo/start))
        \\
        \\  (memory 1))
    );
}

test "print wasm pointer as parameter" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\f = fn(ptr: *i32): i32
        \\  0
        \\end
        \\
        \\foreign_export(f)
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/f.*i32 (param $ptr i32) (result i32)
        \\    (i32.const 0))
        \\
        \\  (export "f" (func $foo/f.*i32)))
    );
}

test "print wasm adding pointer and int literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\f = fn(ptr: *i64): *i64
        \\  ptr + 1
        \\end
        \\
        \\foreign_export(f)
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/f.*i64 (param $ptr i32) (result i32)
        \\    (local.get $ptr)
        \\    (i32.const 8)
        \\    i32.add)
        \\
        \\  (export "f" (func $foo/f.*i64)))
    );
}

test "print wasm subtracting pointer and int literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\f = fn(ptr: *i64): *i64
        \\  ptr - 1
        \\end
        \\
        \\foreign_export(f)
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/f.*i64 (param $ptr i32) (result i32)
        \\    (local.get $ptr)
        \\    (i32.const 8)
        \\    i32.sub)
        \\
        \\  (export "f" (func $foo/f.*i64)))
    );
}

test "print wasm adding pointer and i32" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\f = fn(ptr: *i64, len: i32): *i64
        \\  ptr + len
        \\end
        \\
        \\foreign_export(f)
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/f.*i64.i32 (param $ptr i32) (param $len i32) (result i32)
        \\    (local.get $ptr)
        \\    (local.get $len)
        \\    (i32.const 8)
        \\    i32.mul
        \\    i32.add)
        \\
        \\  (export "f" (func $foo/f.*i64.i32)))
    );
}

test "print wasm pointer v128 load" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = fn(): i64x2
        \\  ptr = cast(*i64x2, 0)
        \\  *ptr
        \\end
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
        \\  (memory 1))
    );
}

test "print wasm pointer v128 store" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start = fn(): void
        \\  ptr = cast(*i64x2, 0)
        \\  *ptr = *ptr
        \\end
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
        \\  (memory 1))
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
                \\start = fn(): {s}
                \\  v = *cast(*{s}, 0)
                \\  v {s} v
                \\end
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
                \\  (memory 1))
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
                \\start = fn(): {s}
                \\  v = *cast(*{s}, 0)
                \\  v {s} v
                \\end
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
                \\  (memory 1))
            , .{instructions[type_index][i]}));
        }
    }
}

test "print wasm struct" {
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
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/start (result f64 f64)
        \\    (f64.const 10)
        \\    (f64.const 30))
        \\
        \\  (export "_start" (func $foo/start)))
    );
}

test "print wasm assign struct to variable" {
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
        \\  r = Rectangle(10, 30)
        \\  r
        \\end
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/start (result f64 f64)
        \\    (local $r.width f64)
        \\    (local $r.height f64)
        \\    (f64.const 10)
        \\    (f64.const 30)
        \\    (local.set $r.height)
        \\    (local.set $r.width)
        \\    (local.get $r.width)
        \\    (local.get $r.height))
        \\
        \\  (export "_start" (func $foo/start)))
    );
}

test "print wasm pass struct to function" {
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
        \\id = fn(r: Rectangle): Rectangle
        \\  r
        \\end
        \\
        \\start = fn(): Rectangle
        \\  id(Rectangle(10, 30))
        \\end
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/start (result f64 f64)
        \\    (f64.const 10)
        \\    (f64.const 30)
        \\    (call $foo/id.Rectangle))
        \\
        \\  (func $foo/id.Rectangle (param $r.width f64) (param $r.height f64) (result f64 f64)
        \\    (local.get $r.width)
        \\    (local.get $r.height))
        \\
        \\  (export "_start" (func $foo/start)))
    );
}

test "print wasm struct field access" {
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
        \\start = fn(): f64
        \\  r = Rectangle(10, 30)
        \\  r.width
        \\end
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/start (result f64)
        \\    (local $r.width f64)
        \\    (local $r.height f64)
        \\    (f64.const 10)
        \\    (f64.const 30)
        \\    (local.set $r.height)
        \\    (local.set $r.width)
        \\    (local.get $r.width))
        \\
        \\  (export "_start" (func $foo/start)))
    );
}

test "print wasm struct field write" {
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
        \\  r = Rectangle(10, 30)
        \\  r.width = 45
        \\  r
        \\end
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/start (result f64 f64)
        \\    (local $r.width f64)
        \\    (local $r.height f64)
        \\    (f64.const 10)
        \\    (f64.const 30)
        \\    (local.set $r.height)
        \\    (local.set $r.width)
        \\    (f64.const 45)
        \\    (local.set $r.width)
        \\    (local.get $r.width)
        \\    (local.get $r.height))
        \\
        \\  (export "_start" (func $foo/start)))
    );
}
