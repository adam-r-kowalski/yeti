const std = @import("std");
const Allocator = std.mem.Allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const panic = std.debug.panic;

const Codebase = @import("codebase.zig").Codebase;
const Entity = @import("ecs.zig").Entity;
const List = @import("list.zig").List;
const components = @import("components.zig");

const Source = struct {
    code: []const u8,
    position: components.Position,

    fn init(code: []const u8) Source {
        return Source{
            .code = code,
            .position = components.Position{
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
            'a'...'z', 'A'...'Z', '0'...'9', '_' => {},
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
    try expectEqual(components.Position{ .column = 2, .row = 0 }, source.position);
}

fn trimWhitespace(source: *Source) void {
    var i: u64 = 0;
    while (i < source.code.len and source.code[i] == ' ') : (i += 1) {}
    source.position.column += i;
    source.code = source.code[i..];
}

test "trim whitespace" {
    var source = Source.init(" main() u64: 0");
    trimWhitespace(&source);
    try expectEqualStrings("main() u64: 0", source.code);
    try expectEqual(components.Position{ .column = 1, .row = 0 }, source.position);
}

fn parseFunction(codebase: *Codebase, source: *Source) !Entity {
    trimWhitespace(source);
    const name = components.Name{ .value = parseSymbol(source) };
    return try codebase.ecs.createEntity(.{name});
}

pub fn parse(codebase: *Codebase, code: []const u8) !Entity {
    var source = Source.init(code);
    const symbol = parseSymbol(&source);
    var functions = components.Functions{ .entities = List(Entity).init(codebase.allocator) };
    if (std.mem.eql(u8, symbol, "fn")) {
        const function = try parseFunction(codebase, &source);
        try functions.entities.push(function);
    } else {
        panic("INVALID TOP LEVEL DECLARATION {s}", .{symbol});
    }
    return try codebase.ecs.createEntity(.{functions});
}

test "parse int" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch panic("MEMORY LEAK", .{});
    const allocator = &gpa.allocator;
    var codebase = Codebase.init(allocator);
    defer codebase.deinit();
    const code = "fn main() u64: 0";
    const module = try parse(&codebase, code);
    var functions = module.get(components.Functions).?.entities.iterate();
    const function = functions.next().?;
    try expectEqualStrings(function.get(components.Name).?.value, "main");
    try expectEqual(functions.next(), null);
}
