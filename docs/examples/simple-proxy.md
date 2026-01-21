# Simple Proxy

A minimal CDN proxy that forwards requests to an origin server, adding a header to mark edge processing.

## Source Code

```zig
const std = @import("std");
const zigly = @import("zigly");

pub fn main() !void {
    var downstream = try zigly.downstream();

    // Add a custom header to identify edge processing
    try downstream.request.headers.set("X-Edge-Processed", "true");

    // Proxy to the origin backend
    try downstream.proxy("origin", null);
}
```

## How It Works

1. `zigly.downstream()` returns the incoming client connection
2. `downstream.request.headers.set()` adds a header to the request before forwarding
3. `downstream.proxy("origin", null)` forwards the request to the backend named "origin"

The second argument to `proxy()` is an optional host override. Passing `null` uses the backend's configured host.

## Backend Configuration

In `fastly.toml`:

```toml
[local_server.backends.origin]
url = "https://httpbin.org"
```

For production, configure the backend in Fastly's dashboard or via CLI.

## Testing

```bash
curl -v http://127.0.0.1:7676/headers
```

The response will show `X-Edge-Processed: true` in the request headers echoed back by httpbin.

## Variations

**Host override:**
```zig
try downstream.proxy("origin", "api.example.com");
```

**Add multiple headers:**
```zig
try downstream.request.headers.set("X-Edge-Region", "us-east");
try downstream.request.headers.set("X-Request-ID", request_id);
```

**Conditional proxying:**
```zig
var method_buf: [16]u8 = undefined;
const method = try downstream.request.getMethod(&method_buf);

if (std.mem.eql(u8, method, "GET")) {
    try downstream.proxy("cache", null);
} else {
    try downstream.proxy("origin", null);
}
```

## Related

- [Proxying Guide](../guides/proxying.md)
- [Backend Reference](../reference/backend.md)
- [HTTP Reference](../reference/http.md)
