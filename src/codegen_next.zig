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
const List = @import("list.zig").List;
const Strings = @import("strings.zig").Strings;

const Context = struct {
    codebase: *ECS,
    wasm_instructions: *components.WasmInstructions,
    locals: *components.Locals,
    allocator: *Allocator,
    builtins: components.Builtins,
};

fn codegenNumber(context: Context, entity: Entity) !void {
    const type_of = typeOf(entity);
    const b = context.builtins;
    for (&[_]Entity{ b.IntLiteral, b.FloatLiteral }) |builtin| {
        if (eql(type_of, builtin)) {
            return;
        }
    }
    const builtins = &[_]Entity{ b.I64, b.I32, b.U64, b.U32, b.F64, b.F32 };
    const kinds = &[_]components.WasmInstructionKind{ .i64_const, .i32_const, .i64_const, .i32_const, .f64_const, .f32_const };
    for (builtins) |builtin, i| {
        if (!eql(type_of, builtin)) continue;
        const wasm_instruction = try context.codebase.createEntity(.{
            kinds[i],
            components.Constant.init(entity),
        });
        _ = try context.wasm_instructions.append(wasm_instruction);
        return;
    }
}

fn codegenCall(context: Context, entity: Entity) !void {
    for (entity.get(components.Arguments).slice()) |argument| {
        try codegenEntity(context, argument);
    }
    const wasm_instruction = try context.codebase.createEntity(.{
        components.WasmInstructionKind.call,
        entity.get(components.Callable),
    });
    _ = try context.wasm_instructions.append(wasm_instruction);
}

fn codegenDefine(context: Context, entity: Entity) !void {
    const type_of = typeOf(entity);
    const b = context.builtins;
    for (&[_]Entity{ b.IntLiteral, b.FloatLiteral }) |builtin| {
        if (!eql(type_of, builtin)) continue;
        return;
    }
    const builtins = [_]Entity{ b.I64, b.I32, b.U64, b.U32, b.F64, b.F32 };
    const types = [_]type{ i64, i32, u64, u32, f64, f32 };
    const value = entity.get(components.Value).entity;
    inline for (&types) |T, i| {
        if (eql(builtins[i], type_of)) {
            if (try valueOf(T, value)) |_| {
                return;
            }
        }
    }
    try codegenEntity(context, value);
    const wasm_instruction = try context.codebase.createEntity(.{
        components.WasmInstructionKind.set_local,
        components.Local.init(entity),
    });
    _ = try context.wasm_instructions.append(wasm_instruction);
    try context.locals.put(entity);
    return;
}

