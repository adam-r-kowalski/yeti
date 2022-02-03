const std = @import("std");
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const Arena = std.heap.ArenaAllocator;

const initCodebase = @import("init_codebase.zig").initCodebase;
const MockFileSystem = @import("file_system.zig").FileSystem;
const analyzeSemantics = @import("semantic_analyzer.zig").analyzeSemantics;
const codegen = @import("codegen.zig").codegen;
const printWasm = @import("wasm_printer.zig").printWasm;
const ecs = @import("ecs.zig");
const ECS = ecs.ECS;
const List = @import("list.zig").List;
const components = @import("components.zig");
const test_utils = @import("test_utils.zig");
const literalOf = test_utils.literalOf;
const colors = @import("colors.zig");

const Errors = List(u8, .{ .initial_capacity = 1000 });

pub fn printErrors(codebase: *ECS) ![]u8 {
    const allocator = codebase.arena.allocator();
    var errors = Errors.init(allocator);
    var iterator = codebase.query(.{components.Error});
    while (iterator.next()) |entity| {
        const e = entity.get(components.Error);
        try errors.appendSlice(colors.RED);
        try errors.appendSlice("---- ");
        try errors.appendSlice(e.header);
        try errors.appendSlice(" ----------------------------------- ");
        const module = e.module;
        try errors.appendSlice(module.get(components.ModulePath).string);
        try errors.appendSlice(colors.RESET);
        try errors.appendSlice("\n\n");
        try errors.appendSlice(e.body);
        try errors.appendSlice("\n\n");
        const begin = e.span.begin;
        const end = e.span.end;
        var source = module.get(components.ModuleSource).string;
        var i: usize = 0;
        const context_start = std.math.max(begin.row, 2) - 2;
        const context_end = end.row + 3;
        while (i < context_start) : (i += 1) {
            while (source[0] != '\n') : (source = source[1..]) {}
            source = source[1..];
        }
        var row = context_start;
        var column: usize = 0;
        const width = (try std.fmt.allocPrint(allocator, "{}", .{context_end})).len;
        while (row < context_end and source.len > 0) {
            if (column == 0) {
                const result = try std.fmt.allocPrint(allocator, "{:[1]}| ", .{ row + 1, width });
                try errors.appendSlice(result);
            }
            if (row == begin.row and column == begin.column) {
                try errors.appendSlice(colors.RED);
            }
            if (row == end.row and column == end.column) {
                try errors.appendSlice(colors.RESET);
            }
            switch (source[0]) {
                '\n' => {
                    row += 1;
                    column = 0;
                },
                else => {
                    column += 1;
                },
            }
            try errors.append(source[0]);
            source = source[1..];
        }
        try errors.appendSlice("\n");
        try errors.appendSlice(e.hint);
    }
    return errors.mutSlice();
}
