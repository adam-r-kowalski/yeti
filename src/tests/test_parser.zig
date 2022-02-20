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

test "parse define int literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\start(): u64 {
        \\  x = 10
        \\  x
        \\}
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start");
    const overloads = start.get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const body = overloads[0].get(components.Body).slice();
    try expectEqual(body.len, 2);
    const define = body[0];
    try expectEqual(define.get(components.AstKind), .define);
    try expectEqualStrings(literalOf(define.get(components.Name).entity), "x");
    try expectEqualStrings(literalOf(define.get(components.Value).entity), "10");
    const x = body[1];
    try expectEqual(x.get(components.AstKind), .symbol);
    try expectEqualStrings(literalOf(x), "x");
}

test "parse define with explicit type" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\start(): u64 {
        \\  x: u64 = 10
        \\  x
        \\}
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start");
    const overloads = start.get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const body = overloads[0].get(components.Body).slice();
    try expectEqual(body.len, 2);
    const define = body[0];
    try expectEqual(define.get(components.AstKind), .define);
    try expectEqualStrings(literalOf(define.get(components.Name).entity), "x");
    try expectEqualStrings(literalOf(define.get(components.Value).entity), "10");
    try expectEqualStrings(literalOf(define.get(components.TypeAst).entity), "u64");
    const x = body[1];
    try expectEqual(x.get(components.AstKind), .symbol);
    try expectEqualStrings(literalOf(x), "x");
}

test "parse grouping with parenthesis" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\start(): u64 {
        \\  (5 + 10) * 3
        \\}
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start");
    const overloads = start.get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const body = overloads[0].get(components.Body).slice();
    try expectEqual(body.len, 1);
    const multiply = body[0];
    try expectEqual(multiply.get(components.AstKind), .binary_op);
    try expectEqual(multiply.get(components.BinaryOp), .multiply);
    const multiply_arguments = multiply.get(components.Arguments).slice();
    const add = multiply_arguments[0];
    try expectEqual(add.get(components.AstKind), .binary_op);
    try expectEqual(add.get(components.BinaryOp), .add);
    const add_arguments = add.get(components.Arguments).slice();
    try expectEqualStrings(literalOf(add_arguments[0]), "5");
    try expectEqualStrings(literalOf(add_arguments[1]), "10");
    try expectEqualStrings(literalOf(multiply_arguments[1]), "3");
}

test "parse if then else" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\start(): u64 {
        \\  if 10 > 5 { 20 } else { 30 }
        \\}
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start");
    const overloads = start.get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const body = overloads[0].get(components.Body).slice();
    try expectEqual(body.len, 1);
    const if_ = body[0];
    try expectEqual(if_.get(components.AstKind), .if_);
    const conditional = if_.get(components.Conditional).entity;
    try expectEqual(conditional.get(components.AstKind), .binary_op);
    try expectEqual(conditional.get(components.BinaryOp), .greater_than);
    const then = if_.get(components.Then).slice();
    try expectEqual(then.len, 1);
    try expectEqualStrings(literalOf(then[0]), "20");
    const else_ = if_.get(components.Else).slice();
    try expectEqual(else_.len, 1);
    try expectEqualStrings(literalOf(else_[0]), "30");
}

test "parse multiline if then else" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\start(): u64 {
        \\  if 10 > 5 {
        \\    x = 20
        \\    x
        \\  } else {
        \\    y = 30
        \\    y
        \\  }
        \\}
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start");
    const overloads = start.get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const body = overloads[0].get(components.Body).slice();
    try expectEqual(body.len, 1);
    const if_ = body[0];
    try expectEqual(if_.get(components.AstKind), .if_);
    const conditional = if_.get(components.Conditional).entity;
    try expectEqual(conditional.get(components.AstKind), .binary_op);
    try expectEqual(conditional.get(components.BinaryOp), .greater_than);
    const then = if_.get(components.Then).slice();
    try expectEqual(then.len, 2);
    {
        const define = then[0];
        try expectEqual(define.get(components.AstKind), .define);
        try expectEqualStrings(literalOf(define.get(components.Name).entity), "x");
        try expectEqualStrings(literalOf(define.get(components.Value).entity), "20");
        const x = then[1];
        try expectEqual(x.get(components.AstKind), .symbol);
        try expectEqualStrings(literalOf(x), "x");
    }
    const else_ = if_.get(components.Else).slice();
    try expectEqual(else_.len, 2);
    {
        const define = else_[0];
        try expectEqual(define.get(components.AstKind), .define);
        try expectEqualStrings(literalOf(define.get(components.Name).entity), "y");
        try expectEqualStrings(literalOf(define.get(components.Value).entity), "30");
        const y = else_[1];
        try expectEqual(y.get(components.AstKind), .symbol);
        try expectEqualStrings(literalOf(y), "y");
    }
}

