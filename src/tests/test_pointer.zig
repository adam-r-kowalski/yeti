const std = @import("std");
const Arena = std.heap.ArenaAllocator;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const yeti = @import("yeti");
const initCodebase = yeti.initCodebase;
const tokenize = yeti.tokenize;
const parse = yeti.parse;
const analyzeSemantics = yeti.analyzeSemantics;
const codegen = yeti.codegen;
const printWasm = yeti.printWasm;
const components = yeti.components;
const literalOf = yeti.query.literalOf;
const typeOf = yeti.query.typeOf;
const parentType = yeti.query.parentType;
const valueType = yeti.query.valueType;
const MockFileSystem = yeti.FileSystem;

test "parse pointer" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\start(ptr: *i32) i32 {
        \\  0
        \\}
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start");
    const overloads = start.get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const overload = overloads[0];
    const parameters = overload.get(components.Parameters).slice();
    try expectEqual(parameters.len, 1);
    const ptr = parameters[0];
    try expectEqualStrings(literalOf(ptr), "ptr");
    const type_of = ptr.get(components.TypeAst).entity;
    try expectEqual(type_of.get(components.AstKind), .pointer);
    try expectEqualStrings(literalOf(type_of.get(components.Value).entity), "i32");
    const body = overload.get(components.Body).slice();
    try expectEqual(body.len, 1);
    const zero = body[0];
    try expectEqual(zero.get(components.AstKind), .int);
    try expectEqualStrings(literalOf(zero), "0");
}

test "parse pointer load" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\start(ptr: *i32) i32 {
        \\  *ptr
        \\}
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start");
    const overloads = start.get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const overload = overloads[0];
    const parameters = overload.get(components.Parameters).slice();
    try expectEqual(parameters.len, 1);
    const ptr = parameters[0];
    try expectEqualStrings(literalOf(ptr), "ptr");
    const type_of = ptr.get(components.TypeAst).entity;
    try expectEqual(type_of.get(components.AstKind), .pointer);
    try expectEqualStrings(literalOf(type_of.get(components.Value).entity), "i32");
    const body = overload.get(components.Body).slice();
    try expectEqual(body.len, 1);
    const load = body[0];
    try expectEqual(load.get(components.AstKind), .pointer);
    const value = load.get(components.Value).entity;
    try expectEqual(value.get(components.AstKind), .symbol);
    try expectEqualStrings(literalOf(value), "ptr");
}

test "parse pointer load after new line" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const module = try codebase.createEntity(.{});
    const code =
        \\start() i32 {
        \\  ptr = cast(*i32, 0)
        \\  *ptr
        \\}
    ;
    var tokens = try tokenize(module, code);
    try parse(module, &tokens);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start");
    const overloads = start.get(components.Overloads).slice();
    try expectEqual(overloads.len, 1);
    const overload = overloads[0];
    const parameters = overload.get(components.Parameters).slice();
    try expectEqual(parameters.len, 0);
    const body = overload.get(components.Body).slice();
    try expectEqual(body.len, 2);
    const load = body[1];
    try expectEqual(load.get(components.AstKind), .pointer);
    const value = load.get(components.Value).entity;
    try expectEqual(value.get(components.AstKind), .symbol);
    try expectEqualStrings(literalOf(value), "ptr");
}

test "analyze semantics of casting int literal to *i64" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start() *i64 {
        \\  cast(*i64, 0)
        \\}
    );
    _ = try analyzeSemantics(codebase, fs, "foo.yeti");
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    const return_type = start.get(components.ReturnType).entity;
    try expectEqualStrings(literalOf(return_type), "*i64");
    try expectEqual(parentType(return_type), builtins.Ptr);
    try expectEqualStrings(literalOf(valueType(return_type)), "i64");
    try expectEqual(valueType(return_type), builtins.I64);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 1);
    const cast = body[0];
    try expectEqual(cast.get(components.AstKind), .cast);
    const pointer_type = typeOf(cast);
    try expectEqual(parentType(pointer_type), builtins.Ptr);
    try expectEqual(valueType(pointer_type), builtins.I64);
    const zero = cast.get(components.Value).entity;
    try expectEqual(zero.get(components.AstKind), .int);
    try expectEqual(typeOf(zero), builtins.I32);
    try expectEqualStrings(literalOf(zero), "0");
}

