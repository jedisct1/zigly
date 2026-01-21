const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .wasm32,
            .os_tag = .wasi,
        },
    });
    const optimize = b.standardOptimizeOption(.{});

    // Zigly module for external packages and examples
    const zigly_module = b.addModule("zigly", .{
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

    // Example builds
    const examples = [_][]const u8{
        "simple_proxy",
        "api_gateway",
        "rate_limiter",
        "geo_redirect",
        "query_router",
        "url_rewriter",
    };

    for (examples) |example| {
        const example_path = b.fmt("examples/{s}.zig", .{example});
        const example_module = b.createModule(.{
            .root_source_file = b.path(example_path),
            .target = target,
            .optimize = optimize,
        });
        example_module.addImport("zigly", zigly_module);

        const example_exe = b.addExecutable(.{
            .name = example,
            .root_module = example_module,
        });
        b.installArtifact(example_exe);
    }
}