test "parse for loop" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\start(): i32 {
        \\  sum = 0
        \\  for i in 0:10 {
        \\      sum = sum + i
        \\  }
        \\  sum
        \\}
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start");
    const overloads = start.get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const body = overloads[0].get(components.Body).slice();
    try expectEqual(body.len, 3);
    const define = body[0];
    try expectEqual(define.get(components.AstKind), .define);
    try expectEqualStrings(literalOf(define.get(components.Name).entity), "sum");
    try expectEqualStrings(literalOf(define.get(components.Value).entity), "0");
    const for_ = body[1];
    try expectEqual(for_.get(components.AstKind), .for_);
    const iterator = for_.get(components.Iterator).entity;
    try expectEqual(iterator.get(components.AstKind), .range);
    const range = iterator.get(components.Range);
    try expectEqualStrings(literalOf(range.first), "0");
    try expectEqualStrings(literalOf(range.last), "10");
    const i = for_.get(components.LoopVariable).entity;
    try expectEqualStrings(literalOf(i), "i");
    const for_body = for_.get(components.Body).slice();
    try expectEqual(for_body.len, 1);
    const assign = for_body[0];
    try expectEqual(assign.get(components.AstKind), .define);
    try expectEqualStrings(literalOf(assign.get(components.Name).entity), "sum");
    const value = assign.get(components.Value).entity;
    try expectEqual(value.get(components.AstKind), .binary_op);
    try expectEqual(value.get(components.BinaryOp), .add);
    const sum = body[2];
    try expectEqual(sum.get(components.AstKind), .symbol);
    try expectEqualStrings(literalOf(sum), "sum");
}

test "parse pipeline" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\start(): i32 {
        \\  5 |> square()
        \\}
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start");
    const overloads = start.get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const body = overloads[0].get(components.Body).slice();
    try expectEqual(body.len, 1);
    const pipeline = body[0];
    try expectEqual(pipeline.get(components.AstKind), .binary_op);
    try expectEqual(pipeline.get(components.BinaryOp), .pipeline);
    const pipeline_arguments = pipeline.get(components.Arguments).slice();
    try expectEqual(pipeline_arguments.len, 2);
    const five = pipeline_arguments[0];
    try expectEqualStrings(literalOf(five), "5");
    const square = pipeline_arguments[1];
    try expectEqual(square.get(components.AstKind), .call);
    try expectEqualStrings(literalOf(square.get(components.Callable).entity), "square");
    const square_arguments = square.get(components.Arguments).slice();
    try expectEqual(square_arguments.len, 0);
}

test "parse foreign export" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code = "foreign_export(start)";
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const foreign_exports = module.get(components.ForeignExports).slice();
    try expectEqual(foreign_exports.len, 1);
    try expectEqualStrings(literalOf(foreign_exports[0]), "start");
}

test "parse foreign import" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\log = foreign_import("console", "log", Function(value: i64): void)
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const log = top_level.findString("log");
    const overloads = log.get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const function = overloads[0];
    try expectEqual(function.get(components.AstKind), .function);
    try expectEqualStrings(literalOf(function.get(components.ForeignModule).entity), "console");
    try expectEqualStrings(literalOf(function.get(components.ForeignName).entity), "log");
    const parameters = function.get(components.Parameters).slice();
    try expectEqual(parameters.len, 1);
    const parameter = parameters[0];
    try expectEqualStrings(literalOf(parameter), "value");
    try expectEqualStrings(literalOf(parameter.get(components.TypeAst).entity), "i64");
    try expectEqualStrings(literalOf(function.get(components.ReturnTypeAst).entity), "void");
}

