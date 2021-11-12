const std = @import("std");
const expect = std.testing.expect;

pub fn typeid(comptime _: type) usize {
    const S = struct {
        var N: usize = 0;
    };
    return @ptrToInt(&S.N);
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
