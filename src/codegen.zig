const std = @import("std");
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
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
const test_utils = @import("test_utils.zig");
const literalOf = test_utils.literalOf;
const typeOf = test_utils.typeOf;
const parentType = test_utils.parentType;
const valueType = test_utils.valueType;
const List = @import("list.zig").List;
const Strings = @import("strings.zig").Strings;

const Context = struct {
    codebase: *ECS,
    wasm_instructions: *components.WasmInstructions,
    locals: *components.Locals,
    allocator: Allocator,
    builtins: components.Builtins,
    label: u64,
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
    if (!entity.contains(components.Mutable)) {
        const type_of = typeOf(entity);
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
        components.Local.init(entity),
    });
    _ = try context.wasm_instructions.append(wasm_instruction);
    try context.locals.put(entity);
}

fn codegenAssign(context: *Context, entity: Entity) !void {
    const value = entity.get(components.Value).entity;
    try codegenEntity(context, value);
    const wasm_instruction = try context.codebase.createEntity(.{
        components.WasmInstructionKind.local_set,
        components.Local.init(entity),
    });
    _ = try context.wasm_instructions.append(wasm_instruction);
    return;
}

fn codegenLocal(context: *Context, entity: Entity) !void {
    const local = entity.get(components.Local);
    if (!local.entity.contains(components.Mutable)) {
        const type_of = typeOf(entity);
        const b = context.builtins;
        for (&[_]Entity{ b.IntLiteral, b.FloatLiteral }) |builtin| {
            if (!eql(type_of, builtin)) continue;
            return;
        }
        const builtins = [_]Entity{ b.I64, b.I32, b.I16, b.I8, b.U64, b.U32, b.U16, b.U8, b.F64, b.F32 };
        const types = [_]type{ i64, i32, i16, i8, u64, u32, u16, u8, f64, f32 };
        const kinds = &[_]components.WasmInstructionKind{ .i64_const, .i32_const, .i32_const, .i32_const, .i64_const, .i32_const, .i32_const, .i32_const, .f64_const, .f32_const };
        if (local.entity.has(components.Value)) |value_component| {
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
        local,
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
    const literal = try std.fmt.allocPrint(context.allocator, "{}", .{bytes});
    const interned = try context.codebase.getPtr(Strings).intern(literal);
    const result = try context.codebase.createEntity(.{
        components.Type.init(context.builtins.I32),
        components.Literal.init(interned),
        bytes,
    });
    const constant = try context.codebase.createEntity(.{
        components.WasmInstructionKind.i32_const,
        components.Constant.init(result),
    });
    const multiply = try context.codebase.createEntity(.{
        components.WasmInstructionKind.i32_mul,
    });
    const op = try context.codebase.createEntity(.{kind});
    try context.wasm_instructions.append(constant);
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
    const builtins = [_]Entity{ b.I64, b.I32, b.U64, b.U32, b.F64, b.F32 };
    const instructions = [_]components.WasmInstructionKind{ .i64_load, .i32_load, .i64_load, .i32_load, .f64_load, .f32_load };
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
    const kind = context.wasm_instructions.last().get(components.WasmInstructionKind);
    if (kind == .i32_const) {
        context.wasm_instructions.shrink(1);
        if ((try valueOf(i32, conditional)).? != 0) {
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
        .cast => try codegenEntity(context, entity.get(components.Value).entity),
        .construct => try codegenConstruct(context, entity),
        .field => try codegenField(context, entity),
        .assign_field => try codegenAssignField(context, entity),
        else => panic("\ncodegen entity {} not implmented\n", .{kind}),
    }
}

pub fn codegen(module: Entity) !void {
    const codebase = module.ecs;
    const allocator = codebase.arena.allocator();
    const builtins = codebase.get(components.Builtins);
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
            };
            for (body_component.slice()) |entity| {
                try codegenEntity(&context, entity);
            }
            _ = try function.set(.{ wasm_instructions, locals });
        }
    }
}