test "parse pointer" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\start(ptr: *i32): i32 {
        \\  0
        \\}
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start");
    const overloads = start.get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const overload = overloads[0];
    const parameters = overload.get(components.Parameters).slice();
    try expectEqual(parameters.len, 1);
    const ptr = parameters[0];
    try expectEqualStrings(literalOf(ptr), "ptr");
    const type_of = ptr.get(components.TypeAst).entity;
    try expectEqual(type_of.get(components.AstKind), .pointer);
    try expectEqualStrings(literalOf(type_of.get(components.Value).entity), "i32");
    const body = overload.get(components.Body).slice();
    try expectEqual(body.len, 1);
    const zero = body[0];
    try expectEqual(zero.get(components.AstKind), .int);
    try expectEqualStrings(literalOf(zero), "0");
}

test "parse pointer load" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\start(ptr: *i32): i32 {
        \\  *ptr
        \\}
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start");
    const overloads = start.get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const overload = overloads[0];
    const parameters = overload.get(components.Parameters).slice();
    try expectEqual(parameters.len, 1);
    const ptr = parameters[0];
    try expectEqualStrings(literalOf(ptr), "ptr");
    const type_of = ptr.get(components.TypeAst).entity;
    try expectEqual(type_of.get(components.AstKind), .pointer);
    try expectEqualStrings(literalOf(type_of.get(components.Value).entity), "i32");
    const body = overload.get(components.Body).slice();
    try expectEqual(body.len, 1);
    const load = body[0];
    try expectEqual(load.get(components.AstKind), .pointer);
    const value = load.get(components.Value).entity;
    try expectEqual(value.get(components.AstKind), .symbol);
    try expectEqualStrings(literalOf(value), "ptr");
}

test "parse pointer load after new line" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\start(): i32 {
        \\  ptr = cast(*i32, 0)
        \\  *ptr
        \\}
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start");
    const overloads = start.get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const overload = overloads[0];
    const parameters = overload.get(components.Parameters).slice();
    try expectEqual(parameters.len, 0);
    const body = overload.get(components.Body).slice();
    try expectEqual(body.len, 2);
    const load = body[1];
    try expectEqual(load.get(components.AstKind), .pointer);
    const value = load.get(components.Value).entity;
    try expectEqual(value.get(components.AstKind), .symbol);
    try expectEqualStrings(literalOf(value), "ptr");
}

test "parse plus equal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\start(): u64 {
        \\  x = 10
        \\  x += 1
        \\  x
        \\}
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start");
    const overloads = start.get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const body = overloads[0].get(components.Body).slice();
    try expectEqual(body.len, 3);
    const define = body[0];
    try expectEqual(define.get(components.AstKind), .define);
    try expectEqualStrings(literalOf(define.get(components.Name).entity), "x");
    try expectEqualStrings(literalOf(define.get(components.Value).entity), "10");
    const plus_equal = body[1];
    try expectEqual(plus_equal.get(components.AstKind), .plus_equal);
    const arguments = plus_equal.get(components.Arguments).slice();
    try expectEqualStrings(literalOf(arguments[0]), "x");
    try expectEqualStrings(literalOf(arguments[1]), "1");
    const x = body[2];
    try expectEqual(x.get(components.AstKind), .symbol);
    try expectEqualStrings(literalOf(x), "x");
}

test "parse times equal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\start(): u64 {
        \\  x = 10
        \\  x *= 1
        \\  x
        \\}
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start");
    const overloads = start.get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const body = overloads[0].get(components.Body).slice();
    try expectEqual(body.len, 3);
    const define = body[0];
    try expectEqual(define.get(components.AstKind), .define);
    try expectEqualStrings(literalOf(define.get(components.Name).entity), "x");
    try expectEqualStrings(literalOf(define.get(components.Value).entity), "10");
    const times_equal = body[1];
    try expectEqual(times_equal.get(components.AstKind), .times_equal);
    const arguments = times_equal.get(components.Arguments).slice();
    try expectEqualStrings(literalOf(arguments[0]), "x");
    try expectEqualStrings(literalOf(arguments[1]), "1");
    const x = body[2];
    try expectEqual(x.get(components.AstKind), .symbol);
    try expectEqualStrings(literalOf(x), "x");
}

