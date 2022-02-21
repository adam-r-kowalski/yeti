const std = @import("std");
const Arena = std.heap.ArenaAllocator;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const yeti = @import("yeti");
const initCodebase = yeti.initCodebase;
const tokenize = yeti.tokenize;
const parseExpression = yeti.parser.parseExpression;
const parseFunction = yeti.parser.parseFunction;
const parseImport = yeti.parser.parseImport;
const parse = yeti.parse;
const LOWEST = yeti.parser.LOWEST;
const components = yeti.components;
const literalOf = yeti.test_utils.literalOf;

test "parse symbol" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code = "foo";
    var tokens = try tokenize(module, code);
    const entity = try parseExpression(codebase, &tokens, LOWEST);
    try expectEqual(entity.get(components.AstKind), .symbol);
    try expectEqualStrings(literalOf(entity), "foo");
    try expectEqual(entity.get(components.Span), .{
        .begin = .{ .column = 0, .row = 0 },
        .end = .{ .column = 3, .row = 0 },
    });
}

test "parse int" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code = "35";
    var tokens = try tokenize(module, code);
    const entity = try parseExpression(codebase, &tokens, LOWEST);
    try expectEqual(entity.get(components.AstKind), .int);
    try expectEqualStrings(literalOf(entity), "35");
    try expectEqual(entity.get(components.Span), .{
        .begin = .{ .column = 0, .row = 0 },
        .end = .{ .column = 2, .row = 0 },
    });
}

test "parse float" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code = "35.3";
    var tokens = try tokenize(module, code);
    const entity = try parseExpression(codebase, &tokens, LOWEST);
    try expectEqual(entity.get(components.AstKind), .float);
    try expectEqualStrings(literalOf(entity), "35.3");
    try expectEqual(entity.get(components.Span), .{
        .begin = .{ .column = 0, .row = 0 },
        .end = .{ .column = 4, .row = 0 },
    });
}

test "parse function with int literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code = "fn(): u64 0 end";
    var tokens = try tokenize(module, code);
    const function = try parseFunction(codebase, &tokens);
    try expectEqual(function.get(components.AstKind), .function);
    try expectEqual(function.get(components.Span), .{
        .begin = .{ .row = 0, .column = 0 },
        .end = .{ .row = 0, .column = 15 },
    });
    try expectEqual(function.get(components.Parameters).slice().len, 0);
    const return_type = function.get(components.ReturnTypeAst).entity;
    try expectEqual(return_type.get(components.AstKind), .symbol);
    try expectEqualStrings(literalOf(return_type), "u64");
    try expectEqual(return_type.get(components.Span), .{
        .begin = .{ .row = 0, .column = 6 },
        .end = .{ .row = 0, .column = 9 },
    });
    const body = function.get(components.Body).slice();
    try expectEqual(body.len, 1);
    const zero = body[0];
    try expectEqual(zero.get(components.AstKind), .int);
    try expectEqualStrings(literalOf(zero), "0");
    try expectEqual(zero.get(components.Span), .{
        .begin = .{ .row = 0, .column = 10 },
        .end = .{ .row = 0, .column = 11 },
    });
}

test "parse function with binary entity" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code = "fn(): u64 5 + x end";
    var tokens = try tokenize(module, code);
    const function = try parseFunction(codebase, &tokens);
    try expectEqual(function.get(components.Parameters).slice().len, 0);
    try expectEqualStrings(literalOf(function.get(components.ReturnTypeAst).entity), "u64");
    const body = function.get(components.Body).slice();
    try expectEqual(body.len, 1);
    const add = body[0];
    try expectEqual(add.get(components.BinaryOp), .add);
    const arguments = add.get(components.Arguments).slice();
    try expectEqual(arguments.len, 2);
    try expectEqualStrings(literalOf(arguments[0]), "5");
    try expectEqualStrings(literalOf(arguments[1]), "x");
}

test "parse function with compound binary entity" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code = "fn(): u64 m * x + b end";
    var tokens = try tokenize(module, code);
    const function = try parseFunction(codebase, &tokens);
    try expectEqual(function.get(components.Parameters).slice().len, 0);
    const body = function.get(components.Body).slice();
    const add = body[0];
    try expectEqual(add.get(components.BinaryOp), .add);
    const add_arguments = add.get(components.Arguments).slice();
    try expectEqual(add_arguments.len, 2);
    const multiply = add_arguments[0];
    try expectEqual(multiply.get(components.BinaryOp), .multiply);
    const multiply_arguments = multiply.get(components.Arguments).slice();
    try expectEqual(multiply_arguments.len, 2);
    const m = multiply_arguments[0];
    try expectEqual(m.get(components.AstKind), .symbol);
    try expectEqualStrings(literalOf(m), "m");
    const x = multiply_arguments[1];
    try expectEqual(x.get(components.AstKind), .symbol);
    try expectEqualStrings(literalOf(x), "x");
    const b = add_arguments[1];
    try expectEqual(b.get(components.AstKind), .symbol);
    try expectEqualStrings(literalOf(b), "b");
}

