const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const panic = std.debug.panic;

const Codebase = @import("codebase.zig").Codebase;
const Entity = @import("ecs.zig").Entity;

const Position = struct {
    column: u64,
    row: u64,
};

const Source = struct {
    code: []const u8,
    position: Position,

    fn init(code: []const u8) Source {
        return Source{
            .code = code,
            .position = Position{
                .column = 0,
                .row = 0,
            },
        };
    }
};

fn parseSymbol(source: *Source) []const u8 {
    var i: u64 = 0;
    while (i < source.code.len) : (i += 1) {
        switch (source.code[i]) {
            'a'...'z', 'A'...'Z', '0'...'9' => {},
            else => break,
        }
    }
    source.position.column += i;
    const symbol = source.code[0..i];
    source.code = source.code[i..];
    return symbol;
}

test "parse symbol" {
    var source = Source.init("fn main() u64: 0");
    const symbol = parseSymbol(&source);
    try expectEqualStrings("fn", symbol);
    try expectEqualStrings(" main() u64: 0", source.code);
    try expectEqual(Position{ .column = 2, .row = 0 }, source.position);
}

fn parseFunction(codebase: *Codebase, _: *Source) !Entity {
    return try codebase.ecs.createEntity(.{});
}

pub fn parse(codebase: *Codebase, code: []const u8) !Entity {
    var source = Source.init(code);
    const symbol = parseSymbol(&source);
    if (std.mem.eql(u8, symbol, "fn")) {
        _ = try parseFunction(codebase, &source);
    } else {
        panic("INVALID TOP LEVEL DECLARATION {s}", .{symbol});
    }
    return try codebase.ecs.createEntity(.{});
}

test "parse int" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch panic("MEMORY LEAK", .{});
    const allocator = &gpa.allocator;
    var codebase = Codebase.init(allocator);
    defer codebase.deinit();
    const code = "fn main() u64: 0";
    _ = try parse(&codebase, code);
}
