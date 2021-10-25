const std = @import("std");
const eql = std.meta.eql;
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
    const Int = try builtinType(codebase, &scope, "Int", Type);
    const Nat = try builtinType(codebase, &scope, "Nat", Type);
    const Real = try builtinType(codebase, &scope, "Real", Type);
    const builtins = components.ir.Builtins{
        .Type = Type,
        .Int = Int,
        .Nat = Nat,
        .Real = Real,
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
    try expectEqualStrings(literalOf(builtins.Int), "Int");
    try expectEqual(typeOf(builtins.Int), builtins.Type);
    try expectEqual(scope.findString("Int"), builtins.Int);
}

fn evalAstNode(entity: Entity) Entity {
    const kind = entity.get(components.ast.Kind);
    switch (kind) {
        .symbol => {
            const scope = entity.ecs.get(components.ir.Scope);
            return scope.findLiteral(entity.get(components.token.Literal));
        },
        else => panic("\nunsupported kind {}\n", .{kind}),
    }
}

fn lowerFunction(function: Entity) !Entity {
    const codebase = function.ecs;
    const entity = evalAstNode(function.get(components.ast.ReturnType).entity);
    const return_type = components.ir.ReturnType.init(entity);
    return try codebase.createEntity(.{
        // NOTE: should the name be the module name concatenated with the function name?
        function.get(components.ast.Name),
        return_type,
    });
}

pub fn lower(codebase: *ECS, fs: ECS, module_name: []const u8, function_name: []const u8) !Entity {
    try initBuiltins(codebase);
    const contents = read(fs, module_name);
    var tokens = try tokenize(codebase, contents);
    const ast = try parse(codebase, &tokens);
    var ir_top_level = components.ir.TopLevel.init(&codebase.arena.allocator, codebase.getPtr(Strings));
    const ast_top_level = ast.get(components.ast.TopLevel);
    const overloads = ast_top_level.findString(function_name).get(components.ast.Overloads).entities.slice();
    assert(overloads.len == 1);
    const start_ast = overloads[0];
    assert(start_ast.get(components.ast.Parameters).entities.len == 0);
    const start_ir = try lowerFunction(start_ast);
    try ir_top_level.put(start_ir.get(components.ast.Name), start_ir);
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
        \\start() Int = bar.baz()
    );
    _ = try newFile(&fs, "bar",
        \\baz() Int = 10
    );
    const ir = try lower(&codebase, fs, "foo", "start");
    const builtins = codebase.get(components.ir.Builtins);
    const top_level = ir.get(components.ir.TopLevel);
    const start = top_level.findString("start");
    try expectEqual(start.get(components.ir.ReturnType).entity, builtins.Int);
}
