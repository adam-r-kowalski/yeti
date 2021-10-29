const Entity = @import("../ecs.zig").Entity;
const distinct = @import("distinct.zig");
const DistinctEntity = distinct.DistinctEntity;
const DistinctEntities = distinct.DistinctEntities;
const DistinctEntityMap = distinct.DistinctEntityMap;

pub const Name = DistinctEntity("Name");
pub const Type = DistinctEntity("Type");
pub const ReturnType = DistinctEntity("ReturnType");
pub const Body = DistinctEntities("Body");
pub const Scope = DistinctEntityMap("Scope", Name);
pub const TopLevel = DistinctEntityMap("TopLevel", Name);

pub const Builtins = struct {
    Type: Entity,
    Module: Entity,
    I64: Entity,
    U64: Entity,
    F64: Entity,
    IntLiteral: Entity,
    FloatLiteral: Entity,
    StringLiteral: Entity,
};
