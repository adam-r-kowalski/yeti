const std = @import("std");
const Arena = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;
const eql = std.meta.eql;
const panic = std.debug.panic;
const assert = std.debug.assert;

const init_codebase = @import("init_codebase.zig");
const initCodebase = init_codebase.initCodebase;
const MockFileSystem = @import("file_system.zig").FileSystem;
const analyzeSemantics = @import("semantic_analyzer.zig").analyzeSemantics;
const ecs = @import("ecs.zig");
const Entity = ecs.Entity;
const ECS = ecs.ECS;
const components = @import("components.zig");
const query = @import("query.zig");
const literalOf = query.literalOf;
const typeOf = query.typeOf;
const parentType = query.parentType;
const valueType = query.valueType;
const List = @import("list.zig").List;
const Strings = @import("strings.zig").Strings;

const Context = struct {
    codebase: *ECS,
    wasm_instructions: *components.WasmInstructions,
    locals: *components.Locals,
    allocator: Allocator,
    builtins: components.Builtins,
    label: u64,
    data_segment: *components.DataSegment,
};

fn codegenNumber(context: *Context, entity: Entity) !void {
    const type_of = typeOf(entity);
    const b = context.builtins;
    for (&[_]Entity{ b.IntLiteral, b.FloatLiteral }) |builtin| {
        if (eql(type_of, builtin)) {
            return;
        }
    }
    const builtins = &[_]Entity{ b.I64, b.I32, b.I16, b.I8, b.U64, b.U32, b.U16, b.U8, b.F64, b.F32 };
    const kinds = &[_]components.WasmInstructionKind{ .i64_const, .i32_const, .i32_const, .i32_const, .i64_const, .i32_const, .i32_const, .i32_const, .f64_const, .f32_const };
    for (builtins) |builtin, i| {
        if (!eql(type_of, builtin)) continue;
        const wasm_instruction = try context.codebase.createEntity(.{
            kinds[i],
            components.Constant.init(entity),
        });
        _ = try context.wasm_instructions.append(wasm_instruction);
        return;
    }
    if (type_of.has(components.ParentType)) |parent_type| {
        assert(eql(parent_type.entity, b.Ptr));
        const wasm_instruction = try context.codebase.createEntity(.{
            components.WasmInstructionKind.i32_const,
            components.Constant.init(entity),
        });
        _ = try context.wasm_instructions.append(wasm_instruction);
        return;
    }
    panic("\ncodegen number unsupported type {s}\n", .{literalOf(type_of)});
}

fn codegenCall(context: *Context, entity: Entity) !void {
    for (entity.get(components.Arguments).slice()) |argument| {
        try codegenEntity(context, argument);
    }
    const wasm_instruction = try context.codebase.createEntity(.{
        components.WasmInstructionKind.call,
        entity.get(components.Callable),
    });
    _ = try context.wasm_instructions.append(wasm_instruction);
}

fn codegenDefine(context: *Context, entity: Entity) !void {
    const value = entity.get(components.Value).entity;
    const local = entity.get(components.Local).entity;
    if (!local.contains(components.Mutable)) {
        const type_of = typeOf(local);
        const b = context.builtins;
        for (&[_]Entity{ b.IntLiteral, b.FloatLiteral }) |builtin| {
            if (!eql(type_of, builtin)) continue;
            return;
        }
        const builtins = [_]Entity{ b.I64, b.I32, b.I16, b.I8, b.U64, b.U32, b.U16, b.U8, b.F64, b.F32 };
        const types = [_]type{ i64, i32, i16, i8, u64, u32, u16, u8, f64, f32 };
        inline for (&types) |T, i| {
            if (eql(builtins[i], type_of)) {
                if (try valueOf(T, value)) |_| {
                    return;
                }
            }
        }
    }
    try codegenEntity(context, value);
    const wasm_instruction = try context.codebase.createEntity(.{
        components.WasmInstructionKind.local_set,
        components.Local.init(local),
    });
    _ = try context.wasm_instructions.append(wasm_instruction);
    try context.locals.put(local);
}

fn codegenAssign(context: *Context, entity: Entity) !void {
    const value = entity.get(components.Value).entity;
    try codegenEntity(context, value);
    const wasm_instruction = try context.codebase.createEntity(.{
        components.WasmInstructionKind.local_set,
        entity.get(components.Local),
    });
    _ = try context.wasm_instructions.append(wasm_instruction);
    return;
}

fn codegenLocal(context: *Context, local: Entity) !void {
    if (!local.contains(components.Mutable)) {
        const type_of = typeOf(local);
        const b = context.builtins;
        for (&[_]Entity{ b.IntLiteral, b.FloatLiteral }) |builtin| {
            if (!eql(type_of, builtin)) continue;
            return;
        }
        const builtins = [_]Entity{ b.I64, b.I32, b.I16, b.I8, b.U64, b.U32, b.U16, b.U8, b.F64, b.F32 };
        const types = [_]type{ i64, i32, i16, i8, u64, u32, u16, u8, f64, f32 };
        const kinds = &[_]components.WasmInstructionKind{ .i64_const, .i32_const, .i32_const, .i32_const, .i64_const, .i32_const, .i32_const, .i32_const, .f64_const, .f32_const };
        if (local.has(components.Value)) |value_component| {
            const value = value_component.entity;
            inline for (&types) |T, i| {
                if (eql(builtins[i], type_of)) {
                    if (try valueOf(T, value)) |_| {
                        const wasm_instruction = try context.codebase.createEntity(.{
                            kinds[i],
                            components.Constant.init(value),
                        });
                        _ = try context.wasm_instructions.append(wasm_instruction);
                        return;
                    }
                }
            }
        }
    }
    const wasm_instruction = try context.codebase.createEntity(.{
        components.WasmInstructionKind.local_get,
        components.Local.init(local),
    });
    _ = try context.wasm_instructions.append(wasm_instruction);
}

fn valueOf(comptime T: type, entity: Entity) !?T {
    if (entity.has(T)) |value| {
        return value;
    }
    if (entity.has(components.Literal)) |literal| {
        const string = entity.ecs.get(Strings).get(literal.interned);
        const types = [_]type{ i64, i32, i16, i8, u64, u32, u16, u8 };
        inline for (&types) |E| {
            if (T == E) {
                const value = try std.fmt.parseInt(T, string, 10);
                _ = try entity.set(.{value});
                return value;
            }
        }
        const float_types = [_]type{ f64, f32 };
        inline for (&float_types) |E| {
            if (T == E) {
                const value = try std.fmt.parseFloat(T, string);
                _ = try entity.set(.{value});
                return value;
            }
        }
        panic("\nvalue of unsupported type {s}\n", .{@typeName(T)});
    }
    return null;
}

