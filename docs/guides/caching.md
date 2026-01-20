# Caching

Edge caching reduces load on origin servers and improves response times. Zigly provides both simple and transactional caching APIs.

## Simple Cache Operations

### Insert

Store data in the cache:

```zig
const zigly = @import("zigly");
const cache = zigly.cache;

fn cacheData(key: []const u8, data: []const u8) !void {
    // Insert with 1 hour TTL
    var body = try cache.insert(key, .{
        .max_age_ns = cache.secondsToNs(3600),
    });
    try body.writeAll(data);
    try body.close();
}
```

### Lookup

Retrieve cached data:

```zig
fn getCached(allocator: Allocator, key: []const u8) !?[]u8 {
    var entry = cache.lookup(key, .{}) catch |err| {
        if (err == FastlyError.FastlyNone) return null;
        return err;
    };
    defer entry.close() catch {};

    const state = try entry.getState();
    if (!state.isFound() or !state.isUsable()) {
        return null;
    }

    var body = try entry.getBody(null);
    defer body.close() catch {};

    return try body.readAll(allocator, 0);
}
```

### Check State

The cache entry state tells you about the entry:

```zig
const state = try entry.getState();

if (state.isFound()) {
    // Entry exists in cache
}

if (state.isUsable()) {
    // Entry can be served (not expired)
}

if (state.isStale()) {
    // Entry is past TTL but within stale-while-revalidate window
}

if (state.mustInsertOrUpdate()) {
    // For transactions: you need to populate this entry
}
```

## Write Options

Control cache behavior with `WriteOptions`:

```zig
const options = cache.WriteOptions{
    // Required: How long the entry is fresh
    .max_age_ns = cache.secondsToNs(300),  // 5 minutes

    // Serve stale content while revalidating
    .stale_while_revalidate_ns = cache.secondsToNs(60),  // 1 minute

    // Tag for purging
    .surrogate_keys = "product-123 category-electronics",

    // Known content length (enables streaming)
    .length = 1024,

    // Custom metadata (not served to clients)
    .user_metadata = "version=2",

    // Don't cache in edge memory (PCI compliance)
    .sensitive_data = true,
};
```

## Time Helpers

Convert between time units:

```zig
const cache = zigly.cache;

// Seconds to nanoseconds
const one_hour = cache.secondsToNs(3600);

// Milliseconds to nanoseconds
const half_second = cache.msToNs(500);
```

## Transactional Caching

Transactional caching prevents cache stampedes. When multiple requests arrive for the same uncached key, only one fetches from the origin:

```zig
fn fetchWithTransaction(allocator: Allocator, key: []const u8) ![]u8 {
    var tx = try cache.transactionLookup(key, .{});
    defer tx.close() catch {};

    const state = try tx.getState();

    if (state.isUsable()) {
        // Cache hit, return cached data
        var body = try tx.getBody(null);
        defer body.close() catch {};
        return try body.readAll(allocator, 0);
    }

    if (state.mustInsertOrUpdate()) {
        // We won the race, fetch and cache
        const data = try fetchFromOrigin(key);

        var result = try tx.insert(.{
            .max_age_ns = cache.secondsToNs(300),
        });
        try result.body.writeAll(data);
        try result.body.close();

        return data;
    }

    // Another request is populating, wait or fetch
    return try fetchFromOrigin(key);
}
```

### Insert and Stream Back

Populate the cache while simultaneously returning data to the caller:

```zig
fn insertAndStream(allocator: Allocator, key: []const u8) ![]u8 {
    var tx = try cache.transactionLookup(key, .{});
    const state = try tx.getState();

    if (state.mustInsertOrUpdate()) {
        const data = try fetchFromOrigin(key);

        var result = try tx.insertAndStreamBack(.{
            .max_age_ns = cache.secondsToNs(300),
        });

        // Write to cache
        try result.body.writeAll(data);
        try result.body.close();

        // Read back from cache entry
        var cached_body = try result.entry.getBody(null);
        defer cached_body.close() catch {};
        return try cached_body.readAll(allocator, 0);
    }

    // Hit path...
}
```

### Update Metadata

Update cache metadata without changing the body:

