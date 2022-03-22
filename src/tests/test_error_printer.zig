const std = @import("std");
const Arena = std.heap.ArenaAllocator;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const yeti = @import("yeti");
const initCodebase = yeti.initCodebase;
const MockFileSystem = yeti.FileSystem;
const analyzeSemantics = yeti.analyzeSemantics;
const printErrors = yeti.printErrors;
const colors = yeti.colors;

test "error printer calling function with to few parameters" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\add(x: i64, y: i64) i64 {
        \\  x + y
        \\}
        \\
        \\start() i64 {
        \\  add(5)
        \\}
    );
    try expectEqual(analyzeSemantics(codebase, fs, "foo.yeti"), error.CompileError);
    const error_message = try printErrors(codebase);
    try expectEqualStrings(error_message, try std.fmt.allocPrint(arena.allocator(),
        \\{s}---- FUNCTION CALL ERROR ----------------------------------- foo.yeti{s}
        \\
        \\No matching function overload found for argument types (IntLiteral)
        \\
        \\4| 
        \\5| start() i64 {{
        \\6|   {s}add(5){s}
        \\7| }}
        \\Here are the possible candidates:
        \\
        \\add(x: i64, {s}y: i64{s}) ----- foo.yeti:1
        \\
    , .{ colors.RED, colors.RESET, colors.RED, colors.RESET, colors.RED, colors.RESET }));
}

test "error printer function overloads are aligned" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\add(x: i64, y: i64) i64 {
        \\  x + y
        \\}
        \\
        \\add(x: i64) i64 {
        \\  x + y
        \\}
        \\
        \\start() i64 {
        \\  a: i32 = 5
        \\  add(a, 7)
        \\}
    );
    try expectEqual(analyzeSemantics(codebase, fs, "foo.yeti"), error.CompileError);
    const error_message = try printErrors(codebase);
    try expectEqualStrings(error_message, try std.fmt.allocPrint(arena.allocator(),
        \\{s}---- FUNCTION CALL ERROR ----------------------------------- foo.yeti{s}
        \\
        \\No matching function overload found for argument types (i32, IntLiteral)
        \\
        \\ 9| start() i64 {{
        \\10|   a: i32 = 5
        \\11|   {s}add(a, 7){s}
        \\12| }}
        \\Here are the possible candidates:
        \\
        \\add({s}x: i64{s}, y: i64) ----- foo.yeti:1
        \\add({s}x: i64{s})         ----- foo.yeti:5
        \\
    , .{ colors.RED, colors.RESET, colors.RED, colors.RESET, colors.RED, colors.RESET, colors.RED, colors.RESET }));
}
