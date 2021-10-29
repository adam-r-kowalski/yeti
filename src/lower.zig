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
const literalOf = @import("test_utils.zig").literalOf;

fn builtinType(codebase: *ECS, scope: *components.ir.Scope, symbol: []const u8, Type: Entity) !Entity {
    const interned = try codebase.getPtr(Strings).intern(symbol);
    const entity = try codebase.createEntity(.{
        components.token.Literal.init(interned),
        components.ir.Type.init(Type),
    });
    try scope.put(interned, entity);
    return entity;
}

fn initBuiltins(codebase: *ECS) !void {
    var scope = components.ir.Scope.init(&codebase.arena.allocator, codebase.getPtr(Strings));
    const interned = try codebase.getPtr(Strings).intern("Type");
    const Type = try codebase.createEntity(.{
        components.token.Literal.init(interned),
    });
    try scope.put(interned, Type);
    _ = try Type.set(.{components.ir.Type.init(Type)});
    const Module = try builtinType(codebase, &scope, "Module", Type);
    const I64 = try builtinType(codebase, &scope, "I64", Type);
    const U64 = try builtinType(codebase, &scope, "U64", Type);
    const F64 = try builtinType(codebase, &scope, "F64", Type);
    const IntLiteral = try builtinType(codebase, &scope, "IntLiteral", Type);
    const FloatLiteral = try builtinType(codebase, &scope, "FloatLiteral", Type);
    const StringLiteral = try builtinType(codebase, &scope, "StringLiteral", Type);
    const builtins = components.ir.Builtins{
        .Type = Type,
        .Module = Module,
        .I64 = I64,
        .U64 = U64,
        .F64 = F64,
        .IntLiteral = IntLiteral,
        .FloatLiteral = FloatLiteral,
        .StringLiteral = StringLiteral,
    };
    try codebase.set(.{ builtins, scope });
}

fn typeOf(entity: Entity) Entity {
    return entity.get(components.ir.Type).entity;
}

test "builtins" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    try initBuiltins(&codebase);
    const builtins = codebase.get(components.ir.Builtins);
    const scope = codebase.get(components.ir.Scope);
    try expectEqualStrings(literalOf(builtins.Type), "Type");
    try expectEqual(typeOf(builtins.Type), builtins.Type);
    try expectEqual(scope.findString("Type"), builtins.Type);
    try expectEqual(scope.findLiteral(builtins.Type.get(components.token.Literal)), builtins.Type);
    try expectEqualStrings(literalOf(builtins.I64), "I64");
    try expectEqual(typeOf(builtins.I64), builtins.Type);
    try expectEqual(scope.findString("I64"), builtins.I64);
}

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
    const literal = entity.get(components.token.Literal);
    const global_scope = context.codebase.get(components.ir.Scope);
    if (global_scope.hasLiteral(literal)) |global| {
        return global;
    }
    // TODO:lookup symbol from cached ir module component
    const top_level_scope = context.ast.get(components.ast.TopLevel);
    if (top_level_scope.hasLiteral(literal)) |top_level| {
        const kind = top_level.get(components.ast.Kind);
        switch (kind) {
            .import => {
                const module_name = context.codebase.get(Strings).get(literal.interned);
                const contents = read(context.fs, module_name);
                var tokens = try tokenize(context.codebase, contents);
                // TODO:cache the ast into ir module component
                const ast = try parse(context.codebase, &tokens);
                // TODO:parse should set the type of the ast to module
                _ = try ast.set(.{components.ir.Type.init(context.codebase.get(components.ir.Builtins).Module)});
                return ast;
            },
            else => panic("\nlowerSumbol unspported top level kind {}\n", .{kind}),
        }
    }
    panic("\nlowerSymbol failed for symbol {s}\n", .{literalOf(entity)});
}

