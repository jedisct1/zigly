const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .wasm32,
            .os_tag = .wasi,
        },
    });
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("zigly", .{
        .root_source_file = b.path("src/zigly.zig"),
    });

    const lib_module = b.createModule(.{
        .root_source_file = b.path("src/zigly.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .name = "zigly",
        .root_module = lib_module,
    });
    b.installArtifact(lib);

    const exe_module = b.createModule(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "zig-tests",
        .root_module = exe_module,
    });
    b.installArtifact(exe);
}