test "parse function parameters" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code = "fn(x: u64, y: u64): u64 x + y end";
    var tokens = try tokenize(module, code);
    const function = try parseFunction(codebase, &tokens);
    const parameters = function.get(components.Parameters).slice();
    try expectEqual(parameters.len, 2);
    const param0 = parameters[0];
    try expectEqualStrings(literalOf(param0), "x");
    try expectEqualStrings(literalOf(param0.get(components.TypeAst).entity), "u64");
    const param1 = parameters[1];
    try expectEqualStrings(literalOf(param1), "y");
    try expectEqualStrings(literalOf(param1.get(components.TypeAst).entity), "u64");
    try expectEqualStrings(literalOf(function.get(components.ReturnTypeAst).entity), "u64");
    const body = function.get(components.Body).slice();
    try expectEqual(body.len, 1);
    const add = body[0];
    try expectEqual(add.get(components.BinaryOp), .add);
    const arguments = add.get(components.Arguments).slice();
    try expectEqualStrings(literalOf(arguments[0]), "x");
    try expectEqualStrings(literalOf(arguments[1]), "y");
}

test "parse function with newline" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\fn(x: u64, y: u64): u64
        \\  x + y
        \\end
    ;
    var tokens = try tokenize(module, code);
    const function = try parseFunction(codebase, &tokens);
    const parameters = function.get(components.Parameters).slice();
    try expectEqual(parameters.len, 2);
    const param0 = parameters[0];
    try expectEqualStrings(literalOf(param0), "x");
    try expectEqualStrings(literalOf(param0.get(components.TypeAst).entity), "u64");
    const param1 = parameters[1];
    try expectEqualStrings(literalOf(param1), "y");
    try expectEqualStrings(literalOf(param1.get(components.TypeAst).entity), "u64");
    const body = function.get(components.Body).slice();
    try expectEqual(body.len, 1);
    const add = body[0];
    try expectEqual(add.get(components.BinaryOp), .add);
    const arguments = add.get(components.Arguments).slice();
    try expectEqualStrings(literalOf(arguments[0]), "x");
    try expectEqualStrings(literalOf(arguments[1]), "y");
}

test "parse constant definition" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\fn(): u64
        \\  x = 5
        \\  y = 15
        \\  x + y
        \\end
    ;
    var tokens = try tokenize(module, code);
    const function = try parseFunction(codebase, &tokens);
    try expectEqualStrings(literalOf(function.get(components.ReturnTypeAst).entity), "u64");
    try expectEqual(function.get(components.Parameters).slice().len, 0);
    const body = function.get(components.Body).slice();
    try expectEqual(body.len, 3);
    const x = body[0];
    try expectEqual(x.get(components.AstKind), .define);
    try expectEqualStrings(literalOf(x.get(components.Name).entity), "x");
    try expectEqualStrings(literalOf(x.get(components.Value).entity), "5");
    const y = body[1];
    try expectEqual(y.get(components.AstKind), .define);
    try expectEqualStrings(literalOf(y.get(components.Name).entity), "y");
    try expectEqualStrings(literalOf(y.get(components.Value).entity), "15");
    const add = body[2];
    try expectEqual(add.get(components.BinaryOp), .add);
    const arguments = add.get(components.Arguments).slice();
    try expectEqual(arguments.len, 2);
    try expectEqualStrings(literalOf(arguments[0]), "x");
    try expectEqualStrings(literalOf(arguments[1]), "y");
}

