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
const lower = @import("lower.zig").lower;
const ecs = @import("ecs.zig");
const Entity = ecs.Entity;
const ECS = ecs.ECS;
const components = @import("components.zig");
const test_utils = @import("test_utils.zig");
const literalOf = test_utils.literalOf;
const typeOf = test_utils.typeOf;
const List = @import("list.zig").List;

const Context = struct {
    codebase: *ECS,
    wasm_instructions: *components.WasmInstructions,
    locals: *components.Locals,
    allocator: *Allocator,
    builtins: components.Builtins,
};

fn codegenIntConst(context: Context, ir_instruction: Entity) !void {
    const int_const = ir_instruction.get(components.Result).entity;
    const type_ = typeOf(int_const);
    if (eql(type_, context.builtins.IntLiteral)) {
        return;
    }
    const b = context.builtins;
    const builtins = &[_]Entity{ b.I64, b.I32, b.U64, b.U32, b.F64, b.F32 };
    const kinds = &[_]components.WasmInstructionKind{ .i64_const, .i32_const, .i64_const, .i32_const, .f64_const, .f32_const };
    for (builtins) |builtin, i| {
        if (!eql(type_, builtin)) continue;
        const wasm_instruction = try context.codebase.createEntity(.{
            kinds[i],
            components.Result.init(int_const),
        });
        _ = try context.wasm_instructions.append(wasm_instruction);
        return;
    }
    panic("\ncodegen int const for type {s} not supported\n", .{literalOf(type_)});
}

fn codegenFloatConst(context: Context, ir_instruction: Entity) !void {
    const float_const = ir_instruction.get(components.Result).entity;
    const type_ = float_const.get(components.Type).entity;
    if (eql(type_, context.builtins.FloatLiteral)) {
        return;
    }
    const b = context.builtins;
    const builtins = &[_]Entity{ b.F64, b.F32 };
    const kinds = &[_]components.WasmInstructionKind{ .f64_const, .f32_const };
    for (builtins) |builtin, i| {
        if (!eql(type_, builtin)) continue;
        const wasm_instruction = try context.codebase.createEntity(.{
            kinds[i],
            components.Result.init(float_const),
        });
        _ = try context.wasm_instructions.append(wasm_instruction);
        return;
    }
    panic("\ncodegen float const for type {s} not supported\n", .{literalOf(type_)});
}

fn codegenCall(context: Context, ir_instruction: Entity) !void {
    const wasm_instruction = try context.codebase.createEntity(.{
        components.WasmInstructionKind.call,
        ir_instruction.get(components.Callable),
    });
    _ = try context.wasm_instructions.append(wasm_instruction);
}

fn codegenGetLocal(context: Context, ir_instruction: Entity) !void {
    const local = ir_instruction.get(components.Result).entity;
    const type_of = local.get(components.Type).entity;
    const b = context.builtins;
    const builtins = &[_]Entity{ b.I64, b.I32, b.U64, b.U32, b.F64, b.F32 };
    for (builtins) |builtin| {
        if (!eql(type_of, builtin)) continue;
        const wasm_instruction = try context.codebase.createEntity(.{
            components.WasmInstructionKind.get_local,
            components.Result.init(local),
        });
        _ = try context.wasm_instructions.append(wasm_instruction);
        try context.locals.put(local);
        return;
    }
    panic("\ncodegen get local type not supported {s}\n", .{literalOf(type_of)});
}

fn codegenSetLocal(context: Context, ir_instruction: Entity) !void {
    const local = ir_instruction.get(components.Result).entity;
    const type_of = local.get(components.Type).entity;
    if (eql(type_of, context.builtins.IntLiteral)) {
        return;
    }
    const b = context.builtins;
    const builtins = &[_]Entity{ b.I64, b.I32, b.U64, b.U32, b.F64, b.F32 };
    for (builtins) |builtin| {
        if (!eql(type_of, builtin)) continue;
        const wasm_instruction = try context.codebase.createEntity(.{
            components.WasmInstructionKind.set_local,
            components.Result.init(local),
        });
        _ = try context.wasm_instructions.append(wasm_instruction);
        try context.locals.put(local);
        return;
    }
    panic("\ncodegen set local type not supported {s}\n", .{literalOf(type_of)});
}

