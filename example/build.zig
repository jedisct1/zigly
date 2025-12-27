const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .wasm32,
            .os_tag = .wasi,
        },
    });
    const optimize = b.standardOptimizeOption(.{});

    const zigly = b.dependency("zigly", .{
        .target = target,
        .optimize = optimize,
    });

    const exe_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_module.addImport("zigly", zigly.module("zigly"));
    exe_module.linkLibrary(zigly.artifact("zigly"));

    const exe = b.addExecutable(.{
        .name = "zigly_example",
        .root_module = exe_module,
    });

    b.installArtifact(exe);
}
