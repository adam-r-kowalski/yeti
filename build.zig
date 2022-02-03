const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("yeti", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    var tests = b.addTest("src/compiler.zig");
    tests.setBuildMode(mode);

    var test_all = b.addTest("src/tests/test_all.zig");
    test_all.addPackagePath("yeti", "src/compiler.zig");
    test_all.setBuildMode(mode);

    const test_step = b.step("test", "Run compiler tests");
    test_step.dependOn(&tests.step);
    test_step.dependOn(&test_all.step);
}
