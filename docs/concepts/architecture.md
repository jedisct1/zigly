# Architecture

This document explains how Zigly maps to Fastly's Compute runtime and the request lifecycle.

## The Compute Runtime

Fastly Compute runs your code at the edge in a WebAssembly sandbox. When a request arrives at a Fastly edge server:

1. Fastly creates a new WebAssembly instance
2. Calls the `_start` entry point (generated automatically by Zig)
3. Your `main()` function processes the request
4. The instance is terminated after the response is sent

Each request gets a fresh instance. There's no shared state between requests unless you use external storage (KV stores, caching).

## Entry Point

Your service needs a `pub fn main()` function:

```zig
const zigly = @import("zigly");

pub fn main() !void {
    var downstream = try zigly.downstream();
    // Process request...
}
```

Zig automatically generates the WASI `_start` entry point when targeting `wasm32-wasi`. Your `main()` function can return errors, which Zig handles appropriately.

## Handle-Based API

Zigly wraps Fastly's handle-based API. Handles are opaque integers that reference resources in the host runtime:

- `RequestHandle` - An HTTP request
- `ResponseHandle` - An HTTP response
- `BodyHandle` - An HTTP body (readable or writable)
- `CacheHandle` - A cache entry
- And others...

You don't work with handles directly. Zigly provides structs that manage them:

```zig
// Zigly struct              Underlying handle
// ---------------           -----------------
pub const Body = struct {
    handle: wasm.BodyHandle,  // Opaque handle
    // Methods that call Fastly APIs with this handle
    pub fn read(self: *Body, buf: []u8) ![]u8 { ... }
    pub fn write(self: *Body, buf: []const u8) !usize { ... }
};
```

## The Downstream Connection

`zigly.downstream()` is the entry point for handling client requests:

```zig
pub const Downstream = struct {
    request: Request,       // The client's request
    response: OutgoingResponse,  // Your response to the client
};
```

This represents the "downstream" connection—the client talking to your edge service. Requests you make to backends are "upstream."

```
Client (downstream) <---> Edge Service <---> Backend (upstream)
```

## Request Flow

A typical request flow:

```zig
fn main() !void {
    // 1. Get the downstream connection
    var downstream = try zigly.downstream();

    // 2. Read the client request
    var method_buf: [16]u8 = undefined;
    const method = try downstream.request.getMethod(&method_buf);

    // 3. Maybe make upstream requests
    var upstream_req = try Request.new("GET", "https://api.example.com/data");
    var upstream_resp = try upstream_req.send("api_backend");

    // 4. Build and send the downstream response
    try downstream.response.setStatus(200);
    try downstream.response.body.writeAll("Response data");
    try downstream.response.finish();
}
```

## Response Lifecycle

The response must be explicitly finished:

```zig
var response = downstream.response;

// Set status (optional, defaults to 200)
try response.setStatus(200);

// Set headers
try response.headers.set("Content-Type", "application/json");

// Write body
try response.body.writeAll("{\"status\":\"ok\"}");

// REQUIRED: Send the response
try response.finish();
```

`finish()` sends the response to the client and closes the connection. If you don't call it, the client gets no response.

### Streaming Responses

For large responses, use `flush()` followed by more writes:

```zig
try response.setStatus(200);
try response.body.writeAll("First chunk");
try response.flush();  // Send buffered data

try response.body.writeAll("Second chunk");
try response.finish();  // Final send
```

### Piping Responses

Zero-copy an upstream response to the client:

```zig
var upstream_resp = try upstream_req.send("backend");
try downstream.response.pipe(&upstream_resp, true, true);
// copy_status=true, copy_headers=true
```

## Proxying

The `proxy()` method combines upstream request and downstream response:

```zig
try downstream.proxy("backend_name", "host.example.com");
```

This is equivalent to:

```zig
try downstream.request.headers.set("Host", "host.example.com");
// Send request to backend, get response, send to client
```

## Resource Cleanup

Most resources are cleaned up automatically when the request ends. However, explicitly closing resources is good practice:

```zig
var body = try cache_entry.getBody(null);
defer body.close() catch {};

var response = try request.send("backend");
defer response.close() catch {};
```

## Module Organization

Zigly organizes APIs into modules:

```
zigly
├── downstream()          # Get client connection
├── http                  # Request, Response, Body, Headers
├── cache                 # Caching APIs
├── erl                   # Rate limiting
├── backend               # Backend management
├── geo                   # Geolocation
├── device                # Device detection
├── kv                    # Key-value store
├── acl                   # Access control lists
├── purge                 # Cache purging
├── Dictionary            # Edge dictionaries
├── Logger                # Logging endpoints
├── UserAgent             # UA parsing
└── runtime               # vCPU metrics
```

Access them through the main import:

```zig
const zigly = @import("zigly");

// Direct access
var downstream = try zigly.downstream();

// Module access
const entry = try zigly.cache.lookup("key", .{});
const is_mobile = try zigly.device.isMobile(allocator, user_agent);
```

## WebAssembly Considerations

### Memory

WebAssembly has a single linear memory space. Zig's allocators work within this space. Use arenas for request-scoped allocations:

```zig
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
defer arena.deinit();
const alloc = arena.allocator();
```

See [Memory Management](memory.md) for details.

### Size

Binary size affects cold start time. Use `ReleaseSmall`:

```bash
zig build -Doptimize=ReleaseSmall
```

### Limitations

- No threads (single-threaded execution)
- No file system access (except through Fastly APIs)
- No network access (except through Fastly APIs)
- Limited stack size (use heap for large buffers)

## Next Steps

- [Error Handling](error-handling.md) - Handle Fastly errors
- [Memory Management](memory.md) - Allocator patterns