fn lowerDot(context: Context, entity: Entity) !Entity {
    const arguments = entity.get(components.ast.Arguments).entities;
    const ast = try lowerExpression(context, arguments[0]);
    assert(eql(typeOf(ast), context.codebase.get(components.ir.Builtins).Module));
    const call = arguments[1];
    assert(call.get(components.ast.Kind) == .call);
    const callable = call.get(components.ast.Callable).entity;
    assert(callable.get(components.ast.Kind) == .symbol);
    // TODO: check if this function has already been lowered for these parameter types
    const top_level = ast.get(components.ast.TopLevel);
    const literal = callable.get(components.token.Literal);
    const overloads = top_level.findLiteral(literal).get(components.ast.Overloads).entities.slice();
    assert(overloads.len == 1);
    const new_context = Context{
        .allocator = context.allocator,
        .codebase = context.codebase,
        .fs = context.fs,
        .ast = ast,
        .function = overloads[0],
    };
    assert(new_context.function.get(components.ast.Parameters).entities.len == 0);
    const function = try lowerFunction(new_context);
    const ast_arguments = call.get(components.ast.Arguments).entities;
    const ir_arguments = try context.allocator.alloc(Entity, ast_arguments.len);
    for (ast_arguments) |argument, i| {
        ir_arguments[i] = try lowerExpression(context, argument);
    }
    // TODO: add a new expression to basic block which calls the function with the ast arguments
    const return_type = function.get(components.ir.ReturnType).entity;
    return try context.codebase.createEntity(.{components.ir.Type.init(return_type)});
}

fn lowerBinaryOp(context: Context, entity: Entity) !Entity {
    const binary_op = entity.get(components.ast.BinaryOp);
    return switch (binary_op) {
        .dot => lowerDot(context, entity),
        else => panic("\nlowerBinaryOp unsupported binary op {}\n", .{binary_op}),
    };
}

fn lowerInt(entity: Entity) !Entity {
    const builtins = entity.ecs.get(components.ir.Builtins);
    return try entity.set(.{components.ir.Type.init(builtins.IntLiteral)});
}

fn lowerExpression(context: Context, entity: Entity) error{OutOfMemory}!Entity {
    const kind = entity.get(components.ast.Kind);
    return switch (kind) {
        .symbol => try lowerSymbol(context, entity),
        .int => try lowerInt(entity),
        .binary_op => try lowerBinaryOp(context, entity),
        else => panic("\nlowerExpression unsupported kind {}\n", .{kind}),
    };
}

fn lowerFunctionBody(context: Context) !components.ir.Body {
    const body = context.function.get(components.ast.Body).entities;
    const lowered = try context.allocator.alloc(Entity, body.len);
    for (body) |expression, i| {
        lowered[i] = try lowerExpression(context, expression);
    }
    return components.ir.Body.init(lowered);
}

fn lowerFunctionReturnType(context: Context) !components.ir.ReturnType {
    const return_type = context.function.get(components.ast.ReturnType).entity;
    return components.ir.ReturnType.init(try lowerExpression(context, return_type));
}

fn lowerFunction(context: Context) !Entity {
    const return_type = try lowerFunctionReturnType(context);
    const body = try lowerFunctionBody(context);
    return try context.codebase.createEntity(.{
        components.ir.Name.init(context.function.get(components.ast.Name).entity),
        return_type,
        body,
    });
}

pub fn lower(codebase: *ECS, fs: ECS, module_name: []const u8, function_name: []const u8) !Entity {
    try initBuiltins(codebase);
    const contents = read(fs, module_name);
    var tokens = try tokenize(codebase, contents);
    const ast = try parse(codebase, &tokens);
    _ = try ast.set(.{components.ir.Type.init(codebase.get(components.ir.Builtins).Module)});
    var ir_top_level = components.ir.TopLevel.init(&codebase.arena.allocator, codebase.getPtr(Strings));
    const ast_top_level = ast.get(components.ast.TopLevel);
    const overloads = ast_top_level.findString(function_name).get(components.ast.Overloads).entities.slice();
    assert(overloads.len == 1);
    const context = Context{
        .allocator = &codebase.arena.allocator,
        .codebase = codebase,
        .fs = fs,
        .ast = ast,
        .function = overloads[0],
    };
    assert(context.function.get(components.ast.Parameters).entities.len == 0);
    const function = try lowerFunction(context);
    try ir_top_level.put(function.get(components.ir.Name), function);
    return try codebase.createEntity(.{ir_top_level});
}

test "call function from import" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try initFileSystem(&arena);
    _ = try newFile(&fs, "foo",
        \\import bar
        \\
        \\start = function() -> I64
        \\  bar.baz()
        \\end
    );
    _ = try newFile(&fs, "bar",
        \\baz = function() -> I64
        \\  10
        \\end
    );
    const ir = try lower(&codebase, fs, "foo", "start");
    const builtins = codebase.get(components.ir.Builtins);
    const top_level = ir.get(components.ir.TopLevel);
    const start = top_level.findString("start");
    try expectEqual(start.get(components.ir.ReturnType).entity, builtins.I64);
}
