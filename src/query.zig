const std = @import("std");
const panic = std.debug.panic;

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

pub fn valueOf(comptime T: type, entity: Entity) !?T {
    if (entity.has(T)) |value| {
        return value;
    }
    if (entity.has(components.Literal)) |literal| {
        const string = entity.ecs.get(Strings).get(literal.interned);
        const types = [_]type{ i64, i32, i16, i8, u64, u32, u16, u8 };
        inline for (&types) |E| {
            if (T == E) {
                const value = try std.fmt.parseInt(T, string, 10);
                _ = try entity.set(.{value});
                return value;
            }
        }
        const float_types = [_]type{ f64, f32 };
        inline for (&float_types) |E| {
            if (T == E) {
                const value = try std.fmt.parseFloat(T, string);
                _ = try entity.set(.{value});
                return value;
            }
        }
        panic("\nvalue of unsupported type {s}\n", .{@typeName(T)});
    }
    return null;
}
