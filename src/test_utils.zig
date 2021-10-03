const Codebase = @import("codebase.zig").Codebase;
const Entity = @import("ecs.zig").Entity;
const components = @import("components.zig");
const Literal = components.Literal;

pub fn literalOf(codebase: Codebase, entity: Entity) []const u8 {
    return codebase.strings.get(entity.get(Literal).interned);
}