const ArithmeticBinaryOps = struct {
    i64_fn: fn (lhs: i64, rhs: i64) i64,
    i32_fn: fn (lhs: i32, rhs: i32) i32,
    i16_fn: fn (lhs: i16, rhs: i16) i16,
    i8_fn: fn (lhs: i8, rhs: i8) i8,
    u64_fn: fn (lhs: u64, rhs: u64) u64,
    u32_fn: fn (lhs: u32, rhs: u32) u32,
    u16_fn: fn (lhs: u16, rhs: u16) u16,
    u8_fn: fn (lhs: u8, rhs: u8) u8,
    f64_fn: fn (lhs: f64, rhs: f64) f64,
    f32_fn: fn (lhs: f32, rhs: f32) f32,
    kinds: [10]components.WasmInstructionKind,
    simd_kinds: ?[8]components.WasmInstructionKind = null,
    float_simd_kinds: ?[2]components.WasmInstructionKind = null,
    types: [10]type = .{ i64, i32, i16, i8, u64, u32, u16, u8, f64, f32 },
    argument_kinds: [10]components.WasmInstructionKind = .{
        .i64_const,
        .i32_const,
        .i32_const,
        .i32_const,
        .i64_const,
        .i32_const,
        .i32_const,
        .i32_const,
        .f64_const,
        .f32_const,
    },
    result_kinds: [10]components.WasmInstructionKind = .{
        .i64_const,
        .i32_const,
        .i32_const,
        .i32_const,
        .i64_const,
        .i32_const,
        .i32_const,
        .i32_const,
        .f64_const,
        .f32_const,
    },

    const Self = @This();

    fn call(comptime self: Self, comptime T: type, lhs: T, rhs: T) T {
        return switch (T) {
            i64 => self.i64_fn(lhs, rhs),
            i32 => self.i32_fn(lhs, rhs),
            i16 => self.i16_fn(lhs, rhs),
            i8 => self.i8_fn(lhs, rhs),
            u64 => self.u64_fn(lhs, rhs),
            u32 => self.u32_fn(lhs, rhs),
            u16 => self.u16_fn(lhs, rhs),
            u8 => self.u8_fn(lhs, rhs),
            f64 => self.f64_fn(lhs, rhs),
            f32 => self.f32_fn(lhs, rhs),
            else => panic("\nunsupported type {s}\n", .{@typeName(T)}),
        };
    }
};

const IntBinaryOps = struct {
    i64_fn: fn (lhs: i64, rhs: i64) i64,
    i32_fn: fn (lhs: i32, rhs: i32) i32,
    i16_fn: fn (lhs: i16, rhs: i16) i16,
    i8_fn: fn (lhs: i8, rhs: i8) i8,
    u64_fn: fn (lhs: u64, rhs: u64) u64,
    u32_fn: fn (lhs: u32, rhs: u32) u32,
    u16_fn: fn (lhs: u16, rhs: u16) u16,
    u8_fn: fn (lhs: u8, rhs: u8) u8,
    kinds: [8]components.WasmInstructionKind,
    types: [8]type = .{ i64, i32, i16, i8, u64, u32, u16, u8 },
    argument_kinds: [8]components.WasmInstructionKind = .{
        .i64_const,
        .i32_const,
        .i32_const,
        .i32_const,
        .i64_const,
        .i32_const,
        .i32_const,
        .i32_const,
    },
    result_kinds: [8]components.WasmInstructionKind = .{
        .i64_const,
        .i32_const,
        .i32_const,
        .i32_const,
        .i64_const,
        .i32_const,
        .i32_const,
        .i32_const,
    },

    const Self = @This();

    fn call(comptime self: Self, comptime T: type, lhs: T, rhs: T) T {
        return switch (T) {
            i64 => self.i64_fn(lhs, rhs),
            i32 => self.i32_fn(lhs, rhs),
            i16 => self.i16_fn(lhs, rhs),
            i8 => self.i8_fn(lhs, rhs),
            u64 => self.u64_fn(lhs, rhs),
            u32 => self.u32_fn(lhs, rhs),
            u16 => self.u16_fn(lhs, rhs),
            u8 => self.u8_fn(lhs, rhs),
            else => panic("\nunsupported type {s}\n", .{@typeName(T)}),
        };
    }
};

const ComparisonBinaryOps = struct {
    i64_fn: fn (lhs: i64, rhs: i64) i32,
    i32_fn: fn (lhs: i32, rhs: i32) i32,
    i16_fn: fn (lhs: i16, rhs: i16) i32,
    i8_fn: fn (lhs: i8, rhs: i8) i32,
    u64_fn: fn (lhs: u64, rhs: u64) i32,
    u32_fn: fn (lhs: u32, rhs: u32) i32,
    u16_fn: fn (lhs: u16, rhs: u16) i32,
    u8_fn: fn (lhs: u8, rhs: u8) i32,
    f64_fn: fn (lhs: f64, rhs: f64) i32,
    f32_fn: fn (lhs: f32, rhs: f32) i32,
    kinds: [10]components.WasmInstructionKind,
    types: [10]type = .{ i64, i32, i16, i8, u64, u32, u16, u8, f64, f32 },
    argument_kinds: [10]components.WasmInstructionKind = .{
        .i64_const,
        .i32_const,
        .i32_const,
        .i32_const,
        .i64_const,
        .i32_const,
        .i32_const,
        .i32_const,
        .f64_const,
        .f32_const,
    },
    result_kinds: [10]components.WasmInstructionKind = .{
        .i32_const,
        .i32_const,
        .i32_const,
        .i32_const,
        .i32_const,
        .i32_const,
        .i32_const,
        .i32_const,
        .i32_const,
        .i32_const,
    },

    const Self = @This();

    fn call(comptime self: Self, comptime T: type, lhs: T, rhs: T) i32 {
        return switch (T) {
            i64 => self.i64_fn(lhs, rhs),
            i32 => self.i32_fn(lhs, rhs),
            i16 => self.i16_fn(lhs, rhs),
            i8 => self.i8_fn(lhs, rhs),
            u64 => self.u64_fn(lhs, rhs),
            u32 => self.u32_fn(lhs, rhs),
            u16 => self.u16_fn(lhs, rhs),
            u8 => self.u8_fn(lhs, rhs),
            f64 => self.f64_fn(lhs, rhs),
            f32 => self.f32_fn(lhs, rhs),
            else => panic("\nunsupported type {s}\n", .{@typeName(T)}),
        };
    }
};

fn addFn(comptime T: type) fn (T, T) T {
    return struct {
        fn f(lhs: T, rhs: T) T {
            return lhs + rhs;
        }
    }.f;
}

