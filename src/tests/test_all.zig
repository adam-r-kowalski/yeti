const std = @import("std");

const test_tokenizer = @import("test_tokenizer.zig");
const test_parser = @import("test_parser.zig");
const test_semantic_analyzer = @import("test_semantic_analyzer.zig");
const test_codegen = @import("test_codegen.zig");
const test_wasm_printer = @import("test_wasm_printer.zig");

test "run all tests" {
    std.testing.refAllDecls(@This());
}
