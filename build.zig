const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mox = b.addModule("mox", .{
        .root_source_file = b.path("src/mox.zig"),
        .target = target,
        .optimize = optimize,
    });

    const root_files = [_][]const u8{
        "src/HTTPServer.zig",
        "src/Tree.zig",
        "src/UUID.zig",
        "src/Request/Client.zig",
    };

    const unit_tests_step = b.step("test", "Run all tests");
    for (root_files) |file| {
        const test_file = b.addTest(.{ .root_source_file = b.path(file) });
        unit_tests_step.dependOn(&b.addRunArtifact(test_file).step);
    }

    const example = b.step("run-example", "Build and run example");
    const example_exe = b.addExecutable(.{
        .name = "endpoint_simple",
        .root_source_file = b.path("examples/endpoint_simple/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    example_exe.root_module.addImport("mox", mox);
    example.dependOn(&b.addRunArtifact(example_exe).step);
}
