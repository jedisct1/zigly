const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .wasm32,
            .os_tag = .wasi,
        },
    });
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "package",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const zigly = b.dependency("zigly", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zigly", zigly.module("zigly"));
    exe.linkLibrary(zigly.artifact("zigly"));

    b.installArtifact(exe);
}
