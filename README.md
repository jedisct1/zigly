![Zigly](logo.png)
========

A Zig library for building [Fastly Compute](https://www.fastly.com/products/edge-compute) services.

## Quick Example

```zig
const zigly = @import("zigly");

pub fn main() !void {
    var downstream = try zigly.downstream();

    // Proxy to origin
    try downstream.proxy("origin", "api.example.com");

    // Or build a custom response
    // try downstream.response.setStatus(200);
    // try downstream.response.body.writeAll("Hello from the edge!");
    // try downstream.response.finish();
}
```

## Installation

Add the dependency:

```sh
zig fetch --save=zigly https://github.com/jedisct1/zigly/archive/refs/tags/0.1.12.tar.gz
```

In `build.zig`:

```zig
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
    .name = "my_app",
    .root_module = exe_module,
});
b.installArtifact(exe);
```

Target `wasm32-wasi`:

```zig
const target = b.standardTargetOptions(.{
    .default_target = .{ .cpu_arch = .wasm32, .os_tag = .wasi }
});
```

Build with `zig build -Doptimize=ReleaseSmall`.

## Documentation

See **[docs/index.md](docs/index.md)** for full documentation including:

- Getting started guide
- API reference for all modules (HTTP, caching, rate limiting, geolocation, device detection, etc.)
- Practical guides and examples
- Deployment instructions

## Requirements

- Zig 0.16.0 or later
- Local testing: [Viceroy](https://github.com/fastly/Viceroy) or [Fastlike](https://github.com/avidal/fastlike)
- [Fastly CLI](https://github.com/fastly/cli) for deployment

## License

See the repository for license information.
