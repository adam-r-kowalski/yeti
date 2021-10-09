const ecs = @import("ecs.zig");
const Entity = ecs.Entity;
const ECS = ecs.ECS;
const Literal = @import("components.zig").Literal;
const Strings = @import("strings.zig").Strings;

pub fn literalOf(entity: Entity) []const u8 {
    return entity.ecs.get(Strings).get(entity.get(Literal).interned);
}
