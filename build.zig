const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "mox",
        .root_source_file = b.path("src/mox.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(lib);

    const root_files = [_][]const u8{
        "src/mox.zig",
        "src/Tree.zig",
    };

    const unit_tests_step = b.step("test", "Run all tests");
    for (root_files) |file| {
        const test_file = b.addTest(.{ .root_source_file = b.path(file) });
        unit_tests_step.dependOn(&b.addRunArtifact(test_file).step);
    }
}