fn codegenBinaryOp(context: Context, kind: components.WasmInstructionKind) !void {
    const wasm_instruction = try context.codebase.createEntity(.{kind});
    _ = try context.wasm_instructions.append(wasm_instruction);
    return;
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
        const basic_blocks = function.get(components.BasicBlocks).slice();
        try expectEqual(basic_blocks.len, 1);
        const basic_block = basic_blocks[0].get(components.IrInstructions).slice();
        for (basic_block) |ir_instruction| {
            const kind = ir_instruction.get(components.IrInstructionKind);
            switch (kind) {
                .int_const => try codegenIntConst(context, ir_instruction),
                .float_const => try codegenFloatConst(context, ir_instruction),
                .i64_add => try codegenBinaryOp(context, .i64_add),
                .i32_add => try codegenBinaryOp(context, .i32_add),
                .f64_add => try codegenBinaryOp(context, .f64_add),
                .f32_add => try codegenBinaryOp(context, .f32_add),
                .i64_sub => try codegenBinaryOp(context, .i64_sub),
                .i32_sub => try codegenBinaryOp(context, .i32_sub),
                .f64_sub => try codegenBinaryOp(context, .f64_sub),
                .f32_sub => try codegenBinaryOp(context, .f32_sub),
                .i64_mul => try codegenBinaryOp(context, .i64_mul),
                .i32_mul => try codegenBinaryOp(context, .i32_mul),
                .f64_mul => try codegenBinaryOp(context, .f64_mul),
                .f32_mul => try codegenBinaryOp(context, .f32_mul),
                .i64_div => try codegenBinaryOp(context, .i64_div),
                .i32_div => try codegenBinaryOp(context, .i32_div),
                .u64_div => try codegenBinaryOp(context, .u64_div),
                .u32_div => try codegenBinaryOp(context, .u32_div),
                .f64_div => try codegenBinaryOp(context, .f64_div),
                .f32_div => try codegenBinaryOp(context, .f32_div),
                .call => try codegenCall(context, ir_instruction),
                .get_local => try codegenGetLocal(context, ir_instruction),
                .set_local => try codegenSetLocal(context, ir_instruction),
            }
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
        const module = try lower(codebase, fs, "foo.yeti", "start");
        try codegen(module);
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        const wasm_instructions = start.get(components.WasmInstructions).slice();
        try expectEqual(wasm_instructions.len, 1);
        const i64_const = wasm_instructions[0];
        try expectEqual(i64_const.get(components.WasmInstructionKind), const_kinds[i]);
        try expectEqualStrings(literalOf(i64_const.get(components.Result).entity), "5");
    }
}

test "codegen float literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "F64", "F32" };
    const const_kinds = [_]components.WasmInstructionKind{ .f64_const, .f32_const };
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(&arena.allocator,
            \\start = function(): {s}
            \\  5.3
            \\end
        , .{type_}));
        const module = try lower(codebase, fs, "foo.yeti", "start");
        try codegen(module);
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        const wasm_instructions = start.get(components.WasmInstructions).slice();
        try expectEqual(wasm_instructions.len, 1);
        const f64_const = wasm_instructions[0];
        try expectEqual(f64_const.get(components.WasmInstructionKind), const_kinds[i]);
        try expectEqualStrings(literalOf(f64_const.get(components.Result).entity), "5.3");
    }
}

test "codegen int literal as float" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "F64", "F32" };
    const const_kinds = [_]components.WasmInstructionKind{ .f64_const, .f32_const };
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(&arena.allocator,
            \\start = function(): {s}
            \\  5
            \\end
        , .{type_}));
        const module = try lower(codebase, fs, "foo.yeti", "start");
        try codegen(module);
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        const wasm_instructions = start.get(components.WasmInstructions).slice();
        try expectEqual(wasm_instructions.len, 1);
        const f64_const = wasm_instructions[0];
        try expectEqual(f64_const.get(components.WasmInstructionKind), const_kinds[i]);
        try expectEqualStrings(literalOf(f64_const.get(components.Result).entity), "5");
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
        const module = try lower(codebase, fs, "foo.yeti", "start");
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
        const i64_const = baz_instructions[0];
        try expectEqual(i64_const.get(components.WasmInstructionKind), const_kinds[i]);
        try expectEqualStrings(literalOf(i64_const.get(components.Result).entity), "10");
    }
}

