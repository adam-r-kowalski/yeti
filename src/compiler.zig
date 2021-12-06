const std = @import("std");

pub const codegen = @import("codegen.zig").codegen;
pub const codegen_next = @import("codegen_next.zig").codegen;
pub const initCodebase = @import("init_codebase.zig").initCodebase;
pub const ECS = @import("ecs.zig").ECS;
pub const FileSystem = @import("file_system.zig").FileSystem;
pub const List = @import("list.zig").List;
pub const lower = @import("lower.zig").lower;
pub const analyzeSemantics = @import("semantic_analyzer.zig").analyzeSemantics;
pub const parse = @import("parser.zig").parse;
pub const Strings = @import("strings.zig").Strings;
pub const tokenize = @import("tokenizer.zig").tokenize;
pub const typeid = @import("typeid.zig").typeid;
pub const wasmString = @import("wasm_string.zig").wasmString;

test "run all tests" {
    std.testing.refAllDecls(@This());
}
