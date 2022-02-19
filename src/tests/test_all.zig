const std = @import("std");

const test_tokenizer = @import("test_tokenizer.zig");
const test_parser = @import("test_parser.zig");
const test_semantic_analyzer = @import("test_semantic_analyzer.zig");
const test_uniform_function_call_syntax = @import("test_uniform_function_call_syntax.zig");
const test_codegen = @import("test_codegen.zig");
const test_wasm_printer = @import("test_wasm_printer.zig");
const test_error_printer = @import("test_error_printer.zig");
const test_ecs = @import("test_ecs.zig");
const test_list = @import("test_list.zig");
const test_strings = @import("test_strings.zig");
const test_init_codebase = @import("test_init_codebase.zig");
const test_file_system = @import("test_file_system.zig");

test "run all tests" {
    std.testing.refAllDecls(@This());
}
