const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const eql = std.meta.eql;

const strings_module = @import("strings.zig");
const Strings = strings_module.Strings;
const InternedString = strings_module.InternedString;
const Entity = @import("ecs.zig").Entity;
const List = @import("list.zig").List;

pub fn DistinctEntity(comptime unique_id: []const u8) type {
    assert(unique_id.len > 0);
    return struct {
        entity: Entity,

        const Self = @This();

        pub fn init(entity: Entity) Self {
            return Self{ .entity = entity };
        }
    };
}

pub fn DistinctEntities(comptime unique_id: []const u8) type {
    assert(unique_id.len > 0);
    return struct {
        entities: List(Entity, .{}),

        const Self = @This();

        pub fn init(allocator: *Allocator) Self {
            return Self{ .entities = List(Entity, .{}).init(allocator) };
        }

        pub fn fromSlice(allocator: *Allocator, entities: []Entity) !Self {
            const list = try List(Entity, .{}).fromSlice(allocator, entities);
            return Self{ .entities = list };
        }

        pub fn withCapacity(allocator: *Allocator, capacity: u64) !Self {
            const list = try List(Entity, .{}).withCapacity(allocator, capacity);
            return Self{ .entities = list };
        }

        pub fn append(self: *Self, entity: Entity) !void {
            try self.entities.append(entity);
        }

        pub fn appendAssumeCapacity(self: *Self, entity: Entity) void {
            self.entities.appendAssumeCapacity(entity);
        }

        pub fn slice(self: Self) []const Entity {
            return self.entities.slice();
        }

        pub fn last(self: Self) Entity {
            return self.entities.last();
        }

        pub fn len(self: Self) u64 {
            return self.entities.len;
        }
    };
}

pub fn DistinctEntityMap(comptime unique_id: []const u8) type {
    assert(unique_id.len > 0);

    return struct {
        const Map = std.AutoHashMap(InternedString, Entity);

        const Self = @This();

        map: Map,
        strings: *Strings,

        pub fn init(allocator: *Allocator, strings: *Strings) Self {
            return Self{ .map = Map.init(allocator), .strings = strings };
        }

        pub fn putInterned(self: *Self, interned: InternedString, entity: Entity) !void {
            try self.map.putNoClobber(interned, entity);
        }

        pub fn findString(self: Self, string: []const u8) Entity {
            const interned = self.strings.lookup.get(string).?;
            return self.map.get(interned).?;
        }

        pub fn findLiteral(self: Self, literal: Literal) Entity {
            return self.map.get(literal.interned).?;
        }

        pub fn hasLiteral(self: Self, literal: Literal) ?Entity {
            return self.map.get(literal.interned);
        }

        pub fn putLiteral(self: *Self, literal: Literal, entity: Entity) !void {
            try self.map.putNoClobber(literal.interned, entity);
        }

        pub fn findName(self: Self, name: Name) Entity {
            return self.hasName(name).?;
        }

        pub fn hasName(self: Self, name: Name) ?Entity {
            const interned = name.entity.get(Literal).interned;
            return self.map.get(interned);
        }

        pub fn putName(self: *Self, value: Name, entity: Entity) !void {
            try self.map.putNoClobber(value.entity.get(Literal).interned, entity);
        }
    };
}

pub fn DistinctEntitySet(comptime unique_id: []const u8) type {
    assert(unique_id.len > 0);

    return struct {
        entities: List(Entity, .{}),

        const Self = @This();

        pub fn init(allocator: *Allocator) Self {
            return Self{ .entities = List(Entity, .{}).init(allocator) };
        }

        pub fn put(self: *Self, entity: Entity) !void {
            for (self.entities.slice()) |e| {
                if (eql(entity, e)) return;
            }
            try self.entities.append(entity);
        }

        pub fn slice(self: Self) []const Entity {
            return self.entities.slice();
        }
    };
}

pub const Position = struct {
    column: u64,
    row: u64,

    pub fn init(column: u64, row: u64) Position {
        return Position{ .column = column, .row = row };
    }
};

pub const Span = struct {
    begin: Position,
    end: Position,

    pub fn init(begin: Position, end: Position) Span {
        return Span{ .begin = begin, .end = end };
    }
};

pub const TokenKind = enum(u8) {
    symbol,
    int,
    float,
    string,
    left_paren,
    right_paren,
    plus,
    minus,
    times,
    slash,
    dot,
    greater_than,
    greater_equal,
    greater_greater,
    less_than,
    less_equal,
    less_less,
    equal,
    equal_equal,
    colon,
    colon_equal,
    bang_equal,
    ampersand,
    bar,
    percent,
    caret,
    comma,
    import,
    function,
    end,
    if_,
    then,
    else_,
};

pub const Literal = struct {
    interned: InternedString,

    pub fn init(interned: InternedString) Literal {
        return Literal{ .interned = interned };
    }
};

