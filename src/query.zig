const Codebase = @import("codebase.zig").Codebase;
const Entity = @import("ecs.zig").Entity;
const components = @import("components.zig");

pub fn nameLiteral(codebase: Codebase, entity: Entity) []const u8 {
    return codebase.strings.get(entity.get(components.Name).?.interned).?;
}

pub fn intLiteral(codebase: Codebase, entity: Entity) []const u8 {
    return codebase.strings.get(entity.get(components.Int).?.interned).?;
}

pub fn typeOf(entity: Entity) Entity {
    return entity.get(components.Type).?.entity;
}
