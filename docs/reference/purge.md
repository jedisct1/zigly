# Purge Reference

The purge module provides cache invalidation by surrogate key.

## Functions

### purge

```zig
pub fn purge(surrogate_key: []const u8) !void
```

Hard purge cached content by surrogate key. Immediately removes content from cache.

```zig
const purge = zigly.purge;

try purge.purge("product-123");
```

### softPurge

```zig
pub fn softPurge(surrogate_key: []const u8) !void
```

Soft purge by surrogate key. Marks content as stale but continues serving it while revalidating.

```zig
try purge.softPurge("product-123");
```

### purgeSurrogateKey

```zig
pub fn purgeSurrogateKey(surrogate_key: []const u8, options: PurgeOptions) !void
```

Purge with options.

```zig
// Hard purge (default)
try purge.purgeSurrogateKey("key", .{});

// Soft purge
try purge.purgeSurrogateKey("key", .{ .soft_purge = true });
```

---

## PurgeOptions

```zig
pub const PurgeOptions = struct {
    soft_purge: bool = false,  // If true, mark as stale instead of removing
};
```

---

## Surrogate Keys

Surrogate keys are tags assigned to cached content. When caching, add surrogate keys:

```zig
const cache = zigly.cache;

var body = try cache.insert("product-page-123", .{
    .max_age_ns = cache.secondsToNs(3600),
    .surrogate_keys = "product-123 category-electronics all-products",
});
```

Multiple keys are space-separated. You can then purge by any of those keys:

```zig
try purge.purge("product-123");        // Purges this product
try purge.purge("category-electronics"); // Purges all electronics
try purge.purge("all-products");        // Purges everything
```

---

## Hard vs Soft Purge

### Hard Purge

```zig
try purge.purge("product-123");
```

- Immediately removes content from cache
- Next request fetches fresh content from origin
- May cause origin load spike if many requests hit at once

### Soft Purge

```zig
try purge.softPurge("product-123");
```

- Marks content as stale
- Continues serving stale content while one request revalidates
- Reduces origin load
- Best for content that changes frequently

---

## Example Usage

### API-Triggered Purge

```zig
const std = @import("std");
const zigly = @import("zigly");
const purge = zigly.purge;

fn start() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var downstream = try zigly.downstream();

    var uri_buf: [4096]u8 = undefined;
    const uri = try downstream.request.getUriString(&uri_buf);

    // Purge API endpoint
    if (std.mem.startsWith(u8, uri, "/api/purge/")) {
        // Authenticate (check API key, etc.)
        const api_key = downstream.request.headers.get(allocator, "X-API-Key") catch "";
        if (!std.mem.eql(u8, api_key, "secret-key")) {
            try downstream.response.setStatus(401);
            try downstream.response.finish();
            return;
        }

        // Extract surrogate key from path
        const key = uri["/api/purge/".len..];

        // Purge
        try purge.softPurge(key);

        try downstream.response.setStatus(200);
        try downstream.response.body.writeAll("Purged");
        try downstream.response.finish();
        return;
    }

    try downstream.proxy("origin", null);
}
```

### Content Update Purge

```zig
fn updateProduct(product_id: []const u8, new_data: []const u8) !void {
    // Update in backend/database
    var req = try Request.new("PUT", "/api/products");
    try req.body.writeAll(new_data);
    var resp = try req.send("api_backend");
    try resp.close();

    // Purge cached pages
    var key_buf: [64]u8 = undefined;
    const key = try std.fmt.bufPrint(&key_buf, "product-{s}", .{product_id});
    try purge.softPurge(key);
}
```

### Batch Purge

```zig
fn purgeMultipleKeys(keys: []const []const u8) !void {
    for (keys) |key| {
        purge.softPurge(key) catch |err| {
            std.debug.print("Failed to purge {s}: {}\n", .{ key, err });
        };
    }
}

// Usage
try purgeMultipleKeys(&[_][]const u8{
    "product-123",
    "product-456",
    "category-electronics",
});
```

---

## Request-Level Cache Control

You can also control caching per-request:

```zig
fn start() !void {
    var downstream = try zigly.downstream();

    // Set surrogate key for this request's cached response
    try downstream.request.setCachingPolicy(.{
        .ttl = 3600,
        .surrogate_key = "my-content-key",
    });

    try downstream.proxy("origin", null);
}
```

---

## Notes

- Purges propagate across all Fastly edge servers
- Purge operations are rate-limited
- Use soft purge when possible to reduce origin load
- Surrogate keys are case-sensitive
- Maximum surrogate key length: 1024 characters
