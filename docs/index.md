# Zigly

Zigly is a Zig library for building [Fastly Compute](https://www.fastly.com/products/edge-compute) services. It provides high-level bindings for Fastly's edge computing platform, targeting WebAssembly.

## Why Zig?

Fastly Compute bills based on execution time and memory usage. The Zig compiler produces WebAssembly modules that are exceptionally small, fast, and memory-efficient—often significantly smaller than equivalent Rust code, and orders of magnitude smaller than JavaScript bundles.

This translates directly to lower costs: smaller binaries mean faster cold starts, less memory overhead, and reduced execution time. If you're running edge compute at scale, Zig can meaningfully reduce your Fastly bill while providing predictable, low-latency performance.

## Quick Example

```zig
const zigly = @import("zigly");

pub fn main() !void {
    var downstream = try zigly.downstream();

    // Option 1: Proxy to a backend
    try downstream.proxy("origin", "api.example.com");

    // Option 2: Build a custom response
    // try downstream.response.setStatus(200);
    // try downstream.response.body.writeAll("Hello from the edge!");
    // try downstream.response.finish();
}
```

## Features

- **HTTP handling** - Full request/response manipulation with headers and bodies
- **Caching** - Simple and transactional cache APIs with TTL and stale-while-revalidate
- **Rate limiting** - Edge rate limiting with rate counters and penalty boxes
- **Geolocation** - IP-based location lookup
- **Device detection** - Identify mobile, tablet, and desktop devices
- **Backends** - Static and dynamic backend management with SSL support
- **KV store** - Key-value storage at the edge
- **ACLs** - IP-based access control lists
- **Logging** - Send logs to external endpoints
- **Purging** - Invalidate cached content by surrogate key

## Documentation

### Getting Started

1. [Installation](getting-started/installation.md) - Add Zigly to your project
2. [Hello World](getting-started/hello-world.md) - Build your first edge service
3. [Testing Locally](getting-started/testing-locally.md) - Run services locally
4. [Deployment](getting-started/deployment.md) - Deploy to Fastly Compute

### Concepts

- [Architecture](concepts/architecture.md) - How Zigly maps to Fastly APIs
- [Error Handling](concepts/error-handling.md) - Working with FastlyError
- [Memory Management](concepts/memory.md) - Allocator patterns

### Guides

- [Proxying](guides/proxying.md) - CDN proxy patterns
- [Caching](guides/caching.md) - Cache strategies
- [Rate Limiting](guides/rate-limiting.md) - Protect your origins
- [Geo Routing](guides/geo-routing.md) - Location-based routing
- [Device Detection](guides/device-detection.md) - Mobile optimization

### API Reference

- [HTTP](reference/http.md) - Request, Response, Headers, Body, Downstream
- [Cache](reference/cache.md) - Simple and transactional caching
- [Backend](reference/backend.md) - Static and dynamic backends
- [ERL](reference/erl.md) - Rate limiting
- [KV Store](reference/kv.md) - Key-value storage
- [Geo](reference/geo.md) - Geolocation
- [Device](reference/device.md) - Device detection
- [Dictionary](reference/dictionary.md) - Edge dictionaries
- [ACL](reference/acl.md) - Access control lists
- [Logger](reference/logger.md) - Logging endpoints
- [Purge](reference/purge.md) - Cache purging
- [User Agent](reference/useragent.md) - UA parsing
- [Runtime](reference/runtime.md) - vCPU metrics

### Examples

- [Simple Proxy](examples/simple-proxy.md) - Basic CDN proxy
- [API Gateway](examples/api-gateway.md) - Multi-backend routing
- [Rate Limiter](examples/rate-limiter.md) - IP-based rate limiting
- [Geo Redirect](examples/geo-redirect.md) - Country-based redirects

## Requirements

- Zig 0.16.0 or later
- Local testing: [Viceroy](https://github.com/fastly/Viceroy) or [Fastlike](https://github.com/avidal/fastlike)
- [Fastly CLI](https://github.com/fastly/cli) for deployment

## License

See the repository for license information.
