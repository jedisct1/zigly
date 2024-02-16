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
        .root_source_file = .{ .path = "src/zigly.zig" },
    });

    const lib = b.addStaticLibrary(.{
        .name = "zigly",
        .root_source_file = .{ .path = "src/zigly.zig" },
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);

    const exe = b.addExecutable(.{
        .name = "zig-tests",
        .root_source_file = .{ .path = "src/tests.zig" },
        .target = target,
        .optimize = optimize,
        .strip = true,
    });
    b.installArtifact(exe);
}