const addOps = ArithmeticBinaryOps{
    .i64_fn = addFn(i64),
    .i32_fn = addFn(i32),
    .i16_fn = addFn(i16),
    .i8_fn = addFn(i8),
    .u64_fn = addFn(u64),
    .u32_fn = addFn(u32),
    .u16_fn = addFn(u16),
    .u8_fn = addFn(u8),
    .f64_fn = addFn(f64),
    .f32_fn = addFn(f32),
    .kinds = [_]components.WasmInstructionKind{
        .i64_add,
        .i32_add,
        .i32_add_mod_16,
        .i32_add_mod_8,
        .i64_add,
        .i32_add,
        .i32_add_mod_16,
        .i32_add_mod_8,
        .f64_add,
        .f32_add,
    },
    .simd_kinds = [_]components.WasmInstructionKind{
        .i64x2_add,
        .i32x4_add,
        .i16x8_add,
        .i8x16_add,
        .i64x2_add,
        .i32x4_add,
        .i16x8_add,
        .i8x16_add,
    },
    .float_simd_kinds = [_]components.WasmInstructionKind{
        .f64x2_add,
        .f32x4_add,
    },
};

fn subtractFn(comptime T: type) fn (T, T) T {
    return struct {
        fn f(lhs: T, rhs: T) T {
            return lhs - rhs;
        }
    }.f;
}

const subtractOps = ArithmeticBinaryOps{
    .i64_fn = subtractFn(i64),
    .i32_fn = subtractFn(i32),
    .i16_fn = subtractFn(i16),
    .i8_fn = subtractFn(i8),
    .u64_fn = subtractFn(u64),
    .u32_fn = subtractFn(u32),
    .u16_fn = subtractFn(u16),
    .u8_fn = subtractFn(u8),
    .f64_fn = subtractFn(f64),
    .f32_fn = subtractFn(f32),
    .kinds = [_]components.WasmInstructionKind{
        .i64_sub,
        .i32_sub,
        .i32_sub_mod_16,
        .i32_sub_mod_8,
        .i64_sub,
        .i32_sub,
        .i32_sub_mod_16,
        .i32_sub_mod_8,
        .f64_sub,
        .f32_sub,
    },
    .simd_kinds = [_]components.WasmInstructionKind{
        .i64x2_sub,
        .i32x4_sub,
        .i16x8_sub,
        .i8x16_sub,
        .i64x2_sub,
        .i32x4_sub,
        .i16x8_sub,
        .i8x16_sub,
    },
    .float_simd_kinds = [_]components.WasmInstructionKind{
        .f64x2_sub,
        .f32x4_sub,
    },
};

fn multiplyFn(comptime T: type) fn (T, T) T {
    return struct {
        fn f(lhs: T, rhs: T) T {
            return lhs * rhs;
        }
    }.f;
}

const multiplyOps = ArithmeticBinaryOps{
    .i64_fn = multiplyFn(i64),
    .i32_fn = multiplyFn(i32),
    .i16_fn = multiplyFn(i16),
    .i8_fn = multiplyFn(i8),
    .u64_fn = multiplyFn(u64),
    .u32_fn = multiplyFn(u32),
    .u16_fn = multiplyFn(u16),
    .u8_fn = multiplyFn(u8),
    .f64_fn = multiplyFn(f64),
    .f32_fn = multiplyFn(f32),
    .kinds = [_]components.WasmInstructionKind{
        .i64_mul,
        .i32_mul,
        .i32_mul_mod_16,
        .i32_mul_mod_8,
        .i64_mul,
        .i32_mul,
        .i32_mul_mod_16,
        .i32_mul_mod_8,
        .f64_mul,
        .f32_mul,
    },
    .simd_kinds = [_]components.WasmInstructionKind{
        .i64x2_mul,
        .i32x4_mul,
        .i16x8_mul,
        .i8x16_mul,
        .i64x2_mul,
        .i32x4_mul,
        .i16x8_mul,
        .i8x16_mul,
    },
    .float_simd_kinds = [_]components.WasmInstructionKind{
        .f64x2_mul,
        .f32x4_mul,
    },
};

fn divideFn(comptime T: type) fn (T, T) T {
    return struct {
        fn f(lhs: T, rhs: T) T {
            return switch (T) {
                i64, i32, i16, i8, u64, u32, u16, u8 => @divFloor(lhs, rhs),
                else => lhs / rhs,
            };
        }
    }.f;
}

const divideOps = ArithmeticBinaryOps{
    .i64_fn = divideFn(i64),
    .i32_fn = divideFn(i32),
    .i16_fn = divideFn(i16),
    .i8_fn = divideFn(i8),
    .u64_fn = divideFn(u64),
    .u32_fn = divideFn(u32),
    .u16_fn = divideFn(u16),
    .u8_fn = divideFn(u8),
    .f64_fn = divideFn(f64),
    .f32_fn = divideFn(f32),
    .kinds = [_]components.WasmInstructionKind{
        .i64_div,
        .i32_div,
        .i32_div,
        .i32_div,
        .u64_div,
        .u32_div,
        .u32_div,
        .u32_div,
        .f64_div,
        .f32_div,
    },
    .float_simd_kinds = [_]components.WasmInstructionKind{
        .f64x2_div,
        .f32x4_div,
    },
};

fn remainderFn(comptime T: type) fn (T, T) T {
    return struct {
        fn f(lhs: T, rhs: T) T {
            return @rem(lhs, rhs);
        }
    }.f;
}

const remainderOps = IntBinaryOps{
    .i64_fn = remainderFn(i64),
    .i32_fn = remainderFn(i32),
    .i16_fn = remainderFn(i16),
    .i8_fn = remainderFn(i8),
    .u64_fn = remainderFn(u64),
    .u32_fn = remainderFn(u32),
    .u16_fn = remainderFn(u16),
    .u8_fn = remainderFn(u8),
    .kinds = [_]components.WasmInstructionKind{
        .i64_rem,
        .i32_rem,
        .i32_rem,
        .i32_rem,
        .u64_rem,
        .u32_rem,
        .u32_rem,
        .u32_rem,
    },
};

fn bitAndFn(comptime T: type) fn (T, T) T {
    return struct {
        fn f(lhs: T, rhs: T) T {
            return lhs & rhs;
        }
    }.f;
}

const bitAndOps = IntBinaryOps{
    .i64_fn = bitAndFn(i64),
    .i32_fn = bitAndFn(i32),
    .i16_fn = bitAndFn(i16),
    .i8_fn = bitAndFn(i8),
    .u64_fn = bitAndFn(u64),
    .u32_fn = bitAndFn(u32),
    .u16_fn = bitAndFn(u16),
    .u8_fn = bitAndFn(u8),
    .kinds = [_]components.WasmInstructionKind{
        .i64_and,
        .i32_and,
        .i32_and,
        .i32_and,
        .i64_and,
        .i32_and,
        .i32_and,
        .i32_and,
    },
};

fn bitOrFn(comptime T: type) fn (T, T) T {
    return struct {
        fn f(lhs: T, rhs: T) T {
            return lhs | rhs;
        }
    }.f;
}

