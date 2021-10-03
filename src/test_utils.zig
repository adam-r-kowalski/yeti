const Codebase = @import("codebase.zig").Codebase;
const Entity = @import("ecs.zig").Entity;
const Literal = @import("tokenizer.zig").Literal;

pub fn literalOf(codebase: Codebase, entity: Entity) []const u8 {
    return codebase.strings.get(entity.get(Literal).?.interned).?;
}