test "analyze semantics of casting i32 to *i64" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start() *i64 {
        \\  i: i32 = 0
        \\  cast(*i64, i)
        \\}
    );
    _ = try analyzeSemantics(codebase, fs, "foo.yeti");
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    const return_type = start.get(components.ReturnType).entity;
    try expectEqualStrings(literalOf(return_type), "*i64");
    try expectEqual(parentType(return_type), builtins.Ptr);
    try expectEqualStrings(literalOf(valueType(return_type)), "i64");
    try expectEqual(valueType(return_type), builtins.I64);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 2);
    const i = blk: {
        const define = body[0];
        try expectEqual(define.get(components.AstKind), .define);
        try expectEqual(typeOf(define), builtins.Void);
        try expectEqualStrings(literalOf(define.get(components.Value).entity), "0");
        const local = define.get(components.Local).entity;
        try expectEqual(local.get(components.AstKind), .local);
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "i");
        try expectEqual(typeOf(local), builtins.I32);
        break :blk local;
    };
    const cast = body[1];
    try expectEqual(cast.get(components.AstKind), .cast);
    const pointer_type = typeOf(cast);
    try expectEqual(parentType(pointer_type), builtins.Ptr);
    try expectEqual(valueType(pointer_type), builtins.I64);
    try expectEqual(cast.get(components.Value).entity, i);
}

test "analyze semantics of pointer store" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start() void {
        \\  ptr = cast(*i64, 0)
        \\  *ptr = 10
        \\}
    );
    _ = try analyzeSemantics(codebase, fs, "foo.yeti");
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.Void);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 2);
    const ptr = blk: {
        const define = body[0];
        try expectEqual(define.get(components.AstKind), .define);
        try expectEqual(typeOf(define), builtins.Void);
        const cast = define.get(components.Value).entity;
        try expectEqual(cast.get(components.AstKind), .cast);
        const pointer_type = typeOf(cast);
        try expectEqual(parentType(pointer_type), builtins.Ptr);
        try expectEqual(valueType(pointer_type), builtins.I64);
        const zero = cast.get(components.Value).entity;
        try expectEqual(zero.get(components.AstKind), .int);
        try expectEqual(typeOf(zero), builtins.I32);
        try expectEqualStrings(literalOf(zero), "0");
        const local = define.get(components.Local).entity;
        try expectEqual(local.get(components.AstKind), .local);
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "ptr");
        try expectEqual(typeOf(local), pointer_type);
        break :blk local;
    };
    const store = body[1];
    try expectEqual(store.get(components.AstKind), .intrinsic);
    try expectEqual(store.get(components.Intrinsic), .store);
    try expectEqual(typeOf(store), builtins.Void);
    const arguments = store.get(components.Arguments).slice();
    try expectEqual(arguments.len, 2);
    try expectEqual(arguments[0], ptr);
    const rhs = arguments[1];
    try expectEqual(rhs.get(components.AstKind), .int);
    try expectEqual(typeOf(rhs), builtins.I64);
    try expectEqualStrings(literalOf(rhs), "10");
}

test "analyze semantics of pointer load" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start() i64 {
        \\  ptr = cast(*i64, 0)
        \\  *ptr
        \\}
    );
    _ = try analyzeSemantics(codebase, fs, "foo.yeti");
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    try expectEqual(start.get(components.ReturnType).entity, builtins.I64);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 2);
    const ptr = blk: {
        const define = body[0];
        try expectEqual(define.get(components.AstKind), .define);
        try expectEqual(typeOf(define), builtins.Void);
        const cast = define.get(components.Value).entity;
        try expectEqual(cast.get(components.AstKind), .cast);
        const pointer_type = typeOf(cast);
        try expectEqual(parentType(pointer_type), builtins.Ptr);
        try expectEqual(valueType(pointer_type), builtins.I64);
        const zero = cast.get(components.Value).entity;
        try expectEqual(zero.get(components.AstKind), .int);
        try expectEqual(typeOf(zero), builtins.I32);
        try expectEqualStrings(literalOf(zero), "0");
        const local = define.get(components.Local).entity;
        try expectEqual(local.get(components.AstKind), .local);
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "ptr");
        try expectEqual(typeOf(local), pointer_type);
        break :blk local;
    };
    const load = body[1];
    try expectEqual(load.get(components.AstKind), .intrinsic);
    try expectEqual(load.get(components.Intrinsic), .load);
    try expectEqual(typeOf(load), builtins.I64);
    const arguments = load.get(components.Arguments).slice();
    try expectEqual(arguments.len, 1);
    try expectEqual(arguments[0], ptr);
}