test "parse string literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\start(): []u8 {
        \\  "hello world"
        \\}
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const overloads = top_level.findString("start").get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const start = overloads[0];
    const return_type = start.get(components.ReturnTypeAst).entity;
    try expectEqual(return_type.get(components.AstKind), .array);
    try expectEqualStrings(literalOf(return_type.get(components.Value).entity), "u8");
    const body = overloads[0].get(components.Body).slice();
    try expectEqual(body.len, 1);
    const hello_world = body[0];
    try expectEqual(hello_world.get(components.AstKind), .string);
    try expectEqualStrings(literalOf(hello_world), "hello world");
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

test "parse array index" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\start(): u8 {
        \\  text = "hello world"
        \\  text[0]
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
    try expectEqual(body.len, 2);
    const define = body[0];
    try expectEqual(define.get(components.AstKind), .define);
    try expectEqualStrings(literalOf(define.get(components.Name).entity), "text");
    const hello_world = define.get(components.Value).entity;
    try expectEqual(hello_world.get(components.AstKind), .string);
    try expectEqualStrings(literalOf(hello_world), "hello world");
    const index = body[1];
    try expectEqual(index.get(components.AstKind), .index);
    const arguments = index.get(components.Arguments).slice();
    try expectEqual(arguments.len, 2);
    try expectEqualStrings(literalOf(arguments[0]), "text");
    try expectEqualStrings(literalOf(arguments[1]), "0");
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

test "parse new if syntax" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\min(x: i64, y: i64): i64 {
        \\  if x < y { x } else { y }
        \\}
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const overloads = top_level.findString("min").get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const min = overloads[0];
    const return_type = min.get(components.ReturnTypeAst).entity;
    try expectEqual(return_type.get(components.AstKind), .symbol);
    try expectEqualStrings(literalOf(return_type), "i64");
    const body = overloads[0].get(components.Body).slice();
    try expectEqual(body.len, 1);
    const if_ = body[0];
    try expectEqual(if_.get(components.AstKind), .if_);
    const conditional = if_.get(components.Conditional).entity;
    try expectEqual(conditional.get(components.AstKind), .binary_op);
    try expectEqual(conditional.get(components.BinaryOp), .less_than);
    const then = if_.get(components.Then).slice();
    try expectEqual(then.len, 1);
    try expectEqualStrings(literalOf(then[0]), "x");
    const else_ = if_.get(components.Else).slice();
    try expectEqual(else_.len, 1);
    try expectEqualStrings(literalOf(else_[0]), "y");
}

test "parse new for loop syntax" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\start(): i32 {
        \\  sum = 0
        \\  for i in 0:10 {
        \\    sum = sum + i
        \\  }
        \\  sum
        \\}
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start");
    const overloads = start.get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const body = overloads[0].get(components.Body).slice();
    try expectEqual(body.len, 3);
    const define = body[0];
    try expectEqual(define.get(components.AstKind), .define);
    try expectEqualStrings(literalOf(define.get(components.Name).entity), "sum");
    try expectEqualStrings(literalOf(define.get(components.Value).entity), "0");
    const for_ = body[1];
    try expectEqual(for_.get(components.AstKind), .for_);
    const iterator = for_.get(components.Iterator).entity;
    try expectEqual(iterator.get(components.AstKind), .range);
    const range = iterator.get(components.Range);
    try expectEqualStrings(literalOf(range.first), "0");
    try expectEqualStrings(literalOf(range.last), "10");
    const i = for_.get(components.LoopVariable).entity;
    try expectEqualStrings(literalOf(i), "i");
    const for_body = for_.get(components.Body).slice();
    try expectEqual(for_body.len, 1);
    const assign = for_body[0];
    try expectEqual(assign.get(components.AstKind), .define);
    try expectEqualStrings(literalOf(assign.get(components.Name).entity), "sum");
    const value = assign.get(components.Value).entity;
    try expectEqual(value.get(components.AstKind), .binary_op);
    try expectEqual(value.get(components.BinaryOp), .add);
    const sum = body[2];
    try expectEqual(sum.get(components.AstKind), .symbol);
    try expectEqualStrings(literalOf(sum), "sum");
}
