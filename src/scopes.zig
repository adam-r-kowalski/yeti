const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const panic = std.debug.panic;
const Allocator = std.mem.Allocator;
const eql = std.meta.eql;

const strings_module = @import("strings.zig");
const InternedString = strings_module.InternedString;
const Strings = strings_module.Strings;
const Entity = @import("ecs.zig").Entity;
const Codebase = @import("codebase.zig").Codebase;
const List = @import("list.zig").List;
const components = @import("components.zig");
const query = @import("query.zig");

const Scope = std.AutoHashMap(InternedString, Entity);

fn Reverse(comptime T: type) type {
    return struct {
        slice: []const T,

        const Self = @This();

        fn init(slice: []const T) Self {
            return Self{ .slice = slice };
        }

        fn next(self: *Self) ?*const T {
            var len = self.slice.len;
            if (len == 0) {
                return null;
            } else {
                len = len - 1;
                const result = &self.slice[len];
                self.slice = self.slice[0..len];
                return result;
            }
        }
    };
}

test "reverse" {
    var iterator = Reverse(u64).init(&.{ 5, 2, 9 });
    try expectEqual(iterator.next().?.*, 9);
    try expectEqual(iterator.next().?.*, 2);
    try expectEqual(iterator.next().?.*, 5);
    try expectEqual(iterator.next(), null);
}

pub const Scopes = struct {
    scopes: List(Scope),
    codebase: *Codebase,
    allocator: *Allocator,
    builtins: *Scope,

    fn init(allocator: *Allocator, codebase: *Codebase, builtins: *Scope) !Scopes {
        var scopes = Scopes{
            .scopes = List(Scope).init(allocator),
            .codebase = codebase,
            .allocator = allocator,
            .builtins = builtins,
        };
        const scope = Scope.init(allocator);
        try scopes.scopes.push(scope);
        return scopes;
    }

    fn deinit(self: *Scopes) void {
        for (self.scopes.slice()) |*scope| {
            scope.deinit();
        }
        self.scopes.deinit();
    }

    fn lookup(self: *Scopes, interned: InternedString) !Entity {
        var scopes = self.scopes.slice();
        var iterator = Reverse(Scope).init(scopes);
        while (iterator.next()) |scope| {
            if (scope.get(interned)) |entity| {
                return entity;
            }
        }
        if (self.builtins.get(interned)) |entity| {
            return entity;
        }
        const name = components.Name{ .interned = interned };
        const entity = try self.codebase.ecs.createEntity(.{name});
        try scopes[0].putNoClobber(interned, entity);
        return entity;
    }

    fn insert(self: *Scopes, interned: InternedString, entity: Entity) !void {
        var scopes = self.scopes.slice();
        try scopes[scopes.len - 1].put(interned, entity);
    }

    fn push(self: *Scopes) !void {
        try self.scopes.push(Scope.init(self.allocator));
    }

    fn pop(self: *Scopes) void {
        if (self.scopes.pop()) |*scope| {
            scope.deinit();
        }
    }
};

test "lookup same symbol in scope" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch panic("MEMORY LEAK", .{});
    const allocator = &gpa.allocator;
    var codebase = try Codebase.init(allocator);
    defer codebase.deinit();
    const interned_foo = try codebase.strings.intern("foo");
    var scope = Scope.init(allocator);
    defer scope.deinit();
    var scopes = try Scopes.init(allocator, &codebase, &scope);
    defer scopes.deinit();
    const foo = try scopes.lookup(interned_foo);
    try expectEqualStrings(query.nameLiteral(codebase, foo), "foo");
    const foo2 = try scopes.lookup(interned_foo);
    try expectEqual(foo, foo2);
}

test "lookup symbol then insert new symbol with same name in scope" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch panic("MEMORY LEAK", .{});
    const allocator = &gpa.allocator;
    var codebase = try Codebase.init(allocator);
    defer codebase.deinit();
    const interned_foo = try codebase.strings.intern("foo");
    var scope = Scope.init(allocator);
    defer scope.deinit();
    var scopes = try Scopes.init(allocator, &codebase, &scope);
    defer scopes.deinit();
    const foo = try scopes.lookup(interned_foo);
    const name = components.Name{ .interned = interned_foo };
    const foo2 = try codebase.ecs.createEntity(.{name});
    try scopes.insert(interned_foo, foo2);
    try expect(!eql(foo, foo2));
    const foo3 = try scopes.lookup(interned_foo);
    try expectEqual(foo2, foo3);
}

test "push and pop new scope" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch panic("MEMORY LEAK", .{});
    const allocator = &gpa.allocator;
    var codebase = try Codebase.init(allocator);
    defer codebase.deinit();
    var scope = Scope.init(allocator);
    defer scope.deinit();
    var scopes = try Scopes.init(allocator, &codebase, &scope);
    defer scopes.deinit();
    const interned_foo = try codebase.strings.intern("foo");
    const name = components.Name{ .interned = interned_foo };
    const foo = try codebase.ecs.createEntity(.{name});
    try scopes.insert(interned_foo, foo);
    try scopes.push();
    const foo2 = try codebase.ecs.createEntity(.{name});
    try scopes.insert(interned_foo, foo2);
    const foo2_lookup = try scopes.lookup(interned_foo);
    try expectEqual(foo2, foo2_lookup);
    try expect(!eql(foo2_lookup, foo));
    scopes.pop();
    const foo_lookup = try scopes.lookup(interned_foo);
    try expectEqual(foo, foo_lookup);
    try expect(!eql(foo_lookup, foo2));
}

test "builtins" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch panic("MEMORY LEAK", .{});
    const allocator = &gpa.allocator;
    var codebase = try Codebase.init(allocator);
    defer codebase.deinit();
    var scope = Scope.init(allocator);
    defer scope.deinit();
    const interned_foo = try codebase.strings.intern("foo");
    const name = components.Name{ .interned = interned_foo };
    const foo = try codebase.ecs.createEntity(.{name});
    try scope.putNoClobber(interned_foo, foo);
    var scopes = try Scopes.init(allocator, &codebase, &scope);
    defer scopes.deinit();
    const foo_lookup = try scopes.lookup(interned_foo);
    try expectEqual(foo, foo_lookup);
}