fn codegenLocal(context: Context, entity: Entity) !void {
    const type_of = typeOf(entity);
    const b = context.builtins;
    for (&[_]Entity{ b.IntLiteral, b.FloatLiteral }) |builtin| {
        if (!eql(type_of, builtin)) continue;
        return;
    }
    const builtins = [_]Entity{ b.I64, b.I32, b.U64, b.U32, b.F64, b.F32 };
    const types = [_]type{ i64, i32, u64, u32, f64, f32 };
    const kinds = &[_]components.WasmInstructionKind{ .i64_const, .i32_const, .i64_const, .i32_const, .f64_const, .f32_const };
    const local = entity.get(components.Local).entity;
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
    const wasm_instruction = try context.codebase.createEntity(.{
        components.WasmInstructionKind.get_local,
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
        const types = [_]type{ i64, i32, u64, u32 };
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

fn codegenAdd(context: Context, entity: Entity) !void {
    const arguments = entity.get(components.Arguments).slice();
    try codegenEntity(context, arguments[0]);
    try codegenEntity(context, arguments[1]);
    const type_of = typeOf(entity);
    const b = context.builtins;
    const types = [_]type{ i64, i32, u64, u32, f64, f32 };
    const builtins = [_]Entity{ b.I64, b.I32, b.U64, b.U32, b.F64, b.F32 };
    const constant_kinds = &[_]components.WasmInstructionKind{ .i64_const, .i32_const, .i64_const, .i32_const, .f64_const, .f32_const };
    const add_kinds = &[_]components.WasmInstructionKind{ .i64_add, .i32_add, .i64_add, .i32_add, .f64_add, .f32_add };
    inline for (&types) |T, i| {
        if (eql(type_of, builtins[i])) {
            const instructions = context.wasm_instructions.mutSlice();
            const rhs = instructions[instructions.len - 1];
            const lhs = instructions[instructions.len - 2];
            const lhs_kind = lhs.get(components.WasmInstructionKind);
            const rhs_kind = rhs.get(components.WasmInstructionKind);
            const kind = constant_kinds[i];
            if (lhs_kind == kind and rhs_kind == kind) {
                const lhs_value = (try valueOf(T, lhs.get(components.Constant).entity)).?;
                const rhs_value = (try valueOf(T, rhs.get(components.Constant).entity)).?;
                const result_value = lhs_value + rhs_value;
                const result_literal = try std.fmt.allocPrint(context.allocator, "{}", .{result_value});
                const interned = try context.codebase.getPtr(Strings).intern(result_literal);
                const result = try context.codebase.createEntity(.{
                    components.Type.init(type_of),
                    components.Literal.init(interned),
                    result_value,
                });
                instructions[instructions.len - 2] = try context.codebase.createEntity(.{
                    kind,
                    components.Constant.init(result),
                });
                context.wasm_instructions.shrink(1);
                return;
            }
            const instruction = try context.codebase.createEntity(.{add_kinds[i]});
            try context.wasm_instructions.append(instruction);
            return;
        }
    }
    panic("\ncodegen add unspported type {s}\n", .{literalOf(type_of)});
}

fn codegenIntrinsic(context: Context, entity: Entity) !void {
    const intrinsic = entity.get(components.Intrinsic);
    switch (intrinsic) {
        .add => try codegenAdd(context, entity),
        else => panic("\ncodegen intrinsic {} not implmented\n", .{intrinsic}),
    }
}

fn codegenEntity(context: Context, entity: Entity) error{ OutOfMemory, Overflow, InvalidCharacter }!void {
    const kind = entity.get(components.AstKind);
    switch (kind) {
        .int, .float => try codegenNumber(context, entity),
        .call => try codegenCall(context, entity),
        .define => try codegenDefine(context, entity),
        .local => try codegenLocal(context, entity),
        .intrinsic => try codegenIntrinsic(context, entity),
        else => panic("\ncodegen entity {} not implmented\n", .{kind}),
    }
}

pub fn codegen(module: Entity) !void {
    const codebase = module.ecs;
    const allocator = &codebase.arena.allocator;
    const builtins = codebase.get(components.Builtins);
    for (module.ecs.get(components.Functions).slice()) |function| {
        var locals = components.Locals.init(allocator);
        var wasm_instructions = components.WasmInstructions.init(allocator);
        const context = Context{
            .codebase = codebase,
            .wasm_instructions = &wasm_instructions,
            .locals = &locals,
            .allocator = allocator,
            .builtins = builtins,
        };
        const body = function.get(components.AnalyzedBody).slice();
        for (body) |entity| {
            try codegenEntity(context, entity);
        }
        _ = try function.set(.{ wasm_instructions, locals });
    }
}

test "codegen int literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "I64", "I32", "U64", "U32", "F64", "F32" };
    const const_kinds = [_]components.WasmInstructionKind{ .i64_const, .i32_const, .i64_const, .i32_const, .f64_const, .f32_const };
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(&arena.allocator,
            \\start = function(): {s}
            \\  5
            \\end
        , .{type_}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti", "start");
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
    const types = [_][]const u8{ "I64", "I32", "U64", "U32", "F64", "F32" };
    const const_kinds = [_]components.WasmInstructionKind{ .i64_const, .i32_const, .i64_const, .i32_const, .f64_const, .f32_const };
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(&arena.allocator,
            \\start = function(): {s}
            \\  5
            \\end
        , .{type_}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti", "start");
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
    const types = [_][]const u8{ "I64", "I32", "U64", "U32", "F64", "F32" };
    const const_kinds = [_]components.WasmInstructionKind{ .i64_const, .i32_const, .i64_const, .i32_const, .f64_const, .f32_const };
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

test "codegen define" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "I64", "I32", "U64", "U32", "F64", "F32" };
    const const_kinds = [_]components.WasmInstructionKind{ .i64_const, .i32_const, .i64_const, .i32_const, .f64_const, .f32_const };
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(&arena.allocator,
            \\start = function(): {s}
            \\  x: {s} = 10
            \\  x
            \\end
        , .{ type_, type_ }));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti", "start");
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

test "codegen add two int literals" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "I64", "I32", "U64", "U32", "F64", "F32" };
    const const_kinds = [_]components.WasmInstructionKind{ .i64_const, .i32_const, .i64_const, .i32_const, .f64_const, .f32_const };
    const results = [_][]const u8{ "10", "10", "10", "10", "1.0e+01", "1.0e+01" };
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(&arena.allocator,
            \\start = function(): {s}
            \\  8 + 2
            \\end
        , .{type_}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti", "start");
        try codegen(module);
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        const start_instructions = start.get(components.WasmInstructions).slice();
        try expectEqual(start_instructions.len, 1);
        const constant = start_instructions[0];
        try expectEqual(constant.get(components.WasmInstructionKind), const_kinds[i]);
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), results[i]);
    }
}

test "codegen add two local constants" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "I64", "I32", "U64", "U32", "F64", "F32" };
    const const_kinds = [_]components.WasmInstructionKind{ .i64_const, .i32_const, .i64_const, .i32_const, .f64_const, .f32_const };
    const results = [_][]const u8{ "10", "10", "10", "10", "1.0e+01", "1.0e+01" };
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(&arena.allocator,
            \\start = function(): {s}
            \\  x: {s} = 8
            \\  y: {s} = 2
            \\  x + y
            \\end
        , .{ type_, type_, type_ }));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti", "start");
        try codegen(module);
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        const start_instructions = start.get(components.WasmInstructions).slice();
        try expectEqual(start_instructions.len, 1);
        const constant = start_instructions[0];
        try expectEqual(constant.get(components.WasmInstructionKind), const_kinds[i]);
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), results[i]);
    }
}

test "codegen add through two function calls" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "I64", "I32", "U64", "U32", "F64", "F32" };
    const const_kinds = [_]components.WasmInstructionKind{ .i64_const, .i32_const, .i64_const, .i32_const, .f64_const, .f32_const };
    const add_kinds = [_]components.WasmInstructionKind{ .i64_add, .i32_add, .i64_add, .i32_add, .f64_add, .f32_add };
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(&arena.allocator,
            \\start = function(): {s}
            \\  id(10) + id(25)
            \\end
            \\
            \\id = function(x: {s}): {s}
            \\  x
            \\end
        , .{ type_, type_, type_ }));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti", "start");
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
        const add = start_instructions[4];
        try expectEqual(add.get(components.WasmInstructionKind), add_kinds[i]);
    }
}
