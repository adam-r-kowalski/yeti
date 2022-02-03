const std = @import("std");
const Arena = std.heap.ArenaAllocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const yeti = @import("yeti");
const Component = yeti.ecs.Component;
const ECS = yeti.ecs.ECS;
const IteratorComponents = yeti.ecs.IteratorComponents;
const typeid = yeti.ecs.typeid;

const Name = struct {
    value: []const u8,
};

const Age = struct {
    value: u8,
};

const Job = struct {
    value: []const u8,
};

test "construct type" {
    const components = .{ Name, Age };
    const Components = IteratorComponents(components);
    const type_info = @typeInfo(Components).Struct;
    try expectEqual(type_info.layout, .Auto);
    const fields = type_info.fields;
    try expectEqual(fields.len, 2);
    const names = fields[0];
    try expectEqualStrings(names.name, "Name");
    try expectEqual(names.field_type, *Component(Name));
    try expectEqual(names.default_value, null);
    try expectEqual(names.is_comptime, false);
    try expectEqual(names.alignment, 8);
    try expectEqual(type_info.decls.len, 0);
    try expectEqual(type_info.is_tuple, false);
    const ages = fields[1];
    try expectEqualStrings(ages.name, "Age");
    try expectEqual(ages.field_type, *Component(Age));
    try expectEqual(ages.default_value, null);
    try expectEqual(ages.is_comptime, false);
    try expectEqual(ages.alignment, 8);
    try expectEqual(type_info.decls.len, 0);
    try expectEqual(type_info.is_tuple, false);
}

test "entity get and set component" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var ecs = ECS.init(&arena);
    const entity = try ecs.createEntity(.{});
    _ = try entity.set(.{Name{ .value = "Joe" }});
    try expectEqual(entity.get(Name), Name{ .value = "Joe" });
    _ = try entity.set(.{Name{ .value = "Bob" }});
    try expectEqual(entity.get(Name), Name{ .value = "Bob" });
}

test "entity get and set components" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var ecs = ECS.init(&arena);
    const entity = try ecs.createEntity(.{});
    _ = try entity.set(.{ Name{ .value = "Joe" }, Age{ .value = 20 } });
    try expectEqual(entity.get(Name), Name{ .value = "Joe" });
    try expectEqual(entity.get(Age), Age{ .value = 20 });
}

test "entity get and set components on creation" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var ecs = ECS.init(&arena);
    const entity = try ecs.createEntity(.{ Name{ .value = "Joe" }, Age{ .value = 20 } });
    try expectEqual(entity.get(Name), Name{ .value = "Joe" });
    try expectEqual(entity.get(Age), Age{ .value = 20 });
}

test "ecs get and set components" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var ecs = ECS.init(&arena);
    try ecs.set(.{ Name{ .value = "Joe" }, Age{ .value = 20 } });
    try expectEqual(ecs.get(Name), Name{ .value = "Joe" });
    try expectEqual(ecs.get(Age), Age{ .value = 20 });
}

test "ecs query entities with components" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var ecs = ECS.init(&arena);
    const joe = try ecs.createEntity(.{ Name{ .value = "Joe" }, Age{ .value = 20 } });
    const bob = try ecs.createEntity(.{Name{ .value = "Bob" }});
    const sally = try ecs.createEntity(.{ Name{ .value = "Sally" }, Age{ .value = 24 } });
    {
        var iterator = ecs.query(.{ Name, Age });
        try expectEqual(iterator.next(), joe);
        try expectEqual(iterator.next(), sally);
        try expectEqual(iterator.next(), null);
    }
    {
        var iterator = ecs.query(.{Name});
        try expectEqual(iterator.next(), joe);
        try expectEqual(iterator.next(), bob);
        try expectEqual(iterator.next(), sally);
        try expectEqual(iterator.next(), null);
    }
}

test "type id" {
    const Foo = struct {
        const Baz = struct {
            x: f64,
        };
        baz: Baz,
    };

    const Bar = struct {
        const Baz = struct {
            y: f64,
        };
        baz: Baz,
    };

    const foo_baz = typeid(Foo.Baz);
    const bar_baz = typeid(Bar.Baz);
    try expect(foo_baz != bar_baz);
}