test "analyze semantics of adding *i64 and int literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start() *i64 {
        \\  ptr = cast(*i64, 0)
        \\  ptr + 1
        \\}
    );
    _ = try analyzeSemantics(codebase, fs, "foo.yeti");
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    const return_type = start.get(components.ReturnType).entity;
    try expectEqual(valueType(return_type), builtins.I64);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 2);
    {
        const define = body[0];
        try expectEqual(define.get(components.AstKind), .define);
        try expectEqual(typeOf(define), builtins.Void);
        const cast = define.get(components.Value).entity;
        try expectEqual(cast.get(components.AstKind), .cast);
        const pointer_type = typeOf(cast);
        try expectEqual(parentType(pointer_type), builtins.Ptr);
        try expectEqual(valueType(pointer_type), builtins.I64);
        const zero = cast.get(components.Value).entity;
        try expectEqual(zero.get(components.AstKind), .int);
        try expectEqual(typeOf(zero), builtins.I32);
        try expectEqualStrings(literalOf(zero), "0");
        const local = define.get(components.Local).entity;
        try expectEqual(local.get(components.AstKind), .local);
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "ptr");
        try expectEqual(typeOf(local), pointer_type);
    }
    const add = body[1];
    try expectEqual(add.get(components.AstKind), .intrinsic);
    try expectEqual(add.get(components.Intrinsic), .add_ptr_i32);
    try expectEqual(typeOf(add), return_type);
}

test "analyze semantics of subtracting *i64 and int literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start() *i64 {
        \\  ptr = cast(*i64, 0)
        \\  ptr - 1
        \\}
    );
    _ = try analyzeSemantics(codebase, fs, "foo.yeti");
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    const return_type = start.get(components.ReturnType).entity;
    try expectEqual(valueType(return_type), builtins.I64);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 2);
    {
        const define = body[0];
        try expectEqual(define.get(components.AstKind), .define);
        try expectEqual(typeOf(define), builtins.Void);
        const cast = define.get(components.Value).entity;
        try expectEqual(cast.get(components.AstKind), .cast);
        const pointer_type = typeOf(cast);
        try expectEqual(parentType(pointer_type), builtins.Ptr);
        try expectEqual(valueType(pointer_type), builtins.I64);
        const zero = cast.get(components.Value).entity;
        try expectEqual(zero.get(components.AstKind), .int);
        try expectEqual(typeOf(zero), builtins.I32);
        try expectEqualStrings(literalOf(zero), "0");
        const local = define.get(components.Local).entity;
        try expectEqual(local.get(components.AstKind), .local);
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "ptr");
        try expectEqual(typeOf(local), pointer_type);
    }
    const add = body[1];
    try expectEqual(add.get(components.AstKind), .intrinsic);
    try expectEqual(add.get(components.Intrinsic), .subtract_ptr_i32);
    try expectEqual(typeOf(add), return_type);
}

test "analyze semantics of comparing two *i64" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const builtins = codebase.get(components.Builtins);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start() i32 {
        \\  ptr = cast(*i64, 0)
        \\  ptr == ptr
        \\}
    );
    _ = try analyzeSemantics(codebase, fs, "foo.yeti");
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    try expectEqualStrings(literalOf(start.get(components.Module).entity), "foo");
    try expectEqualStrings(literalOf(start.get(components.Name).entity), "start");
    try expectEqual(start.get(components.Parameters).len(), 0);
    const return_type = start.get(components.ReturnType).entity;
    try expectEqual(return_type, builtins.I32);
    const body = start.get(components.Body).slice();
    try expectEqual(body.len, 2);
    {
        const define = body[0];
        try expectEqual(define.get(components.AstKind), .define);
        try expectEqual(typeOf(define), builtins.Void);
        const cast = define.get(components.Value).entity;
        try expectEqual(cast.get(components.AstKind), .cast);
        const pointer_type = typeOf(cast);
        try expectEqual(parentType(pointer_type), builtins.Ptr);
        try expectEqual(valueType(pointer_type), builtins.I64);
        const zero = cast.get(components.Value).entity;
        try expectEqual(zero.get(components.AstKind), .int);
        try expectEqual(typeOf(zero), builtins.I32);
        try expectEqualStrings(literalOf(zero), "0");
        const local = define.get(components.Local).entity;
        try expectEqual(local.get(components.AstKind), .local);
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "ptr");
        try expectEqual(typeOf(local), pointer_type);
    }
    const equal = body[1];
    try expectEqual(equal.get(components.AstKind), .intrinsic);
    try expectEqual(equal.get(components.Intrinsic), .equal);
    try expectEqual(typeOf(equal), builtins.I32);
}

