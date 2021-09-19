const std = @import("std");
const expect = std.testing.expect;

const compiler = @import("compiler");

test "foo" {
    try expect(compiler.foo() == 3);
}

// zig test --pkg-begin compiler src/compiler.zig test\test.zig