test "parse constant definition with binary op" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\fn(x: u64, y: u64): u64
        \\  x2 = x * x
        \\  y2 = y * y
        \\  x2 + y2
        \\end
    ;
    var tokens = try tokenize(module, code);
    const function = try parseFunction(codebase, &tokens);
    try expectEqualStrings(literalOf(function.get(components.ReturnTypeAst).entity), "u64");
    const parameters = function.get(components.Parameters).slice();
    try expectEqual(parameters.len, 2);
    const param0 = parameters[0];
    try expectEqualStrings(literalOf(param0), "x");
    try expectEqualStrings(literalOf(param0.get(components.TypeAst).entity), "u64");
    const param1 = parameters[1];
    try expectEqualStrings(literalOf(param1), "y");
    try expectEqualStrings(literalOf(param1.get(components.TypeAst).entity), "u64");
    const body = function.get(components.Body).slice();
    try expectEqual(body.len, 3);
    {
        const x2 = body[0];
        try expectEqualStrings(literalOf(x2.get(components.Name).entity), "x2");
        const multiply = x2.get(components.Value).entity;
        try expectEqual(multiply.get(components.BinaryOp), .multiply);
        const arguments = multiply.get(components.Arguments).slice();
        try expectEqualStrings(literalOf(arguments[0]), "x");
        try expectEqualStrings(literalOf(arguments[1]), "x");
    }
    {
        const y2 = body[1];
        try expectEqualStrings(literalOf(y2.get(components.Name).entity), "y2");
        const multiply = y2.get(components.Value).entity;
        try expectEqual(multiply.get(components.BinaryOp), .multiply);
        const arguments = multiply.get(components.Arguments).slice();
        try expectEqualStrings(literalOf(arguments[0]), "y");
        try expectEqualStrings(literalOf(arguments[1]), "y");
    }
    const add = body[2];
    try expectEqual(add.get(components.BinaryOp), .add);
    const arguments = add.get(components.Arguments).slice();
    try expectEqualStrings(literalOf(arguments[0]), "x2");
    try expectEqualStrings(literalOf(arguments[1]), "y2");
}

test "parse function call" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\fn(x: u64, y: u64): u64
        \\  square(x) + square(y)
        \\end
    ;
    var tokens = try tokenize(module, code);
    const function = try parseFunction(codebase, &tokens);
    try expectEqualStrings(literalOf(function.get(components.ReturnTypeAst).entity), "u64");
    const parameters = function.get(components.Parameters).slice();
    try expectEqual(parameters.len, 2);
    const param0 = parameters[0];
    try expectEqualStrings(literalOf(param0), "x");
    try expectEqualStrings(literalOf(param0.get(components.TypeAst).entity), "u64");
    const param1 = parameters[1];
    try expectEqualStrings(literalOf(param1), "y");
    try expectEqualStrings(literalOf(param1.get(components.TypeAst).entity), "u64");
    const body = function.get(components.Body).slice();
    try expectEqual(body.len, 1);
    const add = body[0];
    try expectEqual(add.get(components.BinaryOp), .add);
    const add_arguments = add.get(components.Arguments).slice();
    {
        const call = add_arguments[0];
        try expectEqual(call.get(components.AstKind), .call);
        try expectEqualStrings(literalOf(call.get(components.Callable).entity), "square");
        const arguments = call.get(components.Arguments).slice();
        try expectEqual(arguments.len, 1);
        try expectEqualStrings(literalOf(arguments[0]), "x");
    }
    {
        const call = add_arguments[1];
        try expectEqual(call.get(components.AstKind), .call);
        try expectEqualStrings(literalOf(call.get(components.Callable).entity), "square");
        const arguments = call.get(components.Arguments).slice();
        try expectEqual(arguments.len, 1);
        try expectEqualStrings(literalOf(arguments[0]), "y");
    }
}

test "parse function call with multiple arguments" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\fn(): u64
        \\  sum_of_squares(10, 56 * 3)
        \\end
    ;
    var tokens = try tokenize(module, code);
    const function = try parseFunction(codebase, &tokens);
    try expectEqualStrings(literalOf(function.get(components.ReturnTypeAst).entity), "u64");
    try expectEqual(function.get(components.Parameters).slice().len, 0);
    const body = function.get(components.Body).slice();
    try expectEqual(body.len, 1);
    const call = body[0];
    try expectEqualStrings(literalOf(call.get(components.Callable).entity), "sum_of_squares");
    const call_arguments = call.get(components.Arguments).slice();
    try expectEqual(call_arguments.len, 2);
    try expectEqualStrings(literalOf(call_arguments[0]), "10");
    const multiply = call_arguments[1];
    try expectEqual(multiply.get(components.BinaryOp), .multiply);
    const arguments = multiply.get(components.Arguments).slice();
    try expectEqualStrings(literalOf(arguments[0]), "56");
    try expectEqualStrings(literalOf(arguments[1]), "3");
}

test "parse import module" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\import("foo.yeti")
    ;
    var tokens = try tokenize(module, code);
    const import = try parseImport(codebase, &tokens);
    try expectEqualStrings(literalOf(import.get(components.Path).entity), "foo.yeti");
}

