const std = @import("std");
const Arena = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const initCodebase = @import("init_codebase.zig").initCodebase;
const analyzeSemantics = @import("semantic_analyzer.zig").analyzeSemantics;
const codegen = @import("codegen.zig").codegen;
const printWasm = @import("wasm_printer.zig").printWasm;
const List = @import("list.zig").List;
const components = @import("components.zig");

const FileSystem = struct {
    const Files = List(std.fs.File, .{});

    files: Files,
    allocator: Allocator,

    fn init(arena: *Arena) FileSystem {
        return FileSystem{
            .files = Files.init(arena.allocator()),
            .allocator = arena.allocator(),
        };
    }

    fn deinit(self: *FileSystem) void {
        for (self.files.slice()) |file| {
            file.close();
        }
        self.files.deinit();
    }

    pub fn read(self: *FileSystem, name: []const u8) error{ OutOfMemory, CantOpenFile }![]const u8 {
        const file = std.fs.cwd().openFile(name, std.fs.File.OpenFlags{ .read = true }) catch return error.CantOpenFile;
        try self.files.append(file);
        return file.readToEndAlloc(self.allocator, std.math.maxInt(i64)) catch return error.OutOfMemory;
    }
};

pub fn main() !void {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    const args = try std.process.argsAlloc(arena.allocator());
    assert(args.len == 3);
    var fs = FileSystem.init(&arena);
    defer fs.deinit();
    var codebase = try initCodebase(&arena);
    const module = try analyzeSemantics(codebase, &fs, args[1]);
    try codegen(module);
    const wasm = try printWasm(module);
    const foreign_exports = module.get(components.ForeignExports).slice();
    if (foreign_exports.len > 0) return;
    try std.fs.cwd().writeFile(args[2], wasm);
    const result = try std.ChildProcess.exec(.{
        .allocator = arena.allocator(),
        .argv = &.{ "wasmtime", args[2] },
    });
    std.debug.print("{s}", .{result.stdout});
}
