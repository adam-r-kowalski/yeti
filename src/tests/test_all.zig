const std = @import("std");

const test_tokenizer = @import("test_tokenizer.zig");
const test_parser = @import("test_parser.zig");
const test_semantic_analyzer = @import("test_semantic_analyzer.zig");

test "run all tests" {
    std.testing.refAllDecls(@This());
}