test "codegen of casting int literal to *i64" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start() *i64 {
        \\  cast(*i64, 0)
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    const wasm_instructions = start.get(components.WasmInstructions).slice();
    try expectEqual(wasm_instructions.len, 1);
    const constant = wasm_instructions[0];
    try expectEqual(constant.get(components.WasmInstructionKind), .i32_const);
    try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "0");
}

test "codegen of storing through pointer" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start() void {
        \\  ptr = cast(*i64, 0)
        \\  *ptr = 10
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    const wasm_instructions = start.get(components.WasmInstructions).slice();
    try expectEqual(wasm_instructions.len, 5);
    {
        const constant = wasm_instructions[0];
        try expectEqual(constant.get(components.WasmInstructionKind), .i32_const);
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "0");
    }
    {
        const local_set = wasm_instructions[1];
        try expectEqual(local_set.get(components.WasmInstructionKind), .local_set);
        const local = local_set.get(components.Local).entity;
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "ptr");
    }
    {
        const local_get = wasm_instructions[2];
        try expectEqual(local_get.get(components.WasmInstructionKind), .local_get);
        const local = local_get.get(components.Local).entity;
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "ptr");
    }
    {
        const constant = wasm_instructions[3];
        try expectEqual(constant.get(components.WasmInstructionKind), .i64_const);
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "10");
    }
    {
        try expectEqual(wasm_instructions[4].get(components.WasmInstructionKind), .i64_store);
    }
}

test "codegen of loading through pointer" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start() i64 {
        \\  ptr = cast(*i64, 0)
        \\  *ptr
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    const wasm_instructions = start.get(components.WasmInstructions).slice();
    try expectEqual(wasm_instructions.len, 4);
    {
        const constant = wasm_instructions[0];
        try expectEqual(constant.get(components.WasmInstructionKind), .i32_const);
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "0");
    }
    {
        const local_set = wasm_instructions[1];
        try expectEqual(local_set.get(components.WasmInstructionKind), .local_set);
        const local = local_set.get(components.Local).entity;
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "ptr");
    }
    {
        const local_get = wasm_instructions[2];
        try expectEqual(local_get.get(components.WasmInstructionKind), .local_get);
        const local = local_get.get(components.Local).entity;
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "ptr");
    }
    try expectEqual(wasm_instructions[3].get(components.WasmInstructionKind), .i64_load);
}

test "codegen of adding pointer and int literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start() *i64 {
        \\  ptr = cast(*i64, 0)
        \\  ptr + 1
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    const wasm_instructions = start.get(components.WasmInstructions).slice();
    try expectEqual(wasm_instructions.len, 5);
    {
        const constant = wasm_instructions[0];
        try expectEqual(constant.get(components.WasmInstructionKind), .i32_const);
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "0");
    }
    {
        const local_set = wasm_instructions[1];
        try expectEqual(local_set.get(components.WasmInstructionKind), .local_set);
        const local = local_set.get(components.Local).entity;
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "ptr");
    }
    {
        const local_get = wasm_instructions[2];
        try expectEqual(local_get.get(components.WasmInstructionKind), .local_get);
        const local = local_get.get(components.Local).entity;
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "ptr");
    }
    {
        const constant = wasm_instructions[3];
        try expectEqual(constant.get(components.WasmInstructionKind), .i32_const);
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "8");
    }
    try expectEqual(wasm_instructions[4].get(components.WasmInstructionKind), .i32_add);
}