test "parse two functions" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\sum_of_squares(x: u64, y: u64): u64 {
        \\  x*2 + y*2
        \\}
        \\
        \\start(): u64 {
        \\  sum_of_squares(10, 56 * 3)
        \\}
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    {
        const sum_of_squares = module.get(components.TopLevel).findString("sum_of_squares");
        const overloads = sum_of_squares.get(components.Overloads).slice();
        try expectEqual(overloads.len, 1);
        try expectEqual(overloads[0].get(components.Parameters).slice().len, 2);
    }
    {
        const start = module.get(components.TopLevel).findString("start");
        const overloads = start.get(components.Overloads).slice();
        try expectEqual(overloads.len, 1);
        try expectEqual(overloads[0].get(components.Parameters).slice().len, 0);
    }
}

test "parse overload" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\id(x: u64): u64 { x }
        \\
        \\id(x: f64): f64 { x }
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const id = module.get(components.TopLevel).findString("id");
    const overloads = id.get(components.Overloads).slice();
    try expectEqual(overloads.len, 2);
    {
        const id_u64 = overloads[0];
        const parameters = id_u64.get(components.Parameters).slice();
        try expectEqual(parameters.len, 1);
        const x = parameters[0];
        try expectEqualStrings(literalOf(x), "x");
        try expectEqualStrings(literalOf(x.get(components.TypeAst).entity), "u64");
        try expectEqualStrings(literalOf(id_u64.get(components.ReturnTypeAst).entity), "u64");
    }
    {
        const id_f64 = overloads[1];
        const parameters = id_f64.get(components.Parameters).slice();
        try expectEqual(parameters.len, 1);
        const x = parameters[0];
        try expectEqualStrings(literalOf(x), "x");
        try expectEqualStrings(literalOf(x.get(components.TypeAst).entity), "f64");
        try expectEqualStrings(literalOf(id_f64.get(components.ReturnTypeAst).entity), "f64");
    }
}

test "parse import and function" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\math = import("math.yeti")
        \\
        \\start(): u64 {
        \\  math.sum_of_squares(10, 56 * 3)
        \\}
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const math = top_level.findString("math");
    try expectEqual(math.get(components.AstKind), .import);
    try expectEqualStrings(literalOf(math.get(components.Path).entity), "math.yeti");
    const start = top_level.findString("start");
    const overloads = start.get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const body = overloads[0].get(components.Body).slice();
    try expectEqual(body.len, 1);
    const dot = body[0];
    try expectEqual(dot.get(components.AstKind), .binary_op);
    const dot_arguments = dot.get(components.Arguments).slice();
    try expectEqualStrings(literalOf(dot_arguments[0]), "math");
    const sum_of_squares = dot_arguments[1];
    const callable = sum_of_squares.get(components.Callable).entity;
    try expectEqualStrings(literalOf(callable), "sum_of_squares");
    const sum_of_squares_arguments = sum_of_squares.get(components.Arguments).slice();
    try expectEqualStrings(literalOf(sum_of_squares_arguments[0]), "10");
    const multiply = sum_of_squares_arguments[1];
    try expectEqual(multiply.get(components.BinaryOp), .multiply);
    const arguments = multiply.get(components.Arguments).slice();
    try expectEqualStrings(literalOf(arguments[0]), "56");
    try expectEqualStrings(literalOf(arguments[1]), "3");
}

test "parse char literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\start(): u8 {
        \\  'h'
        \\}
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const overloads = top_level.findString("start").get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const start = overloads[0];
    const return_type = start.get(components.ReturnTypeAst).entity;
    try expectEqual(return_type.get(components.AstKind), .symbol);
    try expectEqualStrings(literalOf(return_type), "u8");
    const body = overloads[0].get(components.Body).slice();
    try expectEqual(body.len, 1);
    const h = body[0];
    try expectEqual(h.get(components.AstKind), .char);
    try expectEqualStrings(literalOf(h), "h");
}

test "parse new function syntax" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\start(): u64 {
        \\  0
        \\}
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const overloads = top_level.findString("start").get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const start = overloads[0];
    const return_type = start.get(components.ReturnTypeAst).entity;
    try expectEqual(return_type.get(components.AstKind), .symbol);
    try expectEqualStrings(literalOf(return_type), "u64");
    const body = overloads[0].get(components.Body).slice();
    try expectEqual(body.len, 1);
    const zero = body[0];
    try expectEqual(zero.get(components.AstKind), .int);
    try expectEqualStrings(literalOf(zero), "0");
}
