const std = @import("std");
const Arena = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const panic = std.debug.panic;

const yeti = @import("yeti");
const initCodebase = yeti.initCodebase;
const analyzeSemantics = yeti.analyzeSemantics;
const codegen = yeti.codegen;
const printWasm = yeti.printWasm;
const printErrors = yeti.printErrors;
const List = yeti.List;
const components = yeti.components;

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
        const file = std.fs.cwd().openFile(name, std.fs.File.OpenFlags{}) catch return error.CantOpenFile;
        try self.files.append(file);
        return file.readToEndAlloc(self.allocator, std.math.maxInt(i64)) catch return error.OutOfMemory;
    }
};

pub fn main() !void {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const args = try std.process.argsAlloc(allocator);
    assert(args.len == 2);
    var fs = FileSystem.init(&arena);
    defer fs.deinit();
    var codebase = try initCodebase(&arena);
    const yeti_filename = args[1];
    const module = analyzeSemantics(codebase, &fs, yeti_filename) catch |e| switch (e) {
        error.CompileError => {
            const errors = try printErrors(codebase);
            std.debug.print("{s}", .{errors});
            return;
        },
        else => |err| panic("\ncompiler crashed with error {}\n", .{err}),
    };
    try codegen(module);
    const wasm = try printWasm(module);
    const foreign_exports = module.get(components.ForeignExports).slice();
    const wat_filename = try allocator.alloc(u8, yeti_filename.len - 1);
    const cutoff = yeti_filename.len - 4;
    std.mem.copy(u8, wat_filename, yeti_filename[0..cutoff]);
    std.mem.copy(u8, wat_filename[cutoff..], "wat");
    const cwd = std.fs.cwd();
    try cwd.writeFile(wat_filename, wasm);
    if (foreign_exports.len > 0) return;
    const result = try std.ChildProcess.exec(.{
        .allocator = arena.allocator(),
        .argv = &.{ "wasmtime", wat_filename },
    });
    std.debug.print("{s}", .{result.stdout});
    try cwd.deleteFile(wat_filename);
}
