const std = @import("std");
const Arena = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const initCodebase = @import("init_codebase.zig").initCodebase;
const lower = @import("lower.zig").lower;
const codegen = @import("codegen.zig").codegen;
const wasmString = @import("wasm_string.zig").wasmString;
const List = @import("list.zig").List;

const FileSystem = struct {
    const Files = List(std.fs.File, .{});

    files: Files,
    allocator: *Allocator,

    fn init(arena: *Arena) FileSystem {
        return FileSystem{
            .files = Files.init(&arena.allocator),
            .allocator = &arena.allocator,
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
    const args = try std.process.argsAlloc(&arena.allocator);
    assert(args.len == 3);
    var fs = FileSystem.init(&arena);
    defer fs.deinit();
    var codebase = try initCodebase(&arena);
    const module = try lower(codebase, &fs, args[1], "start");
    try codegen(module);
    const wasm_string = try wasmString(module);
    try std.fs.cwd().writeFile(args[2], wasm_string);
}
