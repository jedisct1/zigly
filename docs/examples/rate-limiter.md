# Rate Limiter

Implements IP and path-based rate limiting at the edge using Fastly's Edge Rate Limiting (ERL) primitives. Blocks abusive clients before they reach your origin, with different limits for different endpoints.

## Source Code

```zig
const std = @import("std");
const zigly = @import("zigly");
const erl = zigly.erl;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var downstream = try zigly.downstream();

    // Get client IP
    const client_ip = try zigly.http.Downstream.getClientIpAddr();
    const ip_str = try client_ip.print(allocator);

    // Get request path for endpoint-specific rate limiting
    var uri_buf: [4096]u8 = undefined;
    const path = try downstream.request.getPath(&uri_buf);

    // Choose rate limit based on endpoint sensitivity
    const config: struct { counter: []const u8, limit: u32, window: u32 } = if (std.mem.startsWith(u8, path, "/api/auth/") or
        std.mem.startsWith(u8, path, "/api/login"))
    .{
        // Strict limits for auth endpoints: 10 requests per minute
        .counter = "auth_requests",
        .limit = 10,
        .window = 60,
    } else if (std.mem.startsWith(u8, path, "/api/")) .{
        // Moderate limits for API: 100 requests per minute
        .counter = "api_requests",
        .limit = 100,
        .window = 60,
    } else .{
        // Relaxed limits for static content: 500 requests per minute
        .counter = "general_requests",
        .limit = 500,
        .window = 60,
    };

    // Build rate limiter key combining IP and endpoint category
    const key = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ ip_str, config.counter });

    const limiter = erl.RateLimiter.init(.{
        .rate_counter = config.counter,
        .penalty_box = "blocked_ips",
        .window_seconds = config.window,
        .limit = config.limit,
        .ttl_seconds = 300,
    });

    // Check rate limit
    if (try limiter.isBlocked(key, 1)) {
        try downstream.response.setStatus(429);
        try downstream.response.headers.set("Content-Type", "application/json");
        try downstream.response.headers.set("Retry-After", "60");
        try downstream.response.body.writeAll("{\"error\":\"Rate limit exceeded\",\"retry_after\":60}");
        try downstream.response.finish();
        return;
    }

    // Request allowed, proxy to origin
    try downstream.proxy("origin", null);
}
```

## How It Works

1. Get the client IP address using `Downstream.getClientIpAddr()`
2. Extract the request path using `getPath()` for endpoint-specific limits
3. Select rate limit configuration based on path:
   - Auth endpoints (`/api/auth/`, `/api/login`): 10 requests per minute
   - API endpoints (`/api/`): 100 requests per minute
   - General content: 500 requests per minute
4. Build a composite key combining IP and endpoint category
5. Configure a `RateLimiter` with the selected limits
6. Check if the request should be blocked using `isBlocked()`
7. Return 429 with `Retry-After` header if blocked, otherwise proxy the request

## ERL Configuration

In `fastly.toml` for local development:

```toml
[local_server.rate_counter.auth_requests]
[local_server.rate_counter.api_requests]
[local_server.rate_counter.general_requests]
[local_server.penalty_box.blocked_ips]
```

No additional configuration needed for production - Fastly provides the rate counter and penalty box infrastructure.

## Testing

```bash
# Test general endpoint (500/min limit)
curl http://127.0.0.1:7676/

# Test API endpoint (100/min limit)
curl http://127.0.0.1:7676/api/data

# Test auth endpoint (10/min limit) - will hit limit quickly
for i in {1..15}; do curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:7676/api/auth/login; done
```

## Variations

**Simple IP-only rate limiting:**
```zig
const limiter = erl.RateLimiter.init(.{
    .rate_counter = "ip_requests",
    .penalty_box = "blocked_ips",
    .window_seconds = 60,
    .limit = 100,
    .ttl_seconds = 300,
});

if (try limiter.isBlocked(ip_str, 1)) {
    // Return 429
}
```

**Tiered rate limits by authentication:**
```zig
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