pub const Name = DistinctEntity("Name");
pub const ReturnTypeAst = DistinctEntity("Return Type Ast");
pub const ReturnType = DistinctEntity("Return Type");
pub const Value = DistinctEntity("Value");
pub const Callable = DistinctEntity("Callable");
pub const TypeAst = DistinctEntity("Type Ast");
pub const Type = DistinctEntity("Type");
pub const Parameters = DistinctEntities("Parameters");
pub const Body = DistinctEntities("Body");
pub const Arguments = DistinctEntities("Arguments");
pub const Overloads = DistinctEntities("Overloads");
pub const TopLevel = DistinctEntityMap("Top Level");
pub const Path = DistinctEntity("Path");
pub const Scope = DistinctEntityMap("Scope");
pub const BasicBlocks = DistinctEntities("Basic Blocks");
pub const IrInstructions = DistinctEntities("Ir Instructions");
pub const Result = DistinctEntity("Result");
pub const Module = DistinctEntity("Module");
pub const Functions = DistinctEntities("Functions");
pub const WasmInstructions = DistinctEntities("Wasm Instructions");
pub const Locals = DistinctEntitySet("Locals");
pub const Conditional = DistinctEntity("Conditional");
pub const Then = DistinctEntities("Then");
pub const Else = DistinctEntities("Else");
pub const ThenBlock = DistinctEntity("Then Block");
pub const ElseBlock = DistinctEntity("Else Block");
pub const FinallyBlock = DistinctEntity("Finally Block");

pub const AstKind = enum(u8) {
    symbol,
    int,
    float,
    function,
    binary_op,
    define,
    call,
    import,
    overload_set,
    if_,
};

pub const BinaryOp = enum(u8) {
    add,
    subtract,
    multiply,
    divide,
    remainder,
    less_than,
    less_equal,
    greater_than,
    greater_equal,
    equal,
    not_equal,
    bit_or,
    bit_xor,
    bit_and,
    left_shift,
    right_shift,
    dot,
};

pub const LoweredParameters = struct { value: bool };
pub const LoweredBody = struct { value: bool };

pub const IrInstructionKind = enum(u8) {
    int_const,
    float_const,
    i64_add,
    i32_add,
    f64_add,
    f32_add,
    i64_sub,
    i32_sub,
    f64_sub,
    f32_sub,
    i64_mul,
    i32_mul,
    f64_mul,
    f32_mul,
    i64_div,
    i32_div,
    u64_div,
    u32_div,
    f64_div,
    f32_div,
    i64_lt,
    i32_lt,
    u64_lt,
    u32_lt,
    f64_lt,
    f32_lt,
    i64_le,
    i32_le,
    u64_le,
    u32_le,
    f64_le,
    f32_le,
    i64_gt,
    i32_gt,
    u64_gt,
    u32_gt,
    f64_gt,
    f32_gt,
    i64_ge,
    i32_ge,
    u64_ge,
    u32_ge,
    f64_ge,
    f32_ge,
    i64_eq,
    i32_eq,
    f64_eq,
    f32_eq,
    i64_ne,
    i32_ne,
    f64_ne,
    f32_ne,
    i64_or,
    i32_or,
    i64_xor,
    i32_xor,
    i64_and,
    i32_and,
    i64_shl,
    i32_shl,
    u64_shl,
    u32_shl,
    i64_shr,
    i32_shr,
    u64_shr,
    u32_shr,
    i64_rem,
    i32_rem,
    u64_rem,
    u32_rem,
    call,
    get_local,
    set_local,
    if_,
};

pub const WasmInstructionKind = enum(u8) {
    i64_const,
    i32_const,
    f64_const,
    f32_const,
    i64_add,
    i32_add,
    f64_add,
    f32_add,
    i64_sub,
    i32_sub,
    f64_sub,
    f32_sub,
    i64_mul,
    i32_mul,
    f64_mul,
    f32_mul,
    i64_div,
    i32_div,
    u64_div,
    u32_div,
    f64_div,
    f32_div,
    i64_lt,
    i32_lt,
    u64_lt,
    u32_lt,
    f64_lt,
    f32_lt,
    i64_le,
    i32_le,
    u64_le,
    u32_le,
    f64_le,
    f32_le,
    i64_gt,
    i32_gt,
    u64_gt,
    u32_gt,
    f64_gt,
    f32_gt,
    i64_ge,
    i32_ge,
    u64_ge,
    u32_ge,
    f64_ge,
    f32_ge,
    i64_eq,
    i32_eq,
    f64_eq,
    f32_eq,
    i64_ne,
    i32_ne,
    f64_ne,
    f32_ne,
    i64_or,
    i32_or,
    i64_xor,
    i32_xor,
    i64_and,
    i32_and,
    i64_shl,
    i32_shl,
    u64_shl,
    u32_shl,
    i64_shr,
    i32_shr,
    u64_shr,
    u32_shr,
    i64_rem,
    i32_rem,
    u64_rem,
    u32_rem,
    call,
    get_local,
    set_local,
};

pub const Builtins = struct {
    Type: Entity,
    Module: Entity,
    I64: Entity,
    I32: Entity,
    U64: Entity,
    U32: Entity,
    F64: Entity,
    F32: Entity,
    IntLiteral: Entity,
    FloatLiteral: Entity,
    StringLiteral: Entity,
    Void: Entity,
};

pub const Error = struct {
    header: []const u8,
    body: []const u8,
    span: Span,
    hint: []const u8,
    module: Entity,
};
