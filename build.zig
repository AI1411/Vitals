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

    const disk_mod = b.createModule(.{
        .root_source_file = b.path("src/collector/disk.zig"),
        .target = target,
        .optimize = optimize,
    });

    const disk_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/disk_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "disk", .module = disk_mod },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(disk_tests).step);

    const network_mod = b.createModule(.{
        .root_source_file = b.path("src/collector/network.zig"),
        .target = target,
        .optimize = optimize,
    });

    const network_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/network_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "network", .module = network_mod },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(network_tests).step);

    const loadavg_mod = b.createModule(.{
        .root_source_file = b.path("src/collector/loadavg.zig"),
        .target = target,
        .optimize = optimize,
    });

    const loadavg_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/loadavg_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "loadavg", .module = loadavg_mod },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(loadavg_tests).step);

    const parser_mod = b.createModule(.{
        .root_source_file = b.path("src/utils/parser.zig"),
        .target = target,
        .optimize = optimize,
    });

    const parser_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/parser_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "parser", .module = parser_mod },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(parser_tests).step);

    const size_mod = b.createModule(.{
        .root_source_file = b.path("src/utils/size.zig"),
        .target = target,
        .optimize = optimize,
    });

    const size_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/size_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "size", .module = size_mod },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(size_tests).step);

    const proc_reader_mod = b.createModule(.{
        .root_source_file = b.path("src/utils/proc_reader.zig"),
        .target = target,
        .optimize = optimize,
    });

    const process_mod = b.createModule(.{
        .root_source_file = b.path("src/collector/process.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "../utils/proc_reader.zig", .module = proc_reader_mod },
        },
    });

    const process_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/process_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "process", .module = process_mod },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(process_tests).step);

    const all_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("all_tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    test_step.dependOn(&b.addRunArtifact(all_tests).step);
}
