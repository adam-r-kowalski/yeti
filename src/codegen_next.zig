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

const Context = struct {
    codebase: *ECS,
    wasm_instructions: *components.WasmInstructions,
    locals: *components.Locals,
    allocator: *Allocator,
    builtins: components.Builtins,
};

fn codegenNumber(context: Context, entity: Entity) !void {
    const type_ = typeOf(entity);
    const b = context.builtins;
    for (&[_]Entity{ b.IntLiteral, b.FloatLiteral }) |builtin| {
        if (eql(type_, builtin)) {
            return;
        }
    }
    const builtins = &[_]Entity{ b.I64, b.I32, b.U64, b.U32, b.F64, b.F32 };
    const kinds = &[_]components.WasmInstructionKind{ .i64_const, .i32_const, .i64_const, .i32_const, .f64_const, .f32_const };
    for (builtins) |builtin, i| {
        if (!eql(type_, builtin)) continue;
        const wasm_instruction = try context.codebase.createEntity(.{
            kinds[i],
            components.Constant.init(entity),
        });
        _ = try context.wasm_instructions.append(wasm_instruction);
        return;
    }
}

fn codegenCall(context: Context, entity: Entity) !void {
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
    try codegenEntity(context, entity.get(components.Value).entity);
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
    const wasm_instruction = try context.codebase.createEntity(.{
        components.WasmInstructionKind.get_local,
        entity.get(components.Local),
    });
    _ = try context.wasm_instructions.append(wasm_instruction);
}

fn codegenEntity(context: Context, entity: Entity) error{OutOfMemory}!void {
    const kind = entity.get(components.AstKind);
    switch (kind) {
        .int, .float => try codegenNumber(context, entity),
        .call => try codegenCall(context, entity),
        .define => try codegenDefine(context, entity),
        .local => try codegenLocal(context, entity),
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
        try expectEqual(start_instructions.len, 3);
        const i64_const = start_instructions[0];
        try expectEqual(i64_const.get(components.WasmInstructionKind), const_kinds[i]);
        const x = i64_const.get(components.Constant).entity;
        try expectEqualStrings(literalOf(x), "10");
        const set_local = start_instructions[1];
        try expectEqual(set_local.get(components.WasmInstructionKind), .set_local);
        const local = set_local.get(components.Local).entity;
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "x");
        const get_local = start_instructions[2];
        try expectEqual(get_local.get(components.WasmInstructionKind), .get_local);
        try expectEqual(get_local.get(components.Local).entity, local);
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
        const module = try analyzeSemantics(codebase, fs, "foo.yeti", "start");
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