const bitOrOps = IntBinaryOps{
    .i64_fn = bitOrFn(i64),
    .i32_fn = bitOrFn(i32),
    .i16_fn = bitOrFn(i16),
    .i8_fn = bitOrFn(i8),
    .u64_fn = bitOrFn(u64),
    .u32_fn = bitOrFn(u32),
    .u16_fn = bitOrFn(u16),
    .u8_fn = bitOrFn(u8),
    .kinds = [_]components.WasmInstructionKind{
        .i64_or,
        .i32_or,
        .i32_or,
        .i32_or,
        .i64_or,
        .i32_or,
        .i32_or,
        .i32_or,
    },
};

fn bitXorFn(comptime T: type) fn (T, T) T {
    return struct {
        fn f(lhs: T, rhs: T) T {
            return lhs ^ rhs;
        }
    }.f;
}

const bitXorOps = IntBinaryOps{
    .i64_fn = bitXorFn(i64),
    .i32_fn = bitXorFn(i32),
    .i16_fn = bitXorFn(i16),
    .i8_fn = bitXorFn(i8),
    .u64_fn = bitXorFn(u64),
    .u32_fn = bitXorFn(u32),
    .u16_fn = bitXorFn(u16),
    .u8_fn = bitXorFn(u8),
    .kinds = [_]components.WasmInstructionKind{
        .i64_xor,
        .i32_xor,
        .i32_xor,
        .i32_xor,
        .i64_xor,
        .i32_xor,
        .i32_xor,
        .i32_xor,
    },
};

fn leftShiftFn(comptime T: type) fn (T, T) T {
    return struct {
        fn f(lhs: T, rhs: T) T {
            return lhs << @intCast(std.math.Log2Int(T), rhs);
        }
    }.f;
}

const leftShiftOps = IntBinaryOps{
    .i64_fn = leftShiftFn(i64),
    .i32_fn = leftShiftFn(i32),
    .i16_fn = leftShiftFn(i16),
    .i8_fn = leftShiftFn(i8),
    .u64_fn = leftShiftFn(u64),
    .u32_fn = leftShiftFn(u32),
    .u16_fn = leftShiftFn(u16),
    .u8_fn = leftShiftFn(u8),
    .kinds = [_]components.WasmInstructionKind{
        .i64_shl,
        .i32_shl,
        .i32_shl,
        .i32_shl,
        .u64_shl,
        .u32_shl,
        .u32_shl,
        .u32_shl,
    },
};

fn rightShiftFn(comptime T: type) fn (T, T) T {
    return struct {
        fn f(lhs: T, rhs: T) T {
            return lhs >> @intCast(std.math.Log2Int(T), rhs);
        }
    }.f;
}

const rightShiftOps = IntBinaryOps{
    .i64_fn = rightShiftFn(i64),
    .i32_fn = rightShiftFn(i32),
    .i16_fn = rightShiftFn(i16),
    .i8_fn = rightShiftFn(i8),
    .u64_fn = rightShiftFn(u64),
    .u32_fn = rightShiftFn(u32),
    .u16_fn = rightShiftFn(u16),
    .u8_fn = rightShiftFn(u8),
    .kinds = [_]components.WasmInstructionKind{
        .i64_shr,
        .i32_shr,
        .i32_shr,
        .i32_shr,
        .u64_shr,
        .u32_shr,
        .u32_shr,
        .u32_shr,
    },
};

fn equalFn(comptime T: type) fn (T, T) i32 {
    return struct {
        fn f(lhs: T, rhs: T) i32 {
            return if (lhs == rhs) 1 else 0;
        }
    }.f;
}

const equalOps = ComparisonBinaryOps{
    .i64_fn = equalFn(i64),
    .i32_fn = equalFn(i32),
    .i16_fn = equalFn(i16),
    .i8_fn = equalFn(i8),
    .u64_fn = equalFn(u64),
    .u32_fn = equalFn(u32),
    .u16_fn = equalFn(u16),
    .u8_fn = equalFn(u8),
    .f64_fn = equalFn(f64),
    .f32_fn = equalFn(f32),
    .kinds = [_]components.WasmInstructionKind{
        .i64_eq,
        .i32_eq,
        .i32_eq,
        .i32_eq,
        .i64_eq,
        .i32_eq,
        .i32_eq,
        .i32_eq,
        .f64_eq,
        .f32_eq,
    },
};

fn notEqualFn(comptime T: type) fn (T, T) i32 {
    return struct {
        fn f(lhs: T, rhs: T) i32 {
            return if (lhs != rhs) 1 else 0;
        }
    }.f;
}

const notEqualOps = ComparisonBinaryOps{
    .i64_fn = notEqualFn(i64),
    .i32_fn = notEqualFn(i32),
    .i16_fn = notEqualFn(i16),
    .i8_fn = notEqualFn(i8),
    .u64_fn = notEqualFn(u64),
    .u32_fn = notEqualFn(u32),
    .u16_fn = notEqualFn(u16),
    .u8_fn = notEqualFn(u8),
    .f64_fn = notEqualFn(f64),
    .f32_fn = notEqualFn(f32),
    .kinds = [_]components.WasmInstructionKind{
        .i64_ne,
        .i32_ne,
        .i32_ne,
        .i32_ne,
        .i64_ne,
        .i32_ne,
        .i32_ne,
        .i32_ne,
        .f64_ne,
        .f32_ne,
    },
};

fn lessThanFn(comptime T: type) fn (T, T) i32 {
    return struct {
        fn f(lhs: T, rhs: T) i32 {
            return if (lhs < rhs) 1 else 0;
        }
    }.f;
}

const lessThanOps = ComparisonBinaryOps{
    .i64_fn = lessThanFn(i64),
    .i32_fn = lessThanFn(i32),
    .i16_fn = lessThanFn(i16),
    .i8_fn = lessThanFn(i8),
    .u64_fn = lessThanFn(u64),
    .u32_fn = lessThanFn(u32),
    .u16_fn = lessThanFn(u16),
    .u8_fn = lessThanFn(u8),
    .f64_fn = lessThanFn(f64),
    .f32_fn = lessThanFn(f32),
    .kinds = [_]components.WasmInstructionKind{
        .i64_lt,
        .i32_lt,
        .i32_lt,
        .i32_lt,
        .i64_lt,
        .i32_lt,
        .i32_lt,
        .i32_lt,
        .f64_lt,
        .f32_lt,
    },
};

fn lessEqualFn(comptime T: type) fn (T, T) i32 {
    return struct {
        fn f(lhs: T, rhs: T) i32 {
            return if (lhs <= rhs) 1 else 0;
        }
    }.f;
}