test "codegen of subtracting pointer and int literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start() *i64 {
        \\  ptr = cast(*i64, 0)
        \\  ptr - 1
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    const wasm_instructions = start.get(components.WasmInstructions).slice();
    try expectEqual(wasm_instructions.len, 5);
    {
        const constant = wasm_instructions[0];
        try expectEqual(constant.get(components.WasmInstructionKind), .i32_const);
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "0");
    }
    {
        const local_set = wasm_instructions[1];
        try expectEqual(local_set.get(components.WasmInstructionKind), .local_set);
        const local = local_set.get(components.Local).entity;
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "ptr");
    }
    {
        const local_get = wasm_instructions[2];
        try expectEqual(local_get.get(components.WasmInstructionKind), .local_get);
        const local = local_get.get(components.Local).entity;
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "ptr");
    }
    {
        const constant = wasm_instructions[3];
        try expectEqual(constant.get(components.WasmInstructionKind), .i32_const);
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "8");
    }
    try expectEqual(wasm_instructions[4].get(components.WasmInstructionKind), .i32_sub);
}

test "codegen of comparing two *i64" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    const op_strings = [_][]const u8{ "==", "!=", ">=", ">", "<=", "<" };
    const ops = [_]components.WasmInstructionKind{ .i32_eq, .i32_ne, .i32_ge, .i32_gt, .i32_le, .i32_lt };
    for (op_strings) |op_string, i| {
        var fs = try MockFileSystem.init(&arena);
        _ = try fs.newFile("foo.yeti", try std.fmt.allocPrint(arena.allocator(),
            \\start() i32 {{
            \\  ptr = cast(*i64, 0)
            \\  ptr {s} ptr
            \\}}
        , .{op_string}));
        const module = try analyzeSemantics(codebase, fs, "foo.yeti");
        try codegen(module);
        const top_level = module.get(components.TopLevel);
        const start = top_level.findString("start").get(components.Overloads).slice()[0];
        const wasm_instructions = start.get(components.WasmInstructions).slice();
        try expectEqual(wasm_instructions.len, 5);
        {
            const constant = wasm_instructions[0];
            try expectEqual(constant.get(components.WasmInstructionKind), .i32_const);
            try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "0");
        }
        {
            const local_set = wasm_instructions[1];
            try expectEqual(local_set.get(components.WasmInstructionKind), .local_set);
            const local = local_set.get(components.Local).entity;
            try expectEqualStrings(literalOf(local.get(components.Name).entity), "ptr");
        }
        {
            const local_get = wasm_instructions[2];
            try expectEqual(local_get.get(components.WasmInstructionKind), .local_get);
            const local = local_get.get(components.Local).entity;
            try expectEqualStrings(literalOf(local.get(components.Name).entity), "ptr");
        }
        {
            const local_get = wasm_instructions[3];
            try expectEqual(local_get.get(components.WasmInstructionKind), .local_get);
            const local = local_get.get(components.Local).entity;
            try expectEqualStrings(literalOf(local.get(components.Name).entity), "ptr");
        }
        try expectEqual(wasm_instructions[4].get(components.WasmInstructionKind), ops[i]);
    }
}

test "codegen of subtracting two *i64" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start() i32 {
        \\  ptr = cast(*i64, 0)
        \\  ptr - ptr
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const top_level = module.get(components.TopLevel);
    const start = top_level.findString("start").get(components.Overloads).slice()[0];
    const wasm_instructions = start.get(components.WasmInstructions).slice();
    try expectEqual(wasm_instructions.len, 7);
    {
        const constant = wasm_instructions[0];
        try expectEqual(constant.get(components.WasmInstructionKind), .i32_const);
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "0");
    }
    {
        const local_set = wasm_instructions[1];
        try expectEqual(local_set.get(components.WasmInstructionKind), .local_set);
        const local = local_set.get(components.Local).entity;
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "ptr");
    }
    {
        const local_get = wasm_instructions[2];
        try expectEqual(local_get.get(components.WasmInstructionKind), .local_get);
        const local = local_get.get(components.Local).entity;
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "ptr");
    }
    {
        const local_get = wasm_instructions[3];
        try expectEqual(local_get.get(components.WasmInstructionKind), .local_get);
        const local = local_get.get(components.Local).entity;
        try expectEqualStrings(literalOf(local.get(components.Name).entity), "ptr");
    }
    try expectEqual(wasm_instructions[4].get(components.WasmInstructionKind), .i32_sub);
    {
        const constant = wasm_instructions[5];
        try expectEqual(constant.get(components.WasmInstructionKind), .i32_const);
        try expectEqualStrings(literalOf(constant.get(components.Constant).entity), "8");
    }
    try expectEqual(wasm_instructions[6].get(components.WasmInstructionKind), .i32_div);
}

