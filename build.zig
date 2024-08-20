const std = @import("std");

const TESTS = [_][]const u8{
    "/HTTPServer.zig",
    "/Tree.zig",
    "/UUID.zig",
    "/Request/Client.zig",
};

const EXAMPLES = [_][]const u8{"endpoint_simple"};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mox = b.addModule("mox", .{
        .root_source_file = b.path("src/mox.zig"),
        .target = target,
        .optimize = optimize,
    });

    const unit_tests_step = b.step("test", "Run all tests");
    inline for (TESTS) |file| {
        const test_file = b.addTest(.{
            .root_source_file = b.path("src" ++ std.fs.path.sep_str ++ file),
            .target = target,
            .optimize = optimize,
        });
        unit_tests_step.dependOn(&b.addRunArtifact(test_file).step);
    }

    const examples_step = b.step("run-example", "Build and run example");

    inline for (EXAMPLES) |name| {
        const example = b.addExecutable(.{
            .name = name,
            .root_source_file = b.path("examples" ++ std.fs.path.sep_str ++ name ++ ".zig"),
            .target = target,
            .optimize = optimize,
        });
        example.root_module.addImport("mox", mox);
        const run_cmd = b.addRunArtifact(example);
        run_cmd.step.dependOn(b.getInstallStep());
        const desc = "Run the " ++ name ++ " example";
        const run_step = b.step(name, desc);
        run_step.dependOn(&run_cmd.step);

        examples_step.dependOn(&run_cmd.step);
    }
}
