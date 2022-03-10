const std = @import("std");
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
const query = @import("query.zig");
const literalOf = query.literalOf;
const typeOf = query.typeOf;
const valueType = query.valueType;
const valueOf = query.valueOf;
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
        if (eql(parent_type.entity, b.Ptr)) {
            return try wasm.appendSlice("i32");
        }
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
    panic("\nwasm unsupported type {s}\n", .{literalOf(type_of)});
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
            if (eql(parent_type.entity, builtins.Ptr)) {
                try wasm_name.appendSlice("ptr.");
                try wasm_name.appendSlice(literal[1..]);
                continue;
            }
            assert(eql(parent_type.entity, builtins.Array));
            try wasm_name.appendSlice("array.");
            try wasm_name.appendSlice(literal[2..]);
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
        .i32_load8_u => try wasm.appendSlice("\n    i32.load8_u"),
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

fn printBytesAsHex(comptime T: type, wasm: *Wasm, allocator: Allocator, values: []const Entity) !void {
    for (values) |value| {
        var data = (try valueOf(T, value)).?;
        const bytes = @ptrCast([*]u8, &data);
        var i: usize = 0;
        while (i < @sizeOf(T)) : (i += 1) {
            try wasm.append('\\');
            const octal = try std.fmt.allocPrint(allocator, "{x}", .{bytes[i]});
            if (octal.len == 1) {
                try wasm.append('0');
            }
            try wasm.appendSlice(octal);
        }
    }
}

fn printDataSegment(wasm: *Wasm, codebase: *ECS) !void {
    if (codebase.contains(components.UsesMemory)) {
        const data_segment = codebase.get(components.DataSegment);
        const allocator = codebase.arena.allocator();
        const b = codebase.get(components.Builtins);
        for (data_segment.entities.slice()) |entity| {
            try wasm.appendSlice("\n\n  (data (i32.const ");
            const location = entity.get(components.Location).value;
            const string = try std.fmt.allocPrint(allocator, "{}", .{location});
            try wasm.appendSlice(string);
            try wasm.appendSlice(") \"");
            switch (entity.get(components.AstKind)) {
                .string => {
                    for (literalOf(entity)) |c| {
                        switch (c) {
                            '\n' => try wasm.appendSlice("\\n"),
                            else => try wasm.append(c),
                        }
                    }
                },
                .array_literal => {
                    const values = entity.get(components.Values).slice();
                    const value_type = valueType(typeOf(entity));
                    if (eql(value_type, b.I32)) {
                        try printBytesAsHex(i32, wasm, allocator, values);
                    } else if (eql(value_type, b.F32)) {
                        try printBytesAsHex(f32, wasm, allocator, values);
                    } else {
                        panic("\n print bytes as hex unsupported type {s} \n", .{literalOf(value_type)});
                    }
                },
                else => |k| panic("\nwasm print data unsupported kind {}\n", .{k}),
            }
            try wasm.appendSlice("\")");
        }
        try wasm.appendSlice("\n\n  (memory 1)\n  (export \"memory\" (memory 0))");
    }
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
    try printDataSegment(&wasm, codebase);
    try wasm.append(')');
    return wasm.mutSlice();
}
