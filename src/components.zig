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
};

pub const Parameters = struct {
    entities: List(Entity),
};

pub const ReturnType = struct {
    entity: Entity,
};
