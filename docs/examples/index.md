# Examples

Complete, runnable examples demonstrating common Zigly patterns. Each example includes source code, configuration, and testing instructions.

## Available Examples

### [Simple Proxy](simple-proxy.md)

A minimal CDN proxy that forwards requests to an origin server. Shows basic `downstream()` and `proxy()` usage.

### [API Gateway](api-gateway.md)

Routes requests to different backends based on URL path prefixes. Demonstrates path extraction and conditional routing.

### [Rate Limiter](rate-limiter.md)

Implements IP and path-based rate limiting using Fastly's Edge Rate Limiting primitives. Shows how to protect your origin with endpoint-specific limits.

### [Geo Redirect](geo-redirect.md)

Redirects users to country-specific sites based on their IP geolocation. Demonstrates geo lookup and redirect handling.

### [Query Router](query-router.md)

Routes requests based on query parameters. Demonstrates `parseQueryParams()` for extracting and using URL parameters.

### [URL Rewriter](url-rewriter.md)

Rewrites and transforms request URLs before proxying. Demonstrates `getUri()`, `getPathAndQuery()`, and `setUriString()` for URL manipulation.

## Running Examples

All examples are in `examples/` and can be built with:

```bash
zig build -Doptimize=ReleaseSmall
```

Test with a local emulator ([Viceroy](https://github.com/fastly/Viceroy) or [Fastlike](https://github.com/avidal/fastlike)):

```bash
cd examples
viceroy -C fastly.toml ../zig-out/bin/<example>.wasm
```

Then test with curl:

```bash
curl http://127.0.0.1:7676/your/path
```

## Example Structure

Each example uses a simple `main()` function:

```zig
const std = @import("std");
const zigly = @import("zigly");

pub fn main() !void {
    var downstream = try zigly.downstream();
    // Your logic here
}
```

Zig automatically generates the WASI `_start` entry point when targeting `wasm32-wasi` with a `pub fn main()` function. Errors propagate naturally through Zig's error handling.

## More Examples

Additional patterns can be found in the guides:

- [Proxying Guide](../guides/proxying.md) - Backend selection, host override
- [Caching Guide](../guides/caching.md) - Edge caching strategies
- [Device Detection Guide](../guides/device-detection.md) - Mobile optimization