test "codegen int literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "i64", "i32", "u64", "u32", "f64", "f32" };
    const const_kinds = [_]components.WasmInstructionKind{ .i64_const, .i32_const, .i64_const, .i32_const, .f64_const, .f32_const };
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start = fn(): {s}
            \\  5
            \\end
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
            \\start = fn(): {s}
            \\  5
            \\end
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
            \\start = fn(): {s}
            \\  x: {s} = 10
            \\  x
            \\end
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
                \\start = fn(): {s}
                \\  8 {s} 2
                \\end
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
                \\start = fn(): {s}
                \\  x: {s} = 8
                \\  y: {s} = 2
                \\  x {s} y
                \\end
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
                \\start = fn(): {s}
                \\  x: {s} = 8
                \\  y: {s} = 2
                \\  x {s} y
                \\end
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
                \\start = fn(): i32
                \\  x: {s} = 8
                \\  y: {s} = 2
                \\  x {s} y
                \\end
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
                \\start = fn(): i32
                \\  id(10) {s} id(25)
                \\end
                \\
                \\id = fn(x: {s}): {s}
                \\  x
                \\end
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
            \\start = fn(): {s}
            \\  if 1 then 20 else 30 end
            \\end
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
            \\start = fn(): {s}
            \\  if 0 then 20 else 30 end
            \\end
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
            \\start = fn(): {s}
            \\  if f() then 20 else 30 end
            \\end
            \\
            \\f = fn(): i32 1 end
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
            \\start = fn(): {s}
            \\  x: {s} = 10
            \\  x = 3
            \\  x
            \\end
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
        \\start = fn(): i32
        \\  i = 0
        \\  while i < 10 do
        \\      i = i + 1
        \\  end
        \\  i
        \\end
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    const start_instructions = start.get(components.WasmInstructions).slice();
    try expectEqual(start_instructions.len, 17);
    // TODO: test that proper while loop instructions are generated
}

test "codegen of casting int literal to *i64" {
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
        \\start = fn(): void
        \\  ptr = cast(*i64, 0)
        \\  *ptr = 10
        \\end
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
        \\start = fn(): i64
        \\  ptr = cast(*i64, 0)
        \\  *ptr
        \\end
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
        \\start = fn(): *i64
        \\  ptr = cast(*i64, 0)
        \\  ptr + 1
        \\end
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
        \\start = fn(): *i64
        \\  ptr = cast(*i64, 0)
        \\  ptr - 1
        \\end
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
            \\start = fn(): i32
            \\  ptr = cast(*i64, 0)
            \\  ptr {s} ptr
            \\end
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
        \\start = fn(): i32
        \\  ptr = cast(*i64, 0)
        \\  ptr - ptr
        \\end
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
        \\start = fn(): i64x2
        \\  ptr = cast(*i64x2, 0)
        \\  *ptr
        \\end
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
                \\start = fn(): {s}
                \\  v = *cast(*{s}, 0)
                \\  v {s} v
                \\end
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
                \\start = fn(): {s}
                \\  v = *cast(*{s}, 0)
                \\  v {s} v
                \\end
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
        \\start = fn(): void
        \\  ptr = cast(*i64x2, 0)
        \\  *ptr = *ptr
        \\end
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

test "codegen of struct" {
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
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    const wasm_instructions = start.get(components.WasmInstructions).slice();
    try expectEqual(wasm_instructions.len, 2);
    {
        const constant = wasm_instructions[0];
        try expectEqual(constant.get(components.WasmInstructionKind), .f64_const);
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "10");
    }
    {
        const constant = wasm_instructions[1];
        try expectEqual(constant.get(components.WasmInstructionKind), .f64_const);
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "30");
    }
}

test "codegen of struct field write" {
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
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    const wasm_instructions = start.get(components.WasmInstructions).slice();
    try expectEqual(wasm_instructions.len, 6);
    {
        const constant = wasm_instructions[0];
        try expectEqual(constant.get(components.WasmInstructionKind), .f64_const);
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "10");
    }
    {
        const constant = wasm_instructions[1];
        try expectEqual(constant.get(components.WasmInstructionKind), .f64_const);
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "30");
    }
    {
        const local_set = wasm_instructions[2];
        try expectEqual(local_set.get(components.WasmInstructionKind), .local_set);
        const local = local_set.get(components.Local).entity;
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "r");
    }
    {
        const constant = wasm_instructions[3];
        try expectEqual(constant.get(components.WasmInstructionKind), .f64_const);
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "45");
    }
    {
        const assign_field = wasm_instructions[4];
        try expectEqual(assign_field.get(components.WasmInstructionKind), .assign_field);
        const local = assign_field.get(components.Local).entity;
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "r");
        try expectEqualStrings(literalOf(assign_field.get(components.Field).entity), "width");
    }
    {
        const local_get = wasm_instructions[5];
        try expectEqual(local_get.get(components.WasmInstructionKind), .local_get);
        const local = local_get.get(components.Local).entity;
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "r");
    }
}
