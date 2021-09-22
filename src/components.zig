const List = @import("list.zig").List;
const Entity = @import("ecs.zig").Entity;

pub const Position = struct {
    column: u64,
    row: u64,
};

pub const Name = struct {
    value: []const u8,
};

pub const Functions = struct {
    entities: List(Entity),
};

pub const Parameters = struct {
    entities: List(Entity),
};
