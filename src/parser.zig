const std = @import("std");
const expect = std.testing.expect;

const Codebase = @import("codebase.zig").Codebase;
const Entity = @import("ecs.zig").Entity;

fn parseFunction(codebase: *Codebase, _: []const u8) !Entity {
    return try codebase.ecs.create_entity(.{});
}

pub fn parse(codebase: *Codebase, source: []const u8) !Entity {
    const module = try codebase.ecs.create_entity(.{});
    if (source.len > 0) {
        switch (source[0]) {
            'f' => {
                _ = try parseFunction(codebase, source);
            },
            else => {
                std.debug.print("\nInvalid top level declaration {s}", .{source});
                unreachable;
            },
        }
    }
    return module;
}

test "parse int" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch @panic("MEMORY LEAK");
    const allocator = &gpa.allocator;
    var codebase = Codebase.init(allocator);
    defer codebase.deinit();
    const source = "fn main() u64: 0";
    _ = try parse(&codebase, source);
}
