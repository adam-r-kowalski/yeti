const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const eql = std.meta.eql;
const panic = std.debug.panic;

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

pub fn DistinctList(comptime unique_id: []const u8, comptime T: type) type {
    assert(unique_id.len > 0);
    return struct {
        values: List(T, .{}),

        const Self = @This();

        pub fn init(allocator: Allocator) Self {
            return Self{ .values = List(T, .{}).init(allocator) };
        }

        pub fn fromSlice(allocator: Allocator, values: []const T) !Self {
            const list = try List(T, .{}).fromSlice(allocator, values);
            return Self{ .values = list };
        }

        pub fn withCapacity(allocator: Allocator, capacity: u64) !Self {
            const list = try List(T, .{}).withCapacity(allocator, capacity);
            return Self{ .values = list };
        }

        pub fn append(self: *Self, value: T) !void {
            try self.values.append(value);
        }

        pub fn appendSlice(self: *Self, values: []const T) !void {
            return self.values.appendSlice(values);
        }

        pub fn appendAssumeCapacity(self: *Self, entity: T) void {
            self.values.appendAssumeCapacity(entity);
        }

        pub fn slice(self: Self) []const T {
            return self.values.slice();
        }

        pub fn mutSlice(self: Self) []T {
            return self.values.mutSlice();
        }

        pub fn shrink(self: *Self, n: u64) void {
            self.values.len -= n;
        }

        pub fn last(self: Self) T {
            return self.values.last();
        }

        pub fn len(self: Self) u64 {
            return self.values.len;
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

        pub fn init(allocator: Allocator, strings: *Strings) Self {
            return Self{ .map = Map.init(allocator), .strings = strings };
        }

        pub fn putInterned(self: *Self, interned: InternedString, entity: Entity) !void {
            try self.map.putNoClobber(interned, entity);
        }

        pub fn putName(self: *Self, value: Name, entity: Entity) !void {
            try self.map.putNoClobber(value.entity.get(Literal).interned, entity);
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
    };
}

pub fn DistinctEntitySet(comptime unique_id: []const u8) type {
    assert(unique_id.len > 0);

    return struct {
        entities: List(Entity, .{}),

        const Self = @This();

        pub fn init(allocator: Allocator) Self {
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
    bar_greater,
    percent,
    caret,
    comma,
    import,
    fn_,
    end,
    if_,
    then,
    else_,
    while_,
    underscore,
    foreign_export,
    foreign_import,
    new_line,
    struct_,
};

pub const Literal = struct {
    interned: InternedString,

    pub fn init(interned: InternedString) Literal {
        return Literal{ .interned = interned };
    }
};

pub const AstKind = enum(u8) {
    symbol,
    int,
    float,
    function,
    binary_op,
    define,
    assign,
    call,
    import,
    overload_set,
    if_,
    while_,
    local,
    intrinsic,
    underscore,
    cast,
    pointer,
    struct_,
    construct,
    field,
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
    pipeline,
};

pub const Intrinsic = enum(u8) {
    add,
    subtract,
    multiply,
    divide,
    remainder,
    bit_and,
    bit_or,
    bit_xor,
    left_shift,
    right_shift,
    equal,
    not_equal,
    less_than,
    less_equal,
    greater_than,
    greater_equal,
    store,
    load,
    add_ptr_i32,
    subtract_ptr_i32,
    subtract_ptr_ptr,
    v128_load,
    v128_store,
};

pub const WasmInstructionKind = enum(u8) {
    i64_const,
    i32_const,
    f64_const,
    f32_const,
    i64_add,
    i32_add,
    i32_add_mod_16,
    i32_add_mod_8,
    f64_add,
    f32_add,
    i64_sub,
    i32_sub,
    i32_sub_mod_16,
    i32_sub_mod_8,
    f64_sub,
    f32_sub,
    i64_mul,
    i32_mul,
    i32_mul_mod_16,
    i32_mul_mod_8,
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
    i32_eqz,
    call,
    local_get,
    local_set,
    if_,
    else_,
    end,
    block,
    loop,
    br_if,
    br,
    i32_store,
    i64_store,
    f32_store,
    f64_store,
    i32_load,
    i64_load,
    f32_load,
    f64_load,
    v128_load,
    v128_store,
    i64x2_add,
    i32x4_add,
    i16x8_add,
    i8x16_add,
    f64x2_add,
    f32x4_add,
    i64x2_sub,
    i32x4_sub,
    i16x8_sub,
    i8x16_sub,
    f64x2_sub,
    f32x4_sub,
    i64x2_mul,
    i32x4_mul,
    i16x8_mul,
    i8x16_mul,
    f64x2_mul,
    f32x4_mul,
    f64x2_div,
    f32x4_div,
    field,
};

pub const Builtins = struct {
    Type: Entity,
    Module: Entity,
    I64: Entity,
    I32: Entity,
    I16: Entity,
    I8: Entity,
    U64: Entity,
    U32: Entity,
    U16: Entity,
    U8: Entity,
    F64: Entity,
    F32: Entity,
    Void: Entity,
    Ptr: Entity,
    IntLiteral: Entity,
    FloatLiteral: Entity,
    I64X2: Entity,
    I32X4: Entity,
    I16X8: Entity,
    I8X16: Entity,
    U64X2: Entity,
    U32X4: Entity,
    U16X8: Entity,
    U8X16: Entity,
    F64X2: Entity,
    F32X4: Entity,
    Cast: Entity,
};

pub const Error = struct {
    header: []const u8,
    body: []const u8,
    span: Span,
    hint: []const u8,
    module: Entity,
};

pub const Scopes = struct {
    const Map = std.AutoHashMap(InternedString, Entity);
    const Self = @This();

    scopes: List(Map, .{}),
    strings: *Strings,
    allocator: Allocator,

    pub fn init(allocator: Allocator, strings: *Strings) Self {
        return Self{
            .scopes = List(Map, .{}).init(allocator),
            .strings = strings,
            .allocator = allocator,
        };
    }

    pub fn pushScope(self: *Self) !u64 {
        const index = self.scopes.len;
        try self.scopes.append(Map.init(self.allocator));
        return index;
    }

    pub fn putInterned(self: *Self, interned: InternedString, entity: Entity) !void {
        assert(self.scopes.len > 0);
        const scopes = self.scopes.mutSlice();
        try scopes[scopes.len - 1].putNoClobber(interned, entity);
    }

    pub fn putName(self: *Self, value: Name, entity: Entity) !void {
        try self.putInterned(value.entity.get(Literal).interned, entity);
    }

    pub fn putLiteral(self: *Self, literal: Literal, entity: Entity) !void {
        try self.putInterned(literal.interned, entity);
    }

    pub fn findString(self: Self, string: []const u8) Entity {
        const interned = self.strings.lookup.get(string).?;
        const scopes = self.scopes.mutSlice();
        var i: usize = scopes.len;
        while (i > 0) : (i -= 1) {
            if (scopes[i - 1].get(interned)) |entity| {
                return entity;
            }
        }
        panic("\nscopes could not find string {s}\n", .{string});
    }

    pub fn findLiteral(self: Self, literal: Literal) Entity {
        return self.hasLiteral(literal).?;
    }

    pub fn findName(self: Self, name: Name) Entity {
        return self.hasName(name).?;
    }

    pub fn hasLiteral(self: Self, literal: Literal) ?Entity {
        const interned = literal.interned;
        const scopes = self.scopes.mutSlice();
        var i: usize = scopes.len;
        while (i > 0) : (i -= 1) {
            if (scopes[i - 1].get(interned)) |entity| {
                return entity;
            }
        }
        return null;
    }

    pub fn hasName(self: Self, name: Name) ?Entity {
        return self.hasLiteral(name.entity.get(Literal));
    }

    pub fn slice(self: Self) []const Map {
        return self.scopes.slice();
    }
};

fn DistinctMap(comptime unique_id: []const u8, comptime K: type, comptime V: type) type {
    assert(unique_id.len > 0);

    return struct {
        const Map = std.AutoHashMap(K, V);

        const Self = @This();

        map: Map,

        pub fn init(allocator: Allocator) Self {
            return Self{ .map = Map.init(allocator) };
        }

        pub fn getOrPut(self: *Self, key: K) !Map.GetOrPutResult {
            return try self.map.getOrPut(key);
        }
    };
}

pub const Name = DistinctEntity("Name");
pub const ReturnTypeAst = DistinctEntity("Return Type Ast");
pub const ReturnType = DistinctEntity("Return Type");
pub const Value = DistinctEntity("Value");
pub const Callable = DistinctEntity("Callable");
pub const TypeAst = DistinctEntity("Type Ast");
pub const Type = DistinctEntity("Type");
pub const Parameters = DistinctList("Parameters", Entity);
pub const Body = DistinctList("Body", Entity);
pub const Arguments = DistinctList("Arguments", Entity);
pub const Overloads = DistinctList("Overloads", Entity);
pub const Fields = DistinctList("Fields", Entity);
pub const TopLevel = DistinctEntityMap("Top Level");
pub const Path = DistinctEntity("Path");
pub const Module = DistinctEntity("Module");
pub const Functions = DistinctList("Functions", Entity);
pub const WasmInstructions = DistinctList("Wasm Instructions", Entity);
pub const Locals = DistinctEntitySet("Locals");
pub const Conditional = DistinctEntity("Conditional");
pub const Then = DistinctList("Then", Entity);
pub const Else = DistinctList("Else", Entity);
pub const DependentEntities = DistinctList("Dependent Entities", Entity);
pub const Local = DistinctEntity("Local");
pub const Field = DistinctEntity("Field");
pub const Constant = DistinctEntity("Constant");
pub const Scope = DistinctEntityMap("Scope");
pub const ActiveScopes = DistinctList("Active Scopes", u64);
pub const Label = struct { value: u64 };
pub const Mutable = struct { value: bool };
pub const AnalyzedParameters = struct { value: bool };
pub const AnalyzedBody = struct { value: bool };
pub const AnalyzedFields = struct { value: bool };
pub const WasmName = DistinctList("Wasm Name", u8);
pub const ForeignImports = DistinctList("Foreign Imports", Entity);
pub const ForeignExports = DistinctList("Foreign Exports", Entity);
pub const ForeignModule = DistinctEntity("Foreign Module");
pub const ForeignName = DistinctEntity("Foreign Name");
pub const Memoized = DistinctMap("Memoized", Entity, Entity);
pub const ParentType = DistinctEntity("Parent Type");
pub const ValueType = DistinctEntity("Value Type");
pub const UsesMemory = struct { value: bool };
pub const Size = struct { bytes: i32 };
pub const ModuleSource = struct { string: []const u8 };
pub const ModulePath = struct { string: []const u8 };