test "codegen call function from import" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "I64", "I32", "U64", "U32", "F64", "F32" };
    const const_kinds = [_]components.WasmInstructionKind{ .i64_const, .i32_const, .i64_const, .i32_const, .f64_const, .f32_const };
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(&arena.allocator,
            \\bar = import("bar.yeti")
            \\
            \\start = function(): {s}
            \\  bar.baz()
            \\end
        , .{type_}));
        _ = try fs.newFile("bar.yeti", try std.fmt.allocPrint(&arena.allocator,
            \\baz = function(): {s}
            \\  10
            \\end
        , .{type_}));
        const module = try lower(codebase, fs, "foo.yeti", "start");
        try codegen(module);
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        const start_instructions = start.get(components.WasmInstructions).slice();
        try expectEqual(start_instructions.len, 1);
        try expectEqual(start_instructions.len, 1);
        const call = start_instructions[0];
        try expectEqual(call.get(components.WasmInstructionKind), .call);
        const baz = call.get(components.Callable).entity;
        const baz_instructions = baz.get(components.WasmInstructions).slice();
        try expectEqual(baz_instructions.len, 1);
        const i64_const = baz_instructions[0];
        try expectEqual(i64_const.get(components.WasmInstructionKind), const_kinds[i]);
        try expectEqualStrings(literalOf(i64_const.get(components.Result).entity), "10");
    }
}

test "codegen assignment" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "I64", "I32", "U64", "U32", "F64", "F32" };
    const const_kinds = [_]components.WasmInstructionKind{ .i64_const, .i32_const, .i64_const, .i32_const, .f64_const, .f32_const };
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(&arena.allocator,
            \\start = function(): {s}
            \\  x = 10
            \\  x
            \\end
        , .{type_}));
        const module = try lower(codebase, fs, "foo.yeti", "start");
        try codegen(module);
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        const start_instructions = start.get(components.WasmInstructions).slice();
        try expectEqual(start_instructions.len, 3);
        const i64_const = start_instructions[0];
        try expectEqual(i64_const.get(components.WasmInstructionKind), const_kinds[i]);
        try expectEqualStrings(literalOf(i64_const.get(components.Result).entity), "10");
        const set_local = start_instructions[1];
        try expectEqual(set_local.get(components.WasmInstructionKind), .set_local);
        try expectEqualStrings(literalOf(set_local.get(components.Result).entity.get(components.Name).entity), "x");
        const get_local = start_instructions[2];
        try expectEqual(get_local.get(components.WasmInstructionKind), .get_local);
        try expectEqualStrings(literalOf(get_local.get(components.Result).entity.get(components.Name).entity), "x");
    }
}

test "codegen two assignments" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "I64", "I32", "U64", "U32", "F64", "F32" };
    const const_kinds = [_]components.WasmInstructionKind{ .i64_const, .i32_const, .i64_const, .i32_const, .f64_const, .f32_const };
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(&arena.allocator,
            \\start = function(): {s}
            \\  x = 10
            \\  y = 42
            \\  x
            \\end
        , .{type_}));
        const module = try lower(codebase, fs, "foo.yeti", "start");
        try codegen(module);
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        const start_instructions = start.get(components.WasmInstructions).slice();
        try expectEqual(start_instructions.len, 3);
        const i64_const = start_instructions[0];
        try expectEqual(i64_const.get(components.WasmInstructionKind), const_kinds[i]);
        const x = i64_const.get(components.Result).entity;
        try expectEqualStrings(literalOf(x), "10");
        const set_local = start_instructions[1];
        try expectEqual(set_local.get(components.WasmInstructionKind), .set_local);
        try expectEqual(set_local.get(components.Result).entity, x);
        const get_local = start_instructions[2];
        try expectEqual(get_local.get(components.WasmInstructionKind), .get_local);
        try expectEqual(get_local.get(components.Result).entity, x);
    }
}

test "codegen assignment explicit type" {
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
        const module = try lower(codebase, fs, "foo.yeti", "start");
        try codegen(module);
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        const start_instructions = start.get(components.WasmInstructions).slice();
        try expectEqual(start_instructions.len, 3);
        const i64_const = start_instructions[0];
        try expectEqual(i64_const.get(components.WasmInstructionKind), const_kinds[i]);
        const x = i64_const.get(components.Result).entity;
        try expectEqualStrings(literalOf(x), "10");
        const set_local = start_instructions[1];
        try expectEqual(set_local.get(components.WasmInstructionKind), .set_local);
        try expectEqual(set_local.get(components.Result).entity, x);
        const get_local = start_instructions[2];
        try expectEqual(get_local.get(components.WasmInstructionKind), .get_local);
        try expectEqual(get_local.get(components.Result).entity, x);
    }
}

