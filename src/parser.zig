const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
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

fn consume(source: *Source, expected: u8) void {
    assert(source.code.len > 0 and source.code[0] == expected);
    source.code = source.code[1..];
    source.position.column += 1;
}

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

fn parseNumber(codebase: *Codebase, source: *Source) !Entity {
    var i: usize = 0;
    while (i < source.code.len) : (i += 1) {
        switch (source.code[i]) {
            '0'...'9' => {},
            else => break,
        }
    }
    const interned = try codebase.strings.intern(source.code[0..i]);
    source.code = source.code[i..];
    source.position.column += i;
    const int = components.Int{ .interned = interned };
    const Type = components.Type{ .entity = codebase.builtins.U64 };
    return try codebase.ecs.createEntity(.{ int, Type });
}

fn parseExpression(codebase: *Codebase, source: *Source) !Entity {
    assert(source.code.len > 0);
    return switch (source.code[0]) {
        '0'...'9' => parseNumber(codebase, source),
        else => panic("INVALID EXPRESSION {}", .{source.code[0]}),
    };
}

fn intLiteral(codebase: Codebase, entity: Entity) []const u8 {
    return codebase.strings.get(entity.get(components.Int).?.interned).?;
}

test "parse expression" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch panic("MEMORY LEAK", .{});
    const allocator = &gpa.allocator;
    var codebase = try Codebase.init(allocator);
    defer codebase.deinit();
    var source = Source.init("0");
    const expression = try parseExpression(&codebase, &source);
    try expectEqualStrings(intLiteral(codebase, expression), "0");
    try expectEqual(expression.get(components.Type).?.entity, codebase.builtins.U64);
}

fn parseFunction(codebase: *Codebase, source: *Source) !Entity {
    trimWhitespace(source);
    const function_name = components.Name{ .interned = try codebase.strings.intern(parseSymbol(source)) };
    const parameters = components.Parameters.init(codebase.allocator);
    consume(source, '(');
    consume(source, ')');
    trimWhitespace(source);
    const return_type_name = components.Name{ .interned = try codebase.strings.intern(parseSymbol(source)) };
    const return_type_entity = try codebase.ecs.createEntity(.{return_type_name});
    const return_type = components.ReturnType{ .entity = return_type_entity };
    consume(source, ':');
    trimWhitespace(source);
    var body = components.Body.init(codebase.allocator);
    const body_entity = try parseExpression(codebase, source);
    try body.entities.push(body_entity);
    return try codebase.ecs.createEntity(.{
        function_name,
        parameters,
        return_type,
        body,
    });
}

pub fn parse(codebase: *Codebase, code: []const u8) !Entity {
    var source = Source.init(code);
    const symbol = parseSymbol(&source);
    var functions = components.Functions.init(codebase.allocator);
    if (std.mem.eql(u8, symbol, "fn")) {
        const function = try parseFunction(codebase, &source);
        try functions.entities.push(function);
    } else {
        panic("INVALID TOP LEVEL DECLARATION {s}", .{symbol});
    }
    return try codebase.ecs.createEntity(.{functions});
}

fn nameLiteral(codebase: Codebase, entity: Entity) []const u8 {
    return codebase.strings.get(entity.get(components.Name).?.interned).?;
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
    const function = functions.next().?.*;
    try expectEqualStrings(nameLiteral(codebase, function), "main");
    try expectEqual(function.get(components.Parameters).?.entities.len, 0);
    const return_type = function.get(components.ReturnType).?.entity;
    try expectEqualStrings(nameLiteral(codebase, return_type), "u64");
    try expectEqual(functions.next(), null);
}
