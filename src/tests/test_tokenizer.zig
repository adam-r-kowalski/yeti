const std = @import("std");
const Arena = std.heap.ArenaAllocator;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const yeti = @import("yeti");
const initCodebase = yeti.initCodebase;
const tokenize = yeti.tokenize;
const components = yeti.components;
const literalOf = yeti.test_utils.literalOf;

test "tokenize symbol" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code = "foo bar? _baz_";
    var tokens = try tokenize(module, code);
    {
        const token = tokens.peek().?;
        try expectEqual(token.get(components.TokenKind), .symbol);
        try expectEqualStrings(literalOf(token), "foo");
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 0, .row = 0 },
            .end = .{ .column = 3, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .symbol);
        try expectEqualStrings(literalOf(token), "foo");
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 0, .row = 0 },
            .end = .{ .column = 3, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .symbol);
        try expectEqualStrings(literalOf(token), "bar?");
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 4, .row = 0 },
            .end = .{ .column = 8, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .symbol);
        try expectEqualStrings(literalOf(token), "_baz_");
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 9, .row = 0 },
            .end = .{ .column = 14, .row = 0 },
        });
    }
    try expectEqual(tokens.next(), null);
}

test "tokenize number" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code = "100 -324 3.25 .73 5.3.2";
    var tokens = try tokenize(module, code);
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .int);
        try expectEqualStrings(literalOf(token), "100");
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 0, .row = 0 },
            .end = .{ .column = 3, .row = 0 },
        });
        try expectEqual(token.has(components.Error), null);
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .int);
        try expectEqualStrings(literalOf(token), "-324");
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 4, .row = 0 },
            .end = .{ .column = 8, .row = 0 },
        });
        try expectEqual(token.has(components.Error), null);
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .float);
        try expectEqualStrings(literalOf(token), "3.25");
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 9, .row = 0 },
            .end = .{ .column = 13, .row = 0 },
        });
        try expectEqual(token.has(components.Error), null);
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .float);
        try expectEqualStrings(literalOf(token), ".73");
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 14, .row = 0 },
            .end = .{ .column = 17, .row = 0 },
        });
        try expectEqual(token.has(components.Error), null);
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .float);
        try expectEqualStrings(literalOf(token), "5.3.2");
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 18, .row = 0 },
            .end = .{ .column = 23, .row = 0 },
        });
        const error_component = token.get(components.Error);
        try expectEqualStrings(error_component.header, "TOKENIZER ERROR");
        try expectEqualStrings(error_component.body, "Number should not have more than 1 decimal.");
        try expectEqual(error_component.span, .{
            .begin = .{ .column = 18, .row = 0 },
            .end = .{ .column = 23, .row = 0 },
        });
        try expectEqualStrings(error_component.hint, "Remove the additional decimals.");
    }
    try expectEqual(tokens.next(), null);
}

test "tokenize string" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\"hello" "world"
    ;
    var tokens = try tokenize(module, code);
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .string);
        try expectEqualStrings(literalOf(token), "hello");
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 0, .row = 0 },
            .end = .{ .column = 7, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .string);
        try expectEqualStrings(literalOf(token), "world");
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 8, .row = 0 },
            .end = .{ .column = 15, .row = 0 },
        });
    }
    try expectEqual(tokens.next(), null);
}

test "tokenize char" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\'h' 'w'
    ;
    var tokens = try tokenize(module, code);
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .char);
        try expectEqualStrings(literalOf(token), "h");
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 0, .row = 0 },
            .end = .{ .column = 3, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .char);
        try expectEqualStrings(literalOf(token), "w");
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 4, .row = 0 },
            .end = .{ .column = 7, .row = 0 },
        });
    }
    try expectEqual(tokens.next(), null);
}

test "tokenize new function syntax" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code = "start(): u64 { 0 }";
    var tokens = try tokenize(module, code);
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .symbol);
        try expectEqualStrings(literalOf(token), "start");
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 0, .row = 0 },
            .end = .{ .column = 5, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .left_paren);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 5, .row = 0 },
            .end = .{ .column = 6, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .right_paren);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 6, .row = 0 },
            .end = .{ .column = 7, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .colon);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 7, .row = 0 },
            .end = .{ .column = 8, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .symbol);
        try expectEqualStrings(literalOf(token), "u64");
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 9, .row = 0 },
            .end = .{ .column = 12, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .left_brace);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 13, .row = 0 },
            .end = .{ .column = 14, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .int);
        try expectEqualStrings(literalOf(token), "0");
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 15, .row = 0 },
            .end = .{ .column = 16, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .right_brace);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 17, .row = 0 },
            .end = .{ .column = 18, .row = 0 },
        });
    }
    try expectEqual(tokens.next(), null);
}

