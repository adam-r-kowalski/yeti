const std = @import("std");
const Allocator = std.mem.Allocator;

const List = @import("list.zig").List;
const Entity = @import("ecs.zig").Entity;
const InternedString = @import("strings.zig").InternedString;

pub const Position = struct {
    column: u64,
    row: u64,
};

pub const Name = struct {
    value: InternedString,
};

pub const Functions = struct {
    entities: List(Entity),

    pub fn init(allocator: *Allocator) Functions {
        return Functions{ .entities = List(Entity).init(allocator) };
    }

    pub fn deinit(self: *Functions) void {
        self.entities.deinit();
    }
};

pub const Parameters = struct {
    entities: List(Entity),

    pub fn init(allocator: *Allocator) Parameters {
        return Parameters{ .entities = List(Entity).init(allocator) };
    }
};

pub const ReturnType = struct {
    entity: Entity,
};

pub const Body = struct {
    entities: List(Entity),

    pub fn init(allocator: *Allocator) Body {
        return Body{ .entities = List(Entity).init(allocator) };
    }

    pub fn deinit(self: *Body) void {
        self.entities.deinit();
    }
};
