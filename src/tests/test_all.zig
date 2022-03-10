const std = @import("std");

const test_uniform_function_call_syntax = @import("test_uniform_function_call_syntax.zig");
const test_error_printer = @import("test_error_printer.zig");
const test_ecs = @import("test_ecs.zig");
const test_list = @import("test_list.zig");
const test_string_interning = @import("test_string_interning.zig");
const test_init_codebase = @import("test_init_codebase.zig");
const test_file_system = @import("test_file_system.zig");
const test_foreign_export = @import("test_foreign_export.zig");
const test_foreign_import = @import("test_foreign_import.zig");
const test_struct = @import("test_struct.zig");
const test_while = @import("test_while.zig");
const test_for = @import("test_for.zig");
const test_strings = @import("test_strings.zig");
const test_arrays = @import("test_arrays.zig");
const test_simd = @import("test_simd.zig");
const test_pointer = @import("test_pointer.zig");
const test_assignment = @import("test_assignment.zig");
const test_if = @import("test_if.zig");
const test_binary_op = @import("test_binary_op.zig");
const test_define = @import("test_define.zig");
const test_function = @import("test_function.zig");
const test_primitive = @import("test_primitive.zig");
const test_import = @import("test_import.zig");
const test_return_type_inference = @import("test_return_type_inference.zig");

test "run all tests" {
    std.testing.refAllDecls(@This());
}