const lessEqualOps = ComparisonBinaryOps{
    .i64_fn = lessEqualFn(i64),
    .i32_fn = lessEqualFn(i32),
    .i16_fn = lessEqualFn(i16),
    .i8_fn = lessEqualFn(i8),
    .u64_fn = lessEqualFn(u64),
    .u32_fn = lessEqualFn(u32),
    .u16_fn = lessEqualFn(u16),
    .u8_fn = lessEqualFn(u8),
    .f64_fn = lessEqualFn(f64),
    .f32_fn = lessEqualFn(f32),
    .kinds = [_]components.WasmInstructionKind{
        .i64_le,
        .i32_le,
        .i32_le,
        .i32_le,
        .i64_le,
        .i32_le,
        .i32_le,
        .i32_le,
        .f64_le,
        .f32_le,
    },
};

fn greaterThanFn(comptime T: type) fn (T, T) i32 {
    return struct {
        fn f(lhs: T, rhs: T) i32 {
            return if (lhs > rhs) 1 else 0;
        }
    }.f;
}

const greaterThanOps = ComparisonBinaryOps{
    .i64_fn = greaterThanFn(i64),
    .i32_fn = greaterThanFn(i32),
    .i16_fn = greaterThanFn(i16),
    .i8_fn = greaterThanFn(i8),
    .u64_fn = greaterThanFn(u64),
    .u32_fn = greaterThanFn(u32),
    .u16_fn = greaterThanFn(u16),
    .u8_fn = greaterThanFn(u8),
    .f64_fn = greaterThanFn(f64),
    .f32_fn = greaterThanFn(f32),
    .kinds = [_]components.WasmInstructionKind{
        .i64_gt,
        .i32_gt,
        .i32_gt,
        .i32_gt,
        .i64_gt,
        .i32_gt,
        .i32_gt,
        .i32_gt,
        .f64_gt,
        .f32_gt,
    },
};

fn greaterEqualFn(comptime T: type) fn (T, T) i32 {
    return struct {
        fn f(lhs: T, rhs: T) i32 {
            return if (lhs >= rhs) 1 else 0;
        }
    }.f;
}

const greaterEqualOps = ComparisonBinaryOps{
    .i64_fn = greaterEqualFn(i64),
    .i32_fn = greaterEqualFn(i32),
    .i16_fn = greaterEqualFn(i16),
    .i8_fn = greaterEqualFn(i8),
    .u64_fn = greaterEqualFn(u64),
    .u32_fn = greaterEqualFn(u32),
    .u16_fn = greaterEqualFn(u16),
    .u8_fn = greaterEqualFn(u8),
    .f64_fn = greaterEqualFn(f64),
    .f32_fn = greaterEqualFn(f32),
    .kinds = [_]components.WasmInstructionKind{
        .i64_ge,
        .i32_ge,
        .i32_ge,
        .i32_ge,
        .i64_ge,
        .i32_ge,
        .i32_ge,
        .i32_ge,
        .f64_ge,
        .f32_ge,
    },
};

fn codegenBinaryOp(context: *Context, entity: Entity, comptime ops: anytype) !void {
    const arguments = entity.get(components.Arguments).slice();
    try codegenEntity(context, arguments[0]);
    try codegenEntity(context, arguments[1]);
    const type_of = typeOf(arguments[0]);
    const b = context.builtins;
    const builtins = [_]Entity{ b.I64, b.I32, b.I16, b.I8, b.U64, b.U32, b.U16, b.U8, b.F64, b.F32 };
    inline for (&ops.types) |T, i| {
        if (eql(type_of, builtins[i])) {
            const instructions = context.wasm_instructions.mutSlice();
            const rhs = instructions[instructions.len - 1];
            const lhs = instructions[instructions.len - 2];
            const lhs_kind = lhs.get(components.WasmInstructionKind);
            const rhs_kind = rhs.get(components.WasmInstructionKind);
            const kind = ops.argument_kinds[i];
            if (lhs_kind == kind and rhs_kind == kind) {
                const lhs_value = (try valueOf(T, lhs.get(components.Constant).entity)).?;
                const rhs_value = (try valueOf(T, rhs.get(components.Constant).entity)).?;
                const result_value = ops.call(T, lhs_value, rhs_value);
                const result_literal = try std.fmt.allocPrint(context.allocator, "{}", .{result_value});
                const interned = try context.codebase.getPtr(Strings).intern(result_literal);
                const result = try context.codebase.createEntity(.{
                    entity.get(components.Type),
                    components.Literal.init(interned),
                    result_value,
                });
                instructions[instructions.len - 2] = try context.codebase.createEntity(.{
                    ops.result_kinds[i],
                    components.Constant.init(result),
                });
                context.wasm_instructions.shrink(1);
                return;
            }
            const instruction = try context.codebase.createEntity(.{ops.kinds[i]});
            try context.wasm_instructions.append(instruction);
            return;
        }
    }
    const vectors = [_]Entity{ b.I64X2, b.I32X4, b.I16X8, b.I8X16, b.U64X2, b.U32X4, b.U16X8, b.U8X16 };
    for (vectors) |vector, i| {
        if (eql(type_of, vector)) {
            if (@hasField(@TypeOf(ops), "simd_kinds")) {
                if (ops.simd_kinds) |simd_kinds| {
                    const instruction = try context.codebase.createEntity(.{simd_kinds[i]});
                    try context.wasm_instructions.append(instruction);
                    return;
                }
            }
        }
    }
    const float_vectors = [_]Entity{ b.F64X2, b.F32X4 };
    for (float_vectors) |vector, i| {
        if (eql(type_of, vector)) {
            if (@hasField(@TypeOf(ops), "float_simd_kinds")) {
                if (ops.float_simd_kinds) |simd_kinds| {
                    const instruction = try context.codebase.createEntity(.{simd_kinds[i]});
                    try context.wasm_instructions.append(instruction);
                    return;
                }
            }
        }
    }
    assert(eql(parentType(type_of), b.Ptr));
    const instructions = context.wasm_instructions.mutSlice();
    const rhs = instructions[instructions.len - 1];
    const lhs = instructions[instructions.len - 2];
    const lhs_kind = lhs.get(components.WasmInstructionKind);
    const rhs_kind = rhs.get(components.WasmInstructionKind);
    const i32_index = 1;
    const kind = ops.argument_kinds[i32_index];
    if (lhs_kind == kind and rhs_kind == kind) {
        const lhs_value = (try valueOf(i32, lhs.get(components.Constant).entity)).?;
        const rhs_value = (try valueOf(i32, rhs.get(components.Constant).entity)).?;
        const result_value = ops.call(i32, lhs_value, rhs_value);
        const result_literal = try std.fmt.allocPrint(context.allocator, "{}", .{result_value});
        const interned = try context.codebase.getPtr(Strings).intern(result_literal);
        const result = try context.codebase.createEntity(.{
            entity.get(components.Type),
            components.Literal.init(interned),
            result_value,
        });
        instructions[instructions.len - 2] = try context.codebase.createEntity(.{
            ops.result_kinds[i32_index],
            components.Constant.init(result),
        });
        context.wasm_instructions.shrink(1);
        return;
    }
    const instruction = try context.codebase.createEntity(.{ops.kinds[i32_index]});
    try context.wasm_instructions.append(instruction);
}