test "codegen function with argument" {
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
            \\  id(x)
            \\end
            \\
            \\id = function(x: {s}): {s}
            \\  x
            \\end
        , .{ type_, type_, type_, type_ }));
        const module = try lower(codebase, fs, "foo.yeti", "start");
        try codegen(module);
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        const start_instructions = start.get(components.WasmInstructions).slice();
        try expectEqual(start_instructions.len, 4);
        const i64_const = start_instructions[0];
        try expectEqual(i64_const.get(components.WasmInstructionKind), const_kinds[i]);
        const x = i64_const.get(components.Result).entity;
        try expectEqualStrings(literalOf(x), "10");
        const set_local = start_instructions[1];
        try expectEqual(set_local.get(components.WasmInstructionKind), .set_local);
        try expectEqual(set_local.get(components.Result).entity, x);
        const get_local = start_instructions[2];
        try expectEqual(get_local.get(components.WasmInstructionKind), .get_local);
        try expectEqual(get_local.get(components.Result).entity, x);
        const call = start_instructions[3];
        try expectEqual(call.get(components.WasmInstructionKind), .call);
        const id = call.get(components.Callable).entity;
        try expectEqualStrings(literalOf(id.get(components.Name).entity), "id");
        const id_instructions = id.get(components.WasmInstructions).slice();
        try expectEqual(id_instructions.len, 1);
        const id_get_local = id_instructions[0];
        try expectEqual(id_get_local.get(components.WasmInstructionKind), .get_local);
        try expectEqualStrings(literalOf(id_get_local.get(components.Result).entity.get(components.Name).entity), "x");
    }
}

test "codegen add" {
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
            \\  x: {s} = 10
            \\  y: {s} = 32
            \\  x + y
            \\end
        , .{ type_, type_, type_ }));
        const module = try lower(codebase, fs, "foo.yeti", "start");
        try codegen(module);
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        const start_instructions = start.get(components.WasmInstructions).slice();
        try expectEqual(start_instructions.len, 7);
        const x = blk: {
            const i64_const = start_instructions[0];
            try expectEqual(i64_const.get(components.WasmInstructionKind), const_kinds[i]);
            const result = i64_const.get(components.Result).entity;
            try expectEqualStrings(literalOf(result), "10");
            const set_local = start_instructions[1];
            try expectEqual(set_local.get(components.WasmInstructionKind), .set_local);
            try expectEqual(set_local.get(components.Result).entity, result);
            break :blk result;
        };
        const y = blk: {
            const i64_const = start_instructions[2];
            try expectEqual(i64_const.get(components.WasmInstructionKind), const_kinds[i]);
            const result = i64_const.get(components.Result).entity;
            try expectEqualStrings(literalOf(result), "32");
            const set_local = start_instructions[3];
            try expectEqual(set_local.get(components.WasmInstructionKind), .set_local);
            try expectEqual(set_local.get(components.Result).entity, result);
            break :blk result;
        };
        {
            const get_local = start_instructions[4];
            try expectEqual(get_local.get(components.WasmInstructionKind), .get_local);
            try expectEqual(get_local.get(components.Result).entity, x);
        }
        {
            const get_local = start_instructions[5];
            try expectEqual(get_local.get(components.WasmInstructionKind), .get_local);
            try expectEqual(get_local.get(components.Result).entity, y);
        }
        try expectEqual(start_instructions[6].get(components.WasmInstructionKind), add_kinds[i]);
    }
}

test "codegen int literal add" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const types = [_][]const u8{ "I64", "I32", "U64", "U32", "F64", "F32" };
    const const_kinds = [_]components.WasmInstructionKind{ .i64_const, .i32_const, .i64_const, .i32_const, .f64_const, .f32_const };
    for (types) |type_, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(&arena.allocator,
            \\start = function(): {s}
            \\  10 + 32
            \\end
        , .{type_}));
        const module = try lower(codebase, fs, "foo.yeti", "start");
        try codegen(module);
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        const start_instructions = start.get(components.WasmInstructions).slice();
        try expectEqual(start_instructions.len, 1);
        const i64_const = start_instructions[0];
        try expectEqual(i64_const.get(components.WasmInstructionKind), const_kinds[i]);
        const result = i64_const.get(components.Result).entity;
        try expectEqualStrings(literalOf(result), "42");
    }
}