test "tokenize function" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code = "start = fn(): u64 0 end";
    var tokens = try tokenize(module, code);
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .symbol);
        try expectEqualStrings(literalOf(token), "start");
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 0, .row = 0 },
            .end = .{ .column = 5, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .equal);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 6, .row = 0 },
            .end = .{ .column = 7, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .fn_);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 8, .row = 0 },
            .end = .{ .column = 10, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .left_paren);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 10, .row = 0 },
            .end = .{ .column = 11, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .right_paren);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 11, .row = 0 },
            .end = .{ .column = 12, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .colon);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 12, .row = 0 },
            .end = .{ .column = 13, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .symbol);
        try expectEqualStrings(literalOf(token), "u64");
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 14, .row = 0 },
            .end = .{ .column = 17, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .int);
        try expectEqualStrings(literalOf(token), "0");
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 18, .row = 0 },
            .end = .{ .column = 19, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .end);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 20, .row = 0 },
            .end = .{ .column = 23, .row = 0 },
        });
    }
    try expectEqual(tokens.next(), null);
}

test "tokenize multine function" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\f = fn(): u64
        \\  x = 5
        \\  y = 15
        \\  x + y
        \\end
    ;
    var tokens = try tokenize(module, code);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .equal);
    try expectEqual(tokens.next().?.get(components.TokenKind), .fn_);
    try expectEqual(tokens.next().?.get(components.TokenKind), .left_paren);
    try expectEqual(tokens.next().?.get(components.TokenKind), .right_paren);
    try expectEqual(tokens.next().?.get(components.TokenKind), .colon);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .new_line);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 13, .row = 0 },
            .end = .{ .column = 0, .row = 1 },
        });
    }
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .equal);
    try expectEqual(tokens.next().?.get(components.TokenKind), .int);
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .new_line);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 7, .row = 1 },
            .end = .{ .column = 0, .row = 2 },
        });
    }
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .equal);
    try expectEqual(tokens.next().?.get(components.TokenKind), .int);
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .new_line);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 8, .row = 2 },
            .end = .{ .column = 0, .row = 3 },
        });
    }
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .plus);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .new_line);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 7, .row = 3 },
            .end = .{ .column = 0, .row = 4 },
        });
    }
    try expectEqual(tokens.next().?.get(components.TokenKind), .end);
    try expectEqual(tokens.next(), null);
}

test "tokenize mulitine function with binary op" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\sum_of_squares = fn(x: u64, y: u64): u64
        \\  x2 = x * x
        \\  x2 = y * y
        \\  x2 + y2
        \\end
    ;
    var tokens = try tokenize(module, code);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .equal);
    try expectEqual(tokens.next().?.get(components.TokenKind), .fn_);
    try expectEqual(tokens.next().?.get(components.TokenKind), .left_paren);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .colon);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .comma);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .colon);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .right_paren);
    try expectEqual(tokens.next().?.get(components.TokenKind), .colon);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .new_line);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .equal);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .times);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .new_line);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .equal);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .times);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .new_line);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .plus);
    try expectEqual(tokens.next().?.get(components.TokenKind), .symbol);
    try expectEqual(tokens.next().?.get(components.TokenKind), .new_line);
    try expectEqual(tokens.next().?.get(components.TokenKind), .end);
    try expectEqual(tokens.next(), null);
}

test "greater operators" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code = "> >= = == : < <= >> <<";
    var tokens = try tokenize(module, code);
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .greater_than);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 0, .row = 0 },
            .end = .{ .column = 1, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .greater_equal);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 2, .row = 0 },
            .end = .{ .column = 4, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .equal);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 5, .row = 0 },
            .end = .{ .column = 6, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .equal_equal);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 7, .row = 0 },
            .end = .{ .column = 9, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .colon);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 10, .row = 0 },
            .end = .{ .column = 11, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .less_than);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 12, .row = 0 },
            .end = .{ .column = 13, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .less_equal);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 14, .row = 0 },
            .end = .{ .column = 16, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .greater_greater);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 17, .row = 0 },
            .end = .{ .column = 19, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .less_less);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 20, .row = 0 },
            .end = .{ .column = 22, .row = 0 },
        });
    }
    try expectEqual(tokens.next(), null);
}

test "tokenize uniform function call syntax" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code = "10.min(20)";
    var tokens = try tokenize(module, code);
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .int);
        try expectEqualStrings(literalOf(token), "10");
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 0, .row = 0 },
            .end = .{ .column = 2, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .dot);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 2, .row = 0 },
            .end = .{ .column = 3, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .symbol);
        try expectEqualStrings(literalOf(token), "min");
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 3, .row = 0 },
            .end = .{ .column = 6, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .left_paren);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 6, .row = 0 },
            .end = .{ .column = 7, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .int);
        try expectEqualStrings(literalOf(token), "20");
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 7, .row = 0 },
            .end = .{ .column = 9, .row = 0 },
        });
    }
    {
        const token = tokens.next().?;
        try expectEqual(token.get(components.TokenKind), .right_paren);
        try expectEqual(token.get(components.Span), .{
            .begin = .{ .column = 9, .row = 0 },
            .end = .{ .column = 10, .row = 0 },
        });
    }
    try expectEqual(tokens.next(), null);
}
