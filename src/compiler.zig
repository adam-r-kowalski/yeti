const std = @import("std");

pub const codegen = @import("codegen.zig").codegen;
pub const initCodebase = @import("init_codebase.zig").initCodebase;
pub const ecs = @import("ecs.zig");
pub const FileSystem = @import("file_system.zig").FileSystem;
pub const List = @import("list.zig").List;
pub const analyzeSemantics = @import("semantic_analyzer.zig").analyzeSemantics;
pub const parser = @import("parser.zig");
pub const parse = parser.parse;
pub const Strings = @import("strings.zig").Strings;
pub const tokenize = @import("tokenizer.zig").tokenize;
pub const typeid = @import("typeid.zig").typeid;
pub const printWasm = @import("wasm_printer.zig").printWasm;
pub const error_printer = @import("error_printer.zig");
pub const components = @import("components.zig");
pub const test_utils = @import("test_utils.zig");

test "run all tests" {
    std.testing.refAllDecls(@This());
}
