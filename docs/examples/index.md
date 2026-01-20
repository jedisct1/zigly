# Examples

Complete, runnable examples demonstrating common Zigly patterns. Each example includes source code, configuration, and testing instructions.

## Available Examples

### [Simple Proxy](simple-proxy.md)

A minimal CDN proxy that forwards requests to an origin server. Shows basic `downstream()` and `proxy()` usage.

### [API Gateway](api-gateway.md)

Routes requests to different backends based on URL path prefixes. Demonstrates path extraction and conditional routing.

### [Rate Limiter](rate-limiter.md)

Implements IP-based rate limiting using Fastly's Edge Rate Limiting primitives. Shows how to protect your origin from abuse.

### [Geo Redirect](geo-redirect.md)

Redirects users to country-specific sites based on their IP geolocation. Demonstrates geo lookup and redirect handling.

## Running Examples

All examples are in `tmp/examples/` and can be built with:

```bash
zig build -Doptimize=ReleaseSmall
```

Test with a local emulator ([Viceroy](https://github.com/fastly/Viceroy) or [Fastlike](https://github.com/avidal/fastlike)):

```bash
cd tmp/examples
viceroy -C fastly.toml ../../zig-out/bin/<example>.wasm
```

Then test with curl:

```bash
curl http://127.0.0.1:7676/your/path
```

## Example Structure

Each example follows the same pattern:

```zig
const std = @import("std");
const zigly = @import("zigly");

fn start() !void {
    var downstream = try zigly.downstream();
    // Your logic here
}

pub export fn _start() callconv(.c) void {
    start() catch |err| {
        std.debug.print("Error: {}\n", .{err});
    };
}
```

The `_start` function is the WASM entry point. It wraps the main logic in a function that can return errors, making error handling cleaner.

## More Examples

Additional patterns can be found in the guides:

- [Proxying Guide](../guides/proxying.md) - Backend selection, host override
- [Caching Guide](../guides/caching.md) - Edge caching strategies
- [Device Detection Guide](../guides/device-detection.md) - Mobile optimization