fn codegenPtrI32BinaryOp(context: *Context, entity: Entity, kind: components.WasmInstructionKind) !void {
    const arguments = entity.get(components.Arguments).slice();
    try codegenEntity(context, arguments[0]);
    try codegenEntity(context, arguments[1]);
    const instructions = context.wasm_instructions.mutSlice();
    const rhs = instructions[instructions.len - 1];
    const rhs_kind = rhs.get(components.WasmInstructionKind);
    const bytes = valueType(typeOf(arguments[0])).get(components.Size).bytes;
    if (rhs_kind == .i32_const) {
        const rhs_value = (try valueOf(i32, rhs.get(components.Constant).entity)).?;
        const result_value = rhs_value * bytes;
        const result_literal = try std.fmt.allocPrint(context.allocator, "{}", .{result_value});
        const interned = try context.codebase.getPtr(Strings).intern(result_literal);
        const result = try context.codebase.createEntity(.{
            entity.get(components.Type),
            components.Literal.init(interned),
            result_value,
        });
        instructions[instructions.len - 1] = try context.codebase.createEntity(.{
            components.WasmInstructionKind.i32_const,
            components.Constant.init(result),
        });
        const instruction = try context.codebase.createEntity(.{kind});
        try context.wasm_instructions.append(instruction);
        return;
    }
    try codegenConstant(i32, context, bytes);
    const multiply = try context.codebase.createEntity(.{
        components.WasmInstructionKind.i32_mul,
    });
    const op = try context.codebase.createEntity(.{kind});
    try context.wasm_instructions.append(multiply);
    try context.wasm_instructions.append(op);
}

fn codegenSubPtrPtr(context: *Context, entity: Entity) !void {
    const arguments = entity.get(components.Arguments).slice();
    try codegenEntity(context, arguments[0]);
    try codegenEntity(context, arguments[1]);
    const bytes = valueType(typeOf(arguments[0])).get(components.Size).bytes;
    const literal = try std.fmt.allocPrint(context.allocator, "{}", .{bytes});
    const interned = try context.codebase.getPtr(Strings).intern(literal);
    const subtract = try context.codebase.createEntity(.{
        components.WasmInstructionKind.i32_sub,
    });
    const result = try context.codebase.createEntity(.{
        components.Type.init(context.builtins.I32),
        components.Literal.init(interned),
        bytes,
    });
    const constant = try context.codebase.createEntity(.{
        components.WasmInstructionKind.i32_const,
        components.Constant.init(result),
    });
    const divide = try context.codebase.createEntity(.{
        components.WasmInstructionKind.i32_div,
    });
    try context.wasm_instructions.append(subtract);
    try context.wasm_instructions.append(constant);
    try context.wasm_instructions.append(divide);
}

fn codegenStore(context: *Context, entity: Entity) !void {
    try context.codebase.set(.{components.UsesMemory{ .value = true }});
    const arguments = entity.get(components.Arguments).slice();
    const pointer = arguments[0];
    try codegenEntity(context, pointer);
    try codegenEntity(context, arguments[1]);
    const b = context.builtins;
    const builtins = [_]Entity{ b.I64, b.I32, b.U64, b.U32, b.F64, b.F32 };
    const instructions = [_]components.WasmInstructionKind{ .i64_store, .i32_store, .i64_store, .i32_store, .f64_store, .f32_store };
    const value_type = valueType(typeOf(pointer));
    for (builtins) |builtin, i| {
        if (eql(value_type, builtin)) {
            const instruction = try context.codebase.createEntity(.{instructions[i]});
            try context.wasm_instructions.append(instruction);
            return;
        }
    }
    if (value_type.has(components.ParentType)) |value_type_parent_type| {
        assert(eql(value_type_parent_type.entity, b.Ptr));
        const instruction = try context.codebase.createEntity(.{components.WasmInstructionKind.i32_store});
        try context.wasm_instructions.append(instruction);
        return;
    }
    panic("\ncodegen store unspported type {s}\n", .{literalOf(value_type)});
}

fn codegenV128Store(context: *Context, entity: Entity) !void {
    try context.codebase.set(.{components.UsesMemory{ .value = true }});
    const arguments = entity.get(components.Arguments).slice();
    try codegenEntity(context, arguments[0]);
    try codegenEntity(context, arguments[1]);
    const instruction = try context.codebase.createEntity(.{
        components.WasmInstructionKind.v128_store,
    });
    try context.wasm_instructions.append(instruction);
}

fn codegenLoad(context: *Context, entity: Entity) !void {
    try context.codebase.set(.{components.UsesMemory{ .value = true }});
    const arguments = entity.get(components.Arguments).slice();
    const pointer = arguments[0];
    try codegenEntity(context, pointer);
    const b = context.builtins;
    const builtins = [_]Entity{ b.I64, b.I32, b.U64, b.U32, b.U8, b.F64, b.F32 };
    const instructions = [_]components.WasmInstructionKind{ .i64_load, .i32_load, .i64_load, .i32_load, .i32_load8_u, .f64_load, .f32_load };
    const value_type = valueType(typeOf(pointer));
    for (builtins) |builtin, i| {
        if (eql(value_type, builtin)) {
            const instruction = try context.codebase.createEntity(.{instructions[i]});
            try context.wasm_instructions.append(instruction);
            return;
        }
    }
    panic("\ncodegen load unspported type {s}\n", .{literalOf(value_type)});
}

fn codegenV128Load(context: *Context, entity: Entity) !void {
    try context.codebase.set(.{components.UsesMemory{ .value = true }});
    const arguments = entity.get(components.Arguments).slice();
    const pointer = arguments[0];
    try codegenEntity(context, pointer);
    const instruction = try context.codebase.createEntity(.{
        components.WasmInstructionKind.v128_load,
    });
    try context.wasm_instructions.append(instruction);
}

