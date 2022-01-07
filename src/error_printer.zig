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

const Errors = List(u8, .{ .initial_capacity = 1000 });

pub fn printErrors(codebase: *ECS) ![]u8 {
    const allocator = codebase.arena.allocator();
    var errors = Errors.init(allocator);
    var iterator = codebase.query(.{components.Error});
    while (iterator.next()) |entity| {
        const e = entity.get(components.Error);
        try errors.appendSlice("---- ");
        try errors.appendSlice(e.header);
        try errors.appendSlice(" ----------------------------------- ");
        const module = e.module;
        try errors.appendSlice(module.get(components.ModulePath).string);
        try errors.appendSlice("\n\n");
        try errors.appendSlice(e.body);
        try errors.appendSlice("\n\n");
        const begin = e.span.begin.row;
        const end = e.span.end.row;
        var source = module.get(components.ModuleSource).string;
        var i: usize = 0;
        var current = std.math.max(begin, 1) - 1;
        while (i < current) : (i += 1) {
            while (source[0] != '\n') : (source = source[1..]) {}
            source = source[1..];
        }
        while (current <= end + 1) : (current += 1) {
            var line_length: usize = 0;
            while (source.len > line_length and source[line_length] != '\n') : (line_length += 1) {}
            const result = try std.fmt.allocPrint(allocator, "{}| ", .{current});
            try errors.appendSlice(result);
            try errors.appendSlice(source[0..line_length]);
            source = source[line_length..];
            if (source.len > 0) source = source[1..];
            try errors.append('\n');
        }
        try errors.appendSlice("\n");
        try errors.appendSlice(e.hint);
    }
    return errors.mutSlice();
}

test "error printer calling function with to few parameters" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\add = fn(x: i64, y: i64): i64
        \\  x + y
        \\end
        \\
        \\start = fn(): i64
        \\  add(5)
        \\end
    );
    try expectEqual(analyzeSemantics(codebase, fs, "foo.yeti"), error.CompileError);
    const error_message = try printErrors(codebase);
    try expectEqualStrings(error_message,
        \\---- FUNCTION CALL ERROR ----------------------------------- foo.yeti
        \\
        \\No function overload matching arguments (IntLiteral) found
        \\
        \\4| start = fn(): i64
        \\5|   add(5)
        \\6| end
        \\
        \\Here are the possible candidates:
        \\
        \\add = fn(x: i64, y: i64)
        \\
    );
}