test "print wasm pointer" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start() *i64 {
        \\  cast(*i64, 0)
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/start (result i32)
        \\    (i32.const 0))
        \\
        \\  (export "_start" (func $foo/start)))
    );
}

test "print wasm pointer store" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start() void {
        \\  ptr = cast(*i64, 0)
        \\  *ptr = 10
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/start
        \\    (local $ptr i32)
        \\    (i32.const 0)
        \\    (local.set $ptr)
        \\    (local.get $ptr)
        \\    (i64.const 10)
        \\    i64.store)
        \\
        \\  (export "_start" (func $foo/start))
        \\
        \\  (memory 1)
        \\  (export "memory" (memory 0)))
    );
}

test "print wasm pointer load" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start() i64 {
        \\  ptr = cast(*i64, 0)
        \\  *ptr
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/start (result i64)
        \\    (local $ptr i32)
        \\    (i32.const 0)
        \\    (local.set $ptr)
        \\    (local.get $ptr)
        \\    i64.load)
        \\
        \\  (export "_start" (func $foo/start))
        \\
        \\  (memory 1)
        \\  (export "memory" (memory 0)))
    );
}

test "print wasm pointer load u8" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\start() u8 {
        \\  ptr = cast(*u8, 0)
        \\  *ptr
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/start (result i32)
        \\    (local $ptr i32)
        \\    (i32.const 0)
        \\    (local.set $ptr)
        \\    (local.get $ptr)
        \\    i32.load8_u)
        \\
        \\  (export "_start" (func $foo/start))
        \\
        \\  (memory 1)
        \\  (export "memory" (memory 0)))
    );
}

test "print wasm pointer as parameter" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\@export
        \\f(ptr: *i32) i32 {
        \\  0
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/f..ptr.ptr.i32 (param $ptr i32) (result i32)
        \\    (i32.const 0))
        \\
        \\  (export "f" (func $foo/f..ptr.ptr.i32)))
    );
}

test "print wasm adding pointer and int literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\@export
        \\f(ptr: *i64) *i64 {
        \\  ptr + 1
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/f..ptr.ptr.i64 (param $ptr i32) (result i32)
        \\    (local.get $ptr)
        \\    (i32.const 8)
        \\    i32.add)
        \\
        \\  (export "f" (func $foo/f..ptr.ptr.i64)))
    );
}

test "print wasm subtracting pointer and int literal" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\@export
        \\f(ptr: *i64) *i64 {
        \\  ptr - 1
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/f..ptr.ptr.i64 (param $ptr i32) (result i32)
        \\    (local.get $ptr)
        \\    (i32.const 8)
        \\    i32.sub)
        \\
        \\  (export "f" (func $foo/f..ptr.ptr.i64)))
    );
}

test "print wasm adding pointer and i32" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    var codebase = try initCodebase(&arena);
    var fs = try MockFileSystem.init(&arena);
    _ = try fs.newFile("foo.yeti",
        \\@export
        \\f(ptr: *i64, len: i32) *i64 {
        \\  ptr + len
        \\}
    );
    const module = try analyzeSemantics(codebase, fs, "foo.yeti");
    try codegen(module);
    const wasm = try printWasm(module);
    try expectEqualStrings(wasm,
        \\(module
        \\
        \\  (func $foo/f..ptr.ptr.i64..len.i32 (param $ptr i32) (param $len i32) (result i32)
        \\    (local.get $ptr)
        \\    (local.get $len)
        \\    (i32.const 8)
        \\    i32.mul
        \\    i32.add)
        \\
        \\  (export "f" (func $foo/f..ptr.ptr.i64..len.i32)))
    );
}
