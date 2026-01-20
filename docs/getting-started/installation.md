# Installation

This guide covers adding Zigly to your Zig project and setting up the build configuration.

## Prerequisites

- Zig 0.16.0 or later
- A Fastly Compute account (for deployment)

## Creating a New Project

Create a new directory and initialize it:

```bash
mkdir my-edge-service
cd my-edge-service
zig init
```

## Adding Zigly

Zigly can be added as a dependency using Zig's package manager. Add it to your `build.zig.zon`:

```zig
.{
    .name = "my-edge-service",
    .version = "0.0.1",
    .dependencies = .{
        .zigly = .{
            .url = "https://github.com/username/zigly/archive/main.tar.gz",
            // Add the hash after first build attempt
        },
    },
}
```

Alternatively, clone Zigly into your project or add it as a git submodule:

```bash
git submodule add https://github.com/username/zigly.git lib/zigly
```

## Build Configuration

Update your `build.zig` to target WebAssembly and include Zigly:

```zig
const std = @import("std");

pub fn build(b: *std.Build) !void {
    // Target wasm32-wasi for Fastly Compute
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .wasm32,
            .os_tag = .wasi,
        },
    });
    const optimize = b.standardOptimizeOption(.{});

    // Add Zigly module
    const zigly_dep = b.dependency("zigly", .{
        .target = target,
        .optimize = optimize,
    });

    const exe_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_module.addImport("zigly", zigly_dep.module("zigly"));

    const exe = b.addExecutable(.{
        .name = "service",
        .root_module = exe_module,
    });
    b.installArtifact(exe);
}
```

If using a local copy of Zigly:

```zig
const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .wasm32,
            .os_tag = .wasi,
        },
    });
    const optimize = b.standardOptimizeOption(.{});

    // Local Zigly module
    const zigly_module = b.addModule("zigly", .{
        .root_source_file = b.path("lib/zigly/src/zigly.zig"),
    });

    const exe_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_module.addImport("zigly", zigly_module);

    const exe = b.addExecutable(.{
        .name = "service",
        .root_module = exe_module,
    });
    b.installArtifact(exe);
}
```

## Building

Build with size optimizations (recommended for edge deployment):

```bash
zig build -Doptimize=ReleaseSmall
```

The compiled WebAssembly binary will be at `zig-out/bin/service.wasm`.

## Project Structure

A typical Zigly project looks like:

```
my-edge-service/
├── build.zig
├── build.zig.zon
├── fastly.toml        # Fastly configuration
├── src/
│   └── main.zig       # Entry point
└── lib/
    └── zigly/         # If using local copy
```

## Next Steps

- [Hello World](hello-world.md) - Write your first edge service
- [Testing Locally](testing-locally.md) - Test locally before deploying
