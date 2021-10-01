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
const codebase_module = @import("codebase.zig");
const Codebase = codebase_module.Codebase;
const Scope = codebase_module.Scope;
const List = @import("list.zig").List;
const components = @import("components.zig");
const query = @import("query.zig");

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
    stack: List(Scope),
    codebase: *Codebase,

    pub fn init(codebase: *Codebase) !Scopes {
        var scopes = Scopes{
            .stack = List(Scope).init(codebase.allocator),
            .codebase = codebase,
        };
        const scope = Scope.init(codebase.allocator);
        try scopes.stack.push(scope);
        return scopes;
    }

    pub fn deinit(self: *Scopes) void {
        for (self.stack.slice()) |*scope| {
            scope.deinit();
        }
        self.stack.deinit();
    }

    pub fn lookup(self: *Scopes, interned: InternedString) !Entity {
        var stack = self.stack.slice();
        var iterator = Reverse(Scope).init(stack);
        while (iterator.next()) |scope| {
            if (scope.get(interned)) |entity| {
                return entity;
            }
        }
        if (self.codebase.builtins.scope.get(interned)) |entity| {
            return entity;
        }
        const name = components.Name{ .interned = interned };
        const entity = try self.codebase.ecs.createEntity(.{name});
        try stack[0].putNoClobber(interned, entity);
        return entity;
    }

    pub fn insert(self: *Scopes, interned: InternedString, entity: Entity) !void {
        var stack = self.stack.slice();
        try stack[stack.len - 1].put(interned, entity);
    }

    pub fn push(self: *Scopes) !void {
        try self.stack.push(Scope.init(self.codebase.allocator));
    }

    pub fn pop(self: *Scopes) void {
        if (self.stack.pop()) |*scope| {
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
    var scopes = try Scopes.init(&codebase);
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
    var scopes = try Scopes.init(&codebase);
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
    var scopes = try Scopes.init(&codebase);
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
    var scopes = try Scopes.init(&codebase);
    defer scopes.deinit();
    const interned_u64 = try codebase.strings.intern("u64");
    const u64_lookup = try scopes.lookup(interned_u64);
    try expectEqual(codebase.builtins.U64, u64_lookup);
}
