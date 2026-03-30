const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "vitals",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run vitals");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run unit tests");

    const src_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    test_step.dependOn(&b.addRunArtifact(src_tests).step);

    const cpu_mod = b.createModule(.{
        .root_source_file = b.path("src/collector/cpu.zig"),
        .target = target,
        .optimize = optimize,
    });

    const cpu_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/cpu_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "cpu", .module = cpu_mod },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(cpu_tests).step);

    const memory_mod = b.createModule(.{
        .root_source_file = b.path("src/collector/memory.zig"),
        .target = target,
        .optimize = optimize,
    });

    const memory_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/memory_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "memory", .module = memory_mod },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(memory_tests).step);

    const all_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("all_tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    test_step.dependOn(&b.addRunArtifact(all_tests).step);
}
