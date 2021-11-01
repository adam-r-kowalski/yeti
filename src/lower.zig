const std = @import("std");
const eql = std.meta.eql;
const Allocator = std.mem.Allocator;
const Arena = std.heap.ArenaAllocator;
const assert = std.debug.assert;
const panic = std.debug.panic;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const init_codebase = @import("init_codebase.zig");
const initCodebase = init_codebase.initCodebase;
const initBuiltins = init_codebase.initBuiltins;
const List = @import("list.zig").List;
const ecs = @import("ecs.zig");
const Entity = ecs.Entity;
const ECS = ecs.ECS;
const strings = @import("strings.zig");
const Strings = strings.Strings;
const InternedString = strings.InternedString;
const tokenize = @import("tokenizer.zig").tokenize;
const parse = @import("parser.zig").parse;
const file_system = @import("file_system.zig");
const FileSystem = file_system.FileSystem;
const initFileSystem = file_system.initFileSystem;
const read = file_system.read;
const newFile = file_system.newFile;
const components = @import("components.zig");
const test_utils = @import("test_utils.zig");
const literalOf = test_utils.literalOf;
const typeOf = test_utils.typeOf;

const Context = struct {
    allocator: *Allocator,
    codebase: *ECS,
    fs: ECS,
    ast: Entity,
    function: Entity,
};

// NOTE:should this take in the active scopes for the current function?
fn lowerSymbol(context: Context, entity: Entity) !Entity {
    // TODO:lookup symbol from local variables of current function
    const literal = entity.get(components.Literal);
    const global_scope = context.codebase.get(components.Scope);
    if (global_scope.hasLiteral(literal)) |global| {
        return global;
    }
    // TODO:lookup symbol from cached ir module component
    const top_level_scope = context.ast.get(components.TopLevel);
    if (top_level_scope.hasLiteral(literal)) |top_level| {
        const kind = top_level.get(components.AstKind);
        switch (kind) {
            .import => {
                const module_name = literalOf(top_level.get(components.Path).entity);
                const contents = read(context.fs, module_name);
                var tokens = try tokenize(context.codebase, contents);
                // TODO:cache the ast into ir module component
                return try parse(context.codebase, &tokens);
            },
            else => panic("\nlowerSumbol unspported top level kind {}\n", .{kind}),
        }
    }
    panic("\nlowerSymbol failed for symbol {s}\n", .{literalOf(entity)});
}

fn lowerDot(context: Context, entity: Entity) !Entity {
    const dot_arguments = entity.get(components.Arguments).slice();
    const ast = try lowerExpression(context, dot_arguments[0]);
    assert(eql(typeOf(ast), context.codebase.get(components.Builtins).Module));
    const call = dot_arguments[1];
    assert(call.get(components.AstKind) == .call);
    const callable = call.get(components.Callable).entity;
    assert(callable.get(components.AstKind) == .symbol);
    // TODO: check if this function has already been lowered for these parameter types
    const top_level = ast.get(components.TopLevel);
    const literal = callable.get(components.Literal);
    const overloads = top_level.findLiteral(literal).get(components.Overloads).slice();
    assert(overloads.len == 1);
    const function = overloads[0];
    const new_context = Context{
        .allocator = context.allocator,
        .codebase = context.codebase,
        .fs = context.fs,
        .ast = ast,
        .function = function,
    };
    assert(new_context.function.get(components.Parameters).entities.len == 0);
    try lowerFunction(new_context);
    const function_arguments = call.get(components.Arguments).slice();
    for (function_arguments) |argument| {
        _ = try lowerExpression(context, argument);
    }
    // TODO: add a new expression to basic block which calls the function with the ast arguments
    const return_type = function.get(components.ReturnType).entity;
    return try context.codebase.createEntity(.{components.Type.init(return_type)});
}

fn lowerBinaryOp(context: Context, entity: Entity) !Entity {
    const binary_op = entity.get(components.BinaryOp);
    return switch (binary_op) {
        .dot => lowerDot(context, entity),
        else => panic("\nlowerBinaryOp unsupported binary op {}\n", .{binary_op}),
    };
}

fn lowerExpression(context: Context, entity: Entity) error{OutOfMemory}!Entity {
    const kind = entity.get(components.AstKind);
    return switch (kind) {
        .symbol => try lowerSymbol(context, entity),
        .int => entity,
        .binary_op => try lowerBinaryOp(context, entity),
        else => panic("\nlowerExpression unsupported kind {}\n", .{kind}),
    };
}

fn lowerFunctionParameters(context: Context) !void {
    const parameters = context.function.get(components.Parameters).slice();
    for (parameters) |parameter| {
        const parameter_type = try lowerExpression(context, parameter.get(components.TypeAst).entity);
        _ = try parameter.set(.{components.Type.init(parameter_type)});
    }
}

fn lowerFunctionReturnType(context: Context) !void {
    const return_type = try lowerExpression(context, context.function.get(components.ReturnTypeAst).entity);
    _ = try context.function.set(.{components.ReturnType.init(return_type)});
}

fn lowerFunctionBody(context: Context) !void {
    const body = context.function.get(components.Body).slice();
    for (body) |expression| {
        _ = try lowerExpression(context, expression);
    }
}

fn lowerFunction(context: Context) !void {
    try lowerFunctionParameters(context);
    try lowerFunctionReturnType(context);
    try lowerFunctionBody(context);
}

pub fn lower(codebase: *ECS, fs: ECS, module_name: []const u8, function_name: []const u8) !Entity {
    try initBuiltins(codebase);
    const contents = read(fs, module_name);
    var tokens = try tokenize(codebase, contents);
    const ast = try parse(codebase, &tokens);
    const top_level = ast.get(components.TopLevel);
    const overloads = top_level.findString(function_name).get(components.Overloads).slice();
    assert(overloads.len == 1);
    const context = Context{
        .allocator = &codebase.arena.allocator,
        .codebase = codebase,
        .fs = fs,
        .ast = ast,
        .function = overloads[0],
    };
    try lowerFunction(context);
    return ast;
}

test "call function from import" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try initFileSystem(&arena);
    _ = try newFile(&fs, "foo.yeti",
        \\bar = import("bar.yeti")
        \\
        \\start = function(): I64
        \\  bar.baz()
        \\end
    );
    _ = try newFile(&fs, "bar.yeti",
        \\baz = function(): I64
        \\  10
        \\end
    );
    const ir = try lower(codebase, fs, "foo.yeti", "start");
    const builtins = codebase.get(components.Builtins);
    const top_level = ir.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.I64);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 1);
    // TODO: the body should a function call whose callable component is baz from the bar module
}
