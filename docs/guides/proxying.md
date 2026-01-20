# Proxying

The most common edge computing pattern: accept a request, optionally modify it, send it to an origin server, and return the response.

## Simple Proxy

The `proxy()` method handles the entire flow:

```zig
const zigly = @import("zigly");

fn start() !void {
    var downstream = try zigly.downstream();
    try downstream.proxy("origin", "api.example.com");
}
```

This:

1. Sets the Host header to `api.example.com`
2. Forwards the request to the "origin" backend
3. Returns the backend's response to the client

The second argument (`host_header`) can be `null` to preserve the original Host header.

## Modifying Requests

Manipulate the request before proxying:

```zig
fn start() !void {
    var downstream = try zigly.downstream();
    var request = downstream.request;

    // Add authentication
    try request.headers.set("Authorization", "Bearer secret-token");

    // Remove sensitive headers from reaching origin
    try request.headers.remove("Cookie");

    // Add tracking header
    try request.headers.set("X-Edge-Location", "SFO");

    try downstream.proxy("origin", "api.example.com");
}
```

## Conditional Proxying

Route to different backends based on request properties:

```zig
const std = @import("std");
const zigly = @import("zigly");

fn start() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var downstream = try zigly.downstream();

    var uri_buf: [4096]u8 = undefined;
    const uri = try downstream.request.getUriString(&uri_buf);

    // Route based on path prefix
    if (std.mem.startsWith(u8, uri, "/api/")) {
        try downstream.proxy("api_backend", "api.example.com");
    } else if (std.mem.startsWith(u8, uri, "/static/")) {
        try downstream.proxy("storage_backend", "cdn.example.com");
    } else {
        try downstream.proxy("web_backend", "www.example.com");
    }
}
```

## Manual Request/Response

For more control, handle requests and responses separately:

```zig
const zigly = @import("zigly");
const Request = zigly.http.Request;

fn start() !void {
    var downstream = try zigly.downstream();

    // Create upstream request
    var uri_buf: [4096]u8 = undefined;
    const client_uri = try downstream.request.getUriString(&uri_buf);

    var upstream_req = try Request.new("GET", client_uri);
    try upstream_req.headers.set("Host", "api.example.com");

    // Copy specific headers from client
    if (downstream.request.headers.get(alloc, "Accept")) |accept| {
        try upstream_req.headers.set("Accept", accept);
    } else |_| {}

    // Send to backend
    var upstream_resp = try upstream_req.send("origin");

    // Modify response before sending to client
    try downstream.response.setStatus(try upstream_resp.getStatus());
    try downstream.response.headers.set("X-Served-By", "edge");

    // Copy body
    var body_buf: [8192]u8 = undefined;
    while (true) {
        const chunk = try upstream_resp.body.read(&body_buf);
        if (chunk.len == 0) break;
        try downstream.response.body.writeAll(chunk);
    }

    try downstream.response.finish();
}
```

## Zero-Copy Piping

Use `pipe()` for efficient response forwarding:

```zig
fn start() !void {
    var downstream = try zigly.downstream();

    var upstream_req = try Request.new("GET", "/data");
    var upstream_resp = try upstream_req.send("origin");

    // Zero-copy the response
    // Arguments: copy_status, copy_headers
    try downstream.response.pipe(&upstream_resp, true, true);
}
```

`pipe()` directly streams the upstream response to the client without buffering.

## Redirects

Redirect clients without proxying:

```zig
fn start() !void {
    var downstream = try zigly.downstream();

    // Permanent redirect
    try downstream.redirect(301, "https://new.example.com/page");

    // Temporary redirect
    // try downstream.redirect(302, "/temporary-location");
}
```

## Caching Policy

Control caching behavior per-request:

```zig
fn start() !void {
    var downstream = try zigly.downstream();

    // Bypass cache for this request
    try downstream.request.setCachingPolicy(.{ .no_cache = true });
    try downstream.proxy("origin", null);
}
```

```zig
fn start() !void {
    var downstream = try zigly.downstream();

    // Override TTL and enable stale-while-revalidate
    try downstream.request.setCachingPolicy(.{
        .ttl = 300,           // 5 minutes
        .serve_stale = 3600,  // Serve stale for 1 hour if origin fails
    });
    try downstream.proxy("origin", null);
}
```

## Dynamic Backends

Create backends at runtime:

```zig
const zigly = @import("zigly");
const DynamicBackend = zigly.DynamicBackend;

fn start() !void {
    var downstream = try zigly.downstream();

    // Register a new backend
    const backend = try (DynamicBackend{
        .name = "dynamic_origin",
        .target = "dynamic.example.com:443",
        .use_ssl = true,
        .host_override = "dynamic.example.com",
        .sni_hostname = "dynamic.example.com",
        .cert_hostname = "dynamic.example.com",
        .connect_timeout_ms = 5000,
        .first_byte_timeout_ms = 15000,
        .between_bytes_timeout_ms = 10000,
    }).register();

    try downstream.proxy(backend.name, null);
}
```

## Failover

Implement backend failover:

```zig
fn start() !void {
    var downstream = try zigly.downstream();

    // Try primary backend
    downstream.proxy("primary", "primary.example.com") catch {
        // Fall back to secondary
        downstream.proxy("secondary", "secondary.example.com") catch {
            // Both failed, return error
            try downstream.response.setStatus(503);
            try downstream.response.body.writeAll("Service unavailable");
            try downstream.response.finish();
            return;
        };
    };
}
```

## Auto-Decompression

Handle compressed responses from backends:

```zig
fn start() !void {
    var downstream = try zigly.downstream();

    // Enable automatic gzip decompression
    try downstream.request.setAutoDecompressResponse(true);

    var upstream_resp = try downstream.request.send("origin");
    // Response body is now decompressed
}
```

## Request Logging

Log requests in Apache format:

```zig
fn start() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var downstream = try zigly.downstream();

    // Process request and capture response details
    try downstream.proxy("origin", null);

    // Log in Apache combined format
    try downstream.request.logApacheCombined(alloc, "access_log", 200, 1234);
}
```

## Next Steps

- [Caching](caching.md) - Cache responses at the edge
- [Rate Limiting](rate-limiting.md) - Protect your backends
- [Backend Reference](../reference/backend.md) - Backend API details
