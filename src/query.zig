const ecs = @import("ecs.zig");
const Entity = ecs.Entity;
const ECS = ecs.ECS;
const components = @import("components.zig");
const Strings = @import("strings.zig").Strings;

pub fn literalOf(entity: Entity) []const u8 {
    return entity.ecs.get(Strings).get(entity.get(components.Literal).interned);
}

pub fn typeOf(entity: Entity) Entity {
    return entity.get(components.Type).entity;
}

pub fn parentType(entity: Entity) Entity {
    return entity.get(components.ParentType).entity;
}

pub fn valueType(entity: Entity) Entity {
    return entity.get(components.ValueType).entity;
}

pub fn sizeOf(entity: Entity) i32 {
    return entity.get(components.Size).bytes;
}