fn codegenIntrinsic(context: *Context, entity: Entity) !void {
    const intrinsic = entity.get(components.Intrinsic);
    switch (intrinsic) {
        .add => try codegenBinaryOp(context, entity, addOps),
        .subtract => try codegenBinaryOp(context, entity, subtractOps),
        .multiply => try codegenBinaryOp(context, entity, multiplyOps),
        .divide => try codegenBinaryOp(context, entity, divideOps),
        .remainder => try codegenBinaryOp(context, entity, remainderOps),
        .bit_and => try codegenBinaryOp(context, entity, bitAndOps),
        .bit_or => try codegenBinaryOp(context, entity, bitOrOps),
        .bit_xor => try codegenBinaryOp(context, entity, bitXorOps),
        .left_shift => try codegenBinaryOp(context, entity, leftShiftOps),
        .right_shift => try codegenBinaryOp(context, entity, rightShiftOps),
        .equal => try codegenBinaryOp(context, entity, equalOps),
        .not_equal => try codegenBinaryOp(context, entity, notEqualOps),
        .less_than => try codegenBinaryOp(context, entity, lessThanOps),
        .less_equal => try codegenBinaryOp(context, entity, lessEqualOps),
        .greater_than => try codegenBinaryOp(context, entity, greaterThanOps),
        .greater_equal => try codegenBinaryOp(context, entity, greaterEqualOps),
        .store => try codegenStore(context, entity),
        .load => try codegenLoad(context, entity),
        .add_ptr_i32 => try codegenPtrI32BinaryOp(context, entity, .i32_add),
        .subtract_ptr_i32 => try codegenPtrI32BinaryOp(context, entity, .i32_sub),
        .subtract_ptr_ptr => try codegenSubPtrPtr(context, entity),
        .v128_load => try codegenV128Load(context, entity),
        .v128_store => try codegenV128Store(context, entity),
    }
}

fn codegenIf(context: *Context, entity: Entity) !void {
    const conditional = entity.get(components.Conditional).entity;
    try codegenEntity(context, conditional);
    const conditional_instruction = context.wasm_instructions.last();
    const kind = conditional_instruction.get(components.WasmInstructionKind);
    if (kind == .i32_const) {
        context.wasm_instructions.shrink(1);
        if ((try valueOf(i32, conditional_instruction.get(components.Constant).entity)).? != 0) {
            for (entity.get(components.Then).slice()) |expression| {
                try codegenEntity(context, expression);
            }
            return;
        }
        for (entity.get(components.Else).slice()) |expression| {
            try codegenEntity(context, expression);
        }
        return;
    }
    try context.wasm_instructions.append(try context.codebase.createEntity(.{
        components.WasmInstructionKind.if_,
        entity.get(components.Type),
    }));
    for (entity.get(components.Then).slice()) |expression| {
        try codegenEntity(context, expression);
    }
    try context.wasm_instructions.append(try context.codebase.createEntity(.{
        components.WasmInstructionKind.else_,
    }));
    for (entity.get(components.Else).slice()) |expression| {
        try codegenEntity(context, expression);
    }
    try context.wasm_instructions.append(try context.codebase.createEntity(.{
        components.WasmInstructionKind.end,
    }));
}

fn codegenWhile(context: *Context, entity: Entity) !void {
    const block_label = components.Label{ .value = context.label };
    const loop_label = components.Label{ .value = context.label + 1 };
    context.label += 2;
    try context.wasm_instructions.append(try context.codebase.createEntity(.{
        components.WasmInstructionKind.block,
        block_label,
    }));
    try context.wasm_instructions.append(try context.codebase.createEntity(.{
        components.WasmInstructionKind.loop,
        loop_label,
    }));
    const conditional = entity.get(components.Conditional).entity;
    try codegenEntity(context, conditional);
    try context.wasm_instructions.append(try context.codebase.createEntity(.{
        components.WasmInstructionKind.i32_eqz,
    }));
    try context.wasm_instructions.append(try context.codebase.createEntity(.{
        components.WasmInstructionKind.br_if,
        block_label,
    }));
    for (entity.get(components.Body).slice()) |expression| {
        try codegenEntity(context, expression);
    }
    try context.wasm_instructions.append(try context.codebase.createEntity(.{
        components.WasmInstructionKind.br,
        loop_label,
    }));
    try context.wasm_instructions.append(try context.codebase.createEntity(.{
        components.WasmInstructionKind.end,
        loop_label,
    }));
    try context.wasm_instructions.append(try context.codebase.createEntity(.{
        components.WasmInstructionKind.end,
        block_label,
    }));
    context.label -= 2;
}

fn codegenFor(context: *Context, entity: Entity) !void {
    const loop_variable = entity.get(components.LoopVariable).entity;
    const local = loop_variable.get(components.Local).entity;
    try context.locals.put(local);
    const iterator = entity.get(components.Iterator).entity;
    const b = context.builtins;
    const builtins = [_]Entity{ b.I64, b.I32, b.I16, b.I8, b.U64, b.U32, b.U16, b.U8, b.F64, b.F32 };
    const kinds = &[_]components.WasmInstructionKind{
        .i64_const,
        .i32_const,
        .i32_const,
        .i32_const,
        .i64_const,
        .i32_const,
        .i32_const,
        .i32_const,
        .f64_const,
        .f32_const,
    };
    const type_of = typeOf(local);
    const i: u64 = blk: {
        for (builtins) |builtin, i| {
            if (!eql(builtin, type_of)) continue;
            break :blk i;
        }
        panic("\nfor range unsupported type {s}\n", .{literalOf(type_of)});
    };
    {
        const first = try context.codebase.createEntity(.{
            components.Type.init(builtins[i]),
            iterator.get(components.First).entity.get(components.Literal),
        });
        const wasm_instruction = try context.codebase.createEntity(.{
            kinds[i],
            components.Constant.init(first),
        });
        _ = try context.wasm_instructions.append(wasm_instruction);
    }
    {
        const wasm_instruction = try context.codebase.createEntity(.{
            components.WasmInstructionKind.local_set,
            components.Local.init(local),
        });
        _ = try context.wasm_instructions.append(wasm_instruction);
    }
    const block_label = components.Label{ .value = context.label };
    const loop_label = components.Label{ .value = context.label + 1 };
    context.label += 2;
    try context.wasm_instructions.append(try context.codebase.createEntity(.{
        components.WasmInstructionKind.block,
        block_label,
    }));
    try context.wasm_instructions.append(try context.codebase.createEntity(.{
        components.WasmInstructionKind.loop,
        loop_label,
    }));
    {
        const wasm_instruction = try context.codebase.createEntity(.{
            components.WasmInstructionKind.local_get,
            components.Local.init(local),
        });
        _ = try context.wasm_instructions.append(wasm_instruction);
    }
    {
        const last = try context.codebase.createEntity(.{
            components.Type.init(builtins[i]),
            iterator.get(components.Last).entity.get(components.Literal),
        });
        const wasm_instruction = try context.codebase.createEntity(.{
            kinds[i],
            components.Constant.init(last),
        });
        _ = try context.wasm_instructions.append(wasm_instruction);
    }
    {
        const wasm_instruction = try context.codebase.createEntity(.{greaterEqualOps.kinds[i]});
        _ = try context.wasm_instructions.append(wasm_instruction);
    }
    try context.wasm_instructions.append(try context.codebase.createEntity(.{
        components.WasmInstructionKind.br_if,
        block_label,
    }));
    for (entity.get(components.Body).slice()) |expression| {
        try codegenEntity(context, expression);
    }
    {
        const string = try std.fmt.allocPrint(context.allocator, "1", .{});
        const interned = try context.codebase.getPtr(Strings).intern(string);
        const one = try context.codebase.createEntity(.{
            components.Type.init(builtins[i]),
            components.Literal.init(interned),
        });
        const wasm_instruction = try context.codebase.createEntity(.{
            kinds[i],
            components.Constant.init(one),
        });
        _ = try context.wasm_instructions.append(wasm_instruction);
    }
    {
        const wasm_instruction = try context.codebase.createEntity(.{
            components.WasmInstructionKind.local_get,
            components.Local.init(local),
        });
        _ = try context.wasm_instructions.append(wasm_instruction);
    }
    {
        const wasm_instruction = try context.codebase.createEntity(.{addOps.kinds[i]});
        _ = try context.wasm_instructions.append(wasm_instruction);
    }
    {
        const wasm_instruction = try context.codebase.createEntity(.{
            components.WasmInstructionKind.local_set,
            components.Local.init(local),
        });
        _ = try context.wasm_instructions.append(wasm_instruction);
    }
    try context.wasm_instructions.append(try context.codebase.createEntity(.{
        components.WasmInstructionKind.br,
        loop_label,
    }));
    try context.wasm_instructions.append(try context.codebase.createEntity(.{
        components.WasmInstructionKind.end,
        loop_label,
    }));
    try context.wasm_instructions.append(try context.codebase.createEntity(.{
        components.WasmInstructionKind.end,
        block_label,
    }));
    context.label -= 2;
}

