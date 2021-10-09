const std = @import("std");
const Allocator = std.mem.Allocator;

const InternedString = @import("strings.zig").InternedString;
const BucketList = @import("bucket_list.zig").BucketList;
const Entity = @import("ecs.zig").Entity;

pub const Position = struct {
    column: u64,
    row: u64,
};

pub const Span = struct {
    begin: Position,
    end: Position,
};

pub const TokenKind = enum(u8) {
    symbol,
    int,
    float,
    function,
    left_paren,
    right_paren,
    colon,
    plus,
    times,
};

pub const Literal = struct {
    interned: InternedString,
};

pub const Name = struct {
    entity: Entity,

    pub fn init(entity: Entity) Name {
        return Name{ .entity = entity };
    }
};

pub const Parameters = struct {
    entities: BucketList(Entity),

    pub fn init(allocator: *Allocator) Parameters {
        return Parameters{ .entities = BucketList(Entity).init(allocator) };
    }
};

pub const ReturnType = struct {
    entity: Entity,

    pub fn init(entity: Entity) ReturnType {
        return ReturnType{ .entity = entity };
    }
};

pub const Body = struct {
    entities: BucketList(Entity),

    pub fn init(allocator: *Allocator) Body {
        return Body{ .entities = BucketList(Entity).init(allocator) };
    }
};

pub const AstKind = enum(u8) {
    symbol,
    int,
    function,
    binary_op,
};

pub const BinaryOpKind = enum(u8) {
    add,
    multiply,
};

pub const BinaryOp = struct {
    kind: BinaryOpKind,
    left: Entity,
    right: Entity,
};
