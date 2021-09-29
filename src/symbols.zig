const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const panic = std.debug.panic;
const Allocator = std.mem.Allocator;

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

pub const Symbols = struct {
    scopes: List(Scope),
    codebase: *Codebase,

    fn init(allocator: *Allocator, codebase: *Codebase) !Symbols {
        var symbols = Symbols{ .scopes = List(Scope).init(allocator), .codebase = codebase };
        const scope = Scope.init(allocator);
        try symbols.scopes.push(scope);
        return symbols;
    }

    fn deinit(self: *Symbols) void {
        for (self.scopes.slice()) |*scope| {
            scope.deinit();
        }
        self.scopes.deinit();
    }

    fn lookup(self: *Symbols, interned: InternedString) !Entity {
        var scopes = self.scopes.slice();
        var iterator = Reverse(Scope).init(scopes);
        while (iterator.next()) |scope| {
            if (scope.get(interned)) |entity| {
                return entity;
            }
        }
        const name = components.Name{ .interned = interned };
        const entity = try self.codebase.ecs.createEntity(.{name});
        try scopes[scopes.len - 1].putNoClobber(interned, entity);
        return entity;
    }
};

test "lookup same symbol in 'external' scope" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch panic("MEMORY LEAK", .{});
    const allocator = &gpa.allocator;
    var codebase = try Codebase.init(allocator);
    defer codebase.deinit();
    const interned_foo = try codebase.strings.intern("foo");
    var symbols = try Symbols.init(allocator, &codebase);
    defer symbols.deinit();
    const foo = try symbols.lookup(interned_foo);
    try expectEqualStrings(query.nameLiteral(codebase, foo), "foo");
    const foo2 = try symbols.lookup(interned_foo);
    try expectEqual(foo, foo2);
}