fn codegenConstruct(context: *Context, entity: Entity) !void {
    for (entity.get(components.Arguments).slice()) |argument| {
        try codegenEntity(context, argument);
    }
}

fn codegenField(context: *Context, entity: Entity) !void {
    _ = try entity.set(.{components.WasmInstructionKind.field});
    try context.wasm_instructions.append(entity);
}

fn codegenAssignField(context: *Context, entity: Entity) !void {
    const value = entity.get(components.Value).entity;
    try codegenEntity(context, value);
    _ = try entity.set(.{components.WasmInstructionKind.assign_field});
    _ = try context.wasm_instructions.append(entity);
}

fn codegenConstant(comptime T: type, context: *Context, value: T) !void {
    const KindAndType = struct {
        kind: components.WasmInstructionKind,
        Type: Entity,
    };
    const kind_and_type: KindAndType = switch (T) {
        i32 => .{ .kind = .i32_const, .Type = context.builtins.I32 },
        else => panic("\ncodegen number unsupported type {s}\n", .{@typeName(T)}),
    };
    const literal = try std.fmt.allocPrint(context.allocator, "{}", .{value});
    const interned = try context.codebase.getPtr(Strings).intern(literal);
    const result = try context.codebase.createEntity(.{
        components.Type.init(kind_and_type.Type),
        components.Literal.init(interned),
        value,
    });
    const wasm_instruction = try context.codebase.createEntity(.{
        kind_and_type.kind,
        components.Constant.init(result),
    });
    _ = try context.wasm_instructions.append(wasm_instruction);
}

fn codegenString(context: *Context, entity: Entity) !void {
    try context.codebase.set(.{components.UsesMemory{ .value = true }});
    const length = entity.get(components.Length).value;
    try context.data_segment.entities.append(entity);
    try codegenConstant(i32, context, context.data_segment.end);
    try codegenConstant(i32, context, length);
    const location = components.Location{ .value = context.data_segment.end };
    _ = try entity.set(.{location});
    context.data_segment.end += length * 8;
}

fn codegenIndex(context: *Context, entity: Entity) !void {
    const arguments = entity.get(components.Arguments).slice();
    const array = arguments[0];
    const array_type = typeOf(array);
    const strings = context.codebase.getPtr(Strings);
    const interned = try strings.intern("ptr");
    for (array_type.get(components.Fields).slice()) |field| {
        if (!eql(field.get(components.Literal).interned, interned)) continue;
        const ptr = try context.codebase.createEntity(.{
            components.AstKind.field,
            components.WasmInstructionKind.field,
            components.Type.init(typeOf(field)),
            components.Local.init(array),
            components.Field.init(field),
        });
        try context.wasm_instructions.append(ptr);
        break;
    }
    try codegenEntity(context, arguments[1]);
    const size = typeOf(entity).get(components.Size).bytes;
    try codegenConstant(i32, context, size);
    const mul = try context.codebase.createEntity(.{components.WasmInstructionKind.i32_mul});
    try context.wasm_instructions.append(mul);
    const add = try context.codebase.createEntity(.{components.WasmInstructionKind.i32_add});
    try context.wasm_instructions.append(add);
    const u8_load = try context.codebase.createEntity(.{components.WasmInstructionKind.i32_load8_u});
    try context.wasm_instructions.append(u8_load);
}

fn codegenEntity(context: *Context, entity: Entity) error{ OutOfMemory, Overflow, InvalidCharacter }!void {
    const kind = entity.get(components.AstKind);
    switch (kind) {
        .int, .float => try codegenNumber(context, entity),
        .call => try codegenCall(context, entity),
        .define => try codegenDefine(context, entity),
        .assign => try codegenAssign(context, entity),
        .local => try codegenLocal(context, entity),
        .intrinsic => try codegenIntrinsic(context, entity),
        .if_ => try codegenIf(context, entity),
        .while_ => try codegenWhile(context, entity),
        .for_ => try codegenFor(context, entity),
        .cast => try codegenEntity(context, entity.get(components.Value).entity),
        .construct => try codegenConstruct(context, entity),
        .field => try codegenField(context, entity),
        .assign_field => try codegenAssignField(context, entity),
        .string => try codegenString(context, entity),
        .index => try codegenIndex(context, entity),
        else => panic("\ncodegen entity {} not implmented\n", .{kind}),
    }
}

pub fn codegen(module: Entity) !void {
    const codebase = module.ecs;
    const allocator = codebase.arena.allocator();
    const builtins = codebase.get(components.Builtins);
    try codebase.set(.{components.DataSegment.init(allocator)});
    for (module.ecs.get(components.Functions).slice()) |function| {
        if (function.has(components.Body)) |body_component| {
            var locals = components.Locals.init(allocator);
            var wasm_instructions = components.WasmInstructions.init(allocator);
            var context = Context{
                .codebase = codebase,
                .wasm_instructions = &wasm_instructions,
                .locals = &locals,
                .allocator = allocator,
                .builtins = builtins,
                .label = 0,
                .data_segment = codebase.getPtr(components.DataSegment),
            };
            for (body_component.slice()) |entity| {
                try codegenEntity(&context, entity);
            }
            _ = try function.set(.{ wasm_instructions, locals });
        }
    }
}