```zig
fn refreshTtl(key: []const u8) !void {
    var tx = try cache.transactionLookup(key, .{});
    defer tx.close() catch {};

    const state = try tx.getState();
    if (state.isFound()) {
        try tx.update(.{
            .max_age_ns = cache.secondsToNs(600),  // Extend TTL
        });
    }
}
```

## Replace Operation

Atomically replace a cache entry:

```zig
fn replaceEntry(key: []const u8, new_data: []const u8) !void {
    var handle = try cache.replace(key, .{});

    // Check if old entry exists
    const state = try handle.getState();
    if (state.isFound()) {
        // Can read old data if needed
        var old_body = try handle.getBody(null);
        const old_data = try old_body.readAll(allocator, 0);
        // Use old_data...
    }

    // Insert new data
    var body = try handle.insert(.{
        .max_age_ns = cache.secondsToNs(300),
    });
    try body.writeAll(new_data);
    try body.close();
}
```

## Cache Metadata

Read metadata from cache entries:

```zig
fn inspectEntry(key: []const u8) !void {
    var entry = try cache.lookup(key, .{});
    defer entry.close() catch {};

    const length = try entry.getLength();
    const age_ns = try entry.getAgeNs();
    const max_age_ns = try entry.getMaxAgeNs();
    const hits = try entry.getHits();

    std.debug.print("Size: {}, Age: {}ms, TTL: {}ms, Hits: {}\n", .{
        length,
        age_ns / cache.ms_per_ns,
        max_age_ns / cache.ms_per_ns,
        hits,
    });
}
```

## Range Requests

Read partial content from cache:

```zig
fn getPartialContent(key: []const u8, start: u64, end: u64) ![]u8 {
    var entry = try cache.lookup(key, .{});
    defer entry.close() catch {};

    var body = try entry.getBody(.{
        .from = start,
        .to = end,
    });
    defer body.close() catch {};

    return try body.readAll(allocator, end - start);
}
```

## Surrogate Keys and Purging

Tag entries for later purging:

```zig
// When caching
var body = try cache.insert("product-123-page", .{
    .max_age_ns = cache.secondsToNs(3600),
    .surrogate_keys = "product-123 all-products",
});

// Later, purge all entries with the key
const purge = zigly.purge;
try purge.purge("product-123");  // Hard purge

// Or soft purge (mark stale, serve while revalidating)
try purge.softPurge("all-products");
```

## Request-Level Cache Control

Override caching at the request level:

```zig
fn proxyWithCache() !void {
    var downstream = try zigly.downstream();

    // Force specific TTL for this request
    try downstream.request.setCachingPolicy(.{
        .ttl = 600,          // Cache for 10 minutes
        .serve_stale = 3600, // Serve stale for 1 hour if origin fails
        .surrogate_key = "api-responses",
    });

    try downstream.proxy("api", null);
}
```

Bypass cache entirely:

```zig
try downstream.request.setCachingPolicy(.{ .no_cache = true });
```

## Async Operations

For non-blocking cache lookups:

```zig
fn asyncLookup(key: []const u8) !void {
    var busy_handle = try cache.transactionLookupAsync(key, .{});

    // Do other work...

    // Wait for result
    var tx = try busy_handle.wait();
    defer tx.close() catch {};

    // Use transaction...
}
```

## Patterns

### Cache-Aside

Check cache first, fetch on miss:

```zig
fn getData(allocator: Allocator, key: []const u8) ![]u8 {
    // Check cache
    if (try getCached(allocator, key)) |data| {
        return data;
    }

    // Fetch from origin
    const data = try fetchFromOrigin(key);

    // Store in cache (fire and forget)
    cacheData(key, data) catch {};

    return data;
}
```

### Stale-While-Revalidate

Serve stale content while refreshing in the background:

```zig
var body = try cache.insert(key, .{
    .max_age_ns = cache.secondsToNs(60),     // Fresh for 1 minute
    .stale_while_revalidate_ns = cache.secondsToNs(300),  // Serve stale for 5 more minutes
});
```

When a request arrives during the stale period, Fastly serves the stale content immediately and triggers a background revalidation.

## Next Steps

- [Rate Limiting](rate-limiting.md) - Protect origins
- [Cache Reference](../reference/cache.md) - Full API details
- [Purge Reference](../reference/purge.md) - Cache invalidation
