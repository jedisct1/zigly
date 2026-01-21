# Hello World

Build your first Fastly Compute service with Zigly.

## The Entry Point

Create `src/main.zig`:

```zig
const zigly = @import("zigly");

pub fn main() !void {
    // Get the downstream connection (client request)
    var downstream = try zigly.downstream();

    // Set response status and body
    try downstream.response.setStatus(200);
    try downstream.response.headers.set("Content-Type", "text/plain");
    try downstream.response.body.writeAll("Hello from the edge!");

    // Send the response
    try downstream.response.finish();
}
```

Zig automatically generates the WASI `_start` entry point when targeting `wasm32-wasi`. Your `main()` function is the entry point for your service logic.

## Understanding the Code

### Downstream Connection

`zigly.downstream()` returns a `Downstream` struct containing:

- `request` - The incoming HTTP request from the client
- `response` - The outgoing response you send back

### Response Lifecycle

1. Set the status code with `setStatus()`
2. Add headers with `headers.set()`
3. Write the body with `body.writeAll()` or `body.write()`
4. Finalize with `finish()` - this sends the response to the client

The `finish()` call is required. Without it, no response is sent.

## Reading the Request

Access request information:

```zig
pub fn main() !void {
    var downstream = try zigly.downstream();
    var request = downstream.request;

    // Get the HTTP method
    var method_buf: [16]u8 = undefined;
    const method = try request.getMethod(&method_buf);

    // Get the path
    var uri_buf: [4096]u8 = undefined;
    const path = try request.getPath(&uri_buf);

    // Check request type
    if (try request.isGet()) {
        // Handle GET
    } else if (try request.isPost()) {
        // Handle POST
    }

    // Read a header (requires allocator)
    const allocator = std.heap.page_allocator;
    const user_agent = try request.headers.get(allocator, "User-Agent");

    try downstream.response.setStatus(200);
    try downstream.response.body.writeAll("Request received");
    try downstream.response.finish();
}
```

## Reading Request Body

For POST/PUT requests, read the body:

```zig
const std = @import("std");
const zigly = @import("zigly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var downstream = try zigly.downstream();

    // Read entire body (0 = no limit)
    const body = try downstream.request.body.readAll(allocator, 0);
    defer allocator.free(body);

    // Process body...

    try downstream.response.setStatus(200);
    try downstream.response.finish();
}
```

## Proxying to a Backend

The most common use case is proxying requests to an origin server:

```zig
const zigly = @import("zigly");

pub fn main() !void {
    var downstream = try zigly.downstream();

    // Proxy the entire request/response to the "origin" backend
    try downstream.proxy("origin", "api.example.com");
}
```

The `proxy()` function:
1. Forwards the client request to the named backend
2. Sets the Host header to the second argument
3. Streams the backend response back to the client

Backends are configured in `fastly.toml` (see [Deployment](deployment.md)).

## Redirects

Redirect clients to a different URL:

```zig
pub fn main() !void {
    var downstream = try zigly.downstream();

    // 301 permanent redirect
    try downstream.redirect(301, "https://example.com/new-location");

    // Or 302 temporary redirect
    // try downstream.redirect(302, "/temporary-location");
}
```

## Build and Test

Build the service:

```bash
zig build -Doptimize=ReleaseSmall
```

Test locally with a Compute emulator (see [Testing Locally](testing-locally.md)):

```bash
viceroy zig-out/bin/service.wasm
```

Make a request:

```bash
curl http://127.0.0.1:7676/
```

## Next Steps

- [Testing Locally](testing-locally.md) - Set up local development
- [Deployment](deployment.md) - Deploy to Fastly Compute
- [Architecture](../concepts/architecture.md) - Understand the request lifecycle
