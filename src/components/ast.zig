const Entity = @import("../ecs.zig").Entity;
const distinct = @import("distinct.zig");
const DistinctEntity = distinct.DistinctEntity;
const DistinctEntities = distinct.DistinctEntities;
const DistinctEntityMap = distinct.DistinctEntityMap;

pub const Name = DistinctEntity("Name");
pub const ReturnType = DistinctEntity("Return Type");
pub const Value = DistinctEntity("Value");
pub const Callable = DistinctEntity("Callable");
pub const Type = DistinctEntity("Type");
pub const Parameters = DistinctEntities("Parameters");
pub const Body = DistinctEntities("Body");
pub const Arguments = DistinctEntities("Arguments");
pub const Overloads = DistinctEntities("Overloads");
pub const TopLevel = DistinctEntityMap("TopLevel", Name);
pub const Path = DistinctEntity("Path");

pub const Kind = enum(u8) {
    symbol,
    int,
    function,
    binary_op,
    define,
    call,
    import,
    overload_set,
};

pub const BinaryOp = enum(u8) {
    add,
    multiply,
    dot,
};
