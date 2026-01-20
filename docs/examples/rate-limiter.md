# Rate Limiter

Implements IP-based rate limiting at the edge using Fastly's Edge Rate Limiting (ERL) primitives. Blocks abusive clients before they reach your origin.

## Source Code

```zig
const std = @import("std");
const zigly = @import("zigly");
const erl = zigly.erl;

fn start() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var downstream = try zigly.downstream();

    // Get client IP
    const client_ip = try zigly.http.Downstream.getClientIpAddr();
    const ip_str = try client_ip.print(allocator);

    // Configure rate limiter: 100 requests per minute, block for 5 minutes
    const limiter = erl.RateLimiter.init(.{
        .rate_counter = "ip_requests",
        .penalty_box = "blocked_ips",
        .window_seconds = 60,
        .limit = 100,
        .ttl_seconds = 300,
    });

    // Check rate limit
    if (try limiter.isBlocked(ip_str, 1)) {
        try downstream.response.setStatus(429);
        try downstream.response.headers.set("Content-Type", "application/json");
        try downstream.response.headers.set("Retry-After", "300");
        try downstream.response.body.writeAll("{\"error\":\"Rate limit exceeded\",\"retry_after\":300}");
        try downstream.response.finish();
        return;
    }

    // Request allowed, proxy to origin
    try downstream.proxy("origin", null);
}

pub export fn _start() callconv(.c) void {
    start() catch |err| {
        std.debug.print("Error: {}\n", .{err});
    };
}
```

## How It Works

1. Get the client IP address using `Downstream.getClientIpAddr()`
2. Convert the IP to a string for use as a rate limit key
3. Configure a `RateLimiter` with:
   - `rate_counter`: Name of the counter to track requests
   - `penalty_box`: Name of the penalty box for blocked IPs
   - `window_seconds`: Time window for counting requests (60 seconds)
   - `limit`: Maximum requests per window (100)
   - `ttl_seconds`: How long to block an IP after exceeding the limit (300 seconds)
4. Check if the IP is blocked using `isBlocked()`, which:
   - Returns `true` if the IP is already in the penalty box
   - Increments the rate counter
   - Adds the IP to the penalty box if it exceeds the limit
5. Return 429 with `Retry-After` header if blocked, otherwise proxy the request

## ERL Configuration

In `fastly.toml` for local development:

```toml
[local_server.rate_counter.ip_requests]
[local_server.penalty_box.blocked_ips]
```

No additional configuration needed for production - Fastly provides the rate counter and penalty box infrastructure.

## Testing

```bash
# First 100 requests succeed
for i in {1..100}; do curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:7676/test; done

# Request 101+ should return 429
curl -v http://127.0.0.1:7676/test
```

## Variations

**Per-endpoint limits:**
```zig
const endpoint_key = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ ip_str, path });

const api_limiter = erl.RateLimiter.init(.{
    .rate_counter = "api_requests",
    .penalty_box = "api_blocked",
    .window_seconds = 60,
    .limit = 10,  // Stricter limit for API
    .ttl_seconds = 600,
});
```

**Tiered rate limits:**
```zig
// Check premium tier first
var auth_buf: [256]u8 = undefined;
if (downstream.request.headers.get("Authorization", &auth_buf)) |_| {
    const premium_limiter = erl.RateLimiter.init(.{
        .rate_counter = "premium_requests",
        .penalty_box = "premium_blocked",
        .window_seconds = 60,
        .limit = 1000,
        .ttl_seconds = 60,
    });
    if (try premium_limiter.isBlocked(ip_str, 1)) {
        // Return 429
    }
} else {
    // Use standard limiter for unauthenticated requests
}
```

**Manual counter management:**
```zig
// Just count without automatic blocking
var counter = erl.RateCounter.open("request_counter");
const count = try counter.increment(ip_str, 1);

if (count > 50) {
    // Log high-traffic IPs without blocking
    var logger = try zigly.logger.Logger.open("analytics");
    try logger.write(ip_str);
}
```

## Related

- [Rate Limiting Guide](../guides/rate-limiting.md)
- [ERL Reference](../reference/erl.md)
- [HTTP Reference](../reference/http.md)
