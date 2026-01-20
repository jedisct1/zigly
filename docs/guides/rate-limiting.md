# Rate Limiting

Edge Rate Limiting (ERL) protects your origins from traffic spikes and abuse. Zigly provides rate counters, penalty boxes, and a combined rate limiter.

## Quick Start

The simplest approach uses `RateLimiter`:

```zig
const zigly = @import("zigly");
const erl = zigly.erl;

fn start() !void {
    var downstream = try zigly.downstream();

    // Get client identifier (usually IP)
    const client_ip = try zigly.http.Downstream.getClientIpAddr();
    var ip_buf: [40]u8 = undefined;
    const ip_str = try std.fmt.bufPrint(&ip_buf, "{}", .{client_ip});

    // Configure rate limiter
    const limiter = erl.RateLimiter.init(.{
        .rate_counter = "requests",
        .penalty_box = "blocked_ips",
        .window_seconds = 60,    // 1 minute window
        .limit = 100,            // 100 requests per window
        .ttl_seconds = 300,      // Block for 5 minutes when exceeded
    });

    // Check rate
    if (try limiter.isBlocked(ip_str, 1)) {
        try downstream.response.setStatus(429);
        try downstream.response.headers.set("Retry-After", "300");
        try downstream.response.body.writeAll("Rate limit exceeded");
        try downstream.response.finish();
        return;
    }

    // Process request normally
    try downstream.proxy("origin", null);
}
```

## Components

### Rate Counter

Tracks request counts over time:

```zig
const rc = erl.RateCounter.open("my_counter");

// Increment by 1
try rc.increment("client-key", 1);

// Increment by custom amount (e.g., request size)
try rc.increment("client-key", 5);

// Get rate (requests per second) over window
const rate = try rc.lookupRate("client-key", 10);  // 10 second window

// Get total count over duration
const count = try rc.lookupCount("client-key", 60);  // Last 60 seconds
```

Rate counters use a sliding window algorithm. The window is divided into sub-windows for accuracy.

### Penalty Box

Tracks blocked entries:

```zig
const pb = erl.PenaltyBox.open("my_penaltybox");

// Check if blocked
const is_blocked = try pb.has("client-key");

// Add to penalty box with TTL
try pb.add("client-key", 300);  // Block for 5 minutes
```

Once in the penalty box, an entry stays blocked until the TTL expires. There's no way to remove an entry early.

### RateLimiter

Combines rate counter and penalty box:

```zig
const limiter = erl.RateLimiter.init(.{
    .rate_counter = "requests",
    .penalty_box = "blocked",
    .window_seconds = 60,
    .limit = 100,
    .ttl_seconds = 300,
});

// Check and increment atomically
const result = try limiter.checkRate("client-key", 1);
if (result == .blocked) {
    // Client is rate limited
}

// Convenience methods
if (try limiter.isAllowed("client-key", 1)) {
    // Process request
}

if (try limiter.isBlocked("client-key", 1)) {
    // Reject request
}
```

The `checkRate` function:
1. Checks if the entry is in the penalty box
2. If not, increments the rate counter
3. If the count exceeds the limit, adds to the penalty box
4. Returns `allowed` or `blocked`

## Standalone Check

For one-off rate checks:

```zig
const result = try erl.checkRate(
    "counter_name",
    "entry_key",
    1,              // delta
    60,             // window_seconds
    100,            // limit
    "penaltybox",   // penalty_box name
    300,            // ttl_seconds
);
```

## Patterns

### IP-Based Limiting

```zig
fn start() !void {
    var downstream = try zigly.downstream();

    const client_ip = try zigly.http.Downstream.getClientIpAddr();
    const ip_str = try client_ip.print(allocator);
    defer allocator.free(ip_str);

    const limiter = erl.RateLimiter.init(.{
        .rate_counter = "ip_requests",
        .penalty_box = "blocked_ips",
        .window_seconds = 60,
        .limit = 100,
        .ttl_seconds = 300,
    });

    if (try limiter.isBlocked(ip_str, 1)) {
        try sendRateLimitResponse(&downstream);
        return;
    }

    try downstream.proxy("origin", null);
}
```

### API Key Limiting

```zig
fn start() !void {
    var downstream = try zigly.downstream();

    const api_key = downstream.request.headers.get(allocator, "X-API-Key") catch {
        try sendUnauthorized(&downstream);
        return;
    };

    const limiter = erl.RateLimiter.init(.{
        .rate_counter = "api_keys",
        .penalty_box = "blocked_keys",
        .window_seconds = 3600,  // 1 hour
        .limit = 1000,           // 1000 requests per hour
        .ttl_seconds = 3600,
    });

    if (try limiter.isBlocked(api_key, 1)) {
        try sendRateLimitResponse(&downstream);
        return;
    }

    try downstream.proxy("origin", null);
}
```

### Tiered Limits

Different limits for different tiers:

```zig
fn getLimiter(tier: []const u8) erl.RateLimiter {
    if (std.mem.eql(u8, tier, "premium")) {
        return erl.RateLimiter.init(.{
            .rate_counter = "premium_requests",
            .penalty_box = "premium_blocked",
            .window_seconds = 60,
            .limit = 1000,
            .ttl_seconds = 60,
        });
    } else {
        return erl.RateLimiter.init(.{
            .rate_counter = "free_requests",
            .penalty_box = "free_blocked",
            .window_seconds = 60,
            .limit = 10,
            .ttl_seconds = 300,
        });
    }
}
```

### Path-Based Limiting

Stricter limits on sensitive endpoints:

```zig
fn start() !void {
    var downstream = try zigly.downstream();

    var uri_buf: [4096]u8 = undefined;
    const uri = try downstream.request.getUriString(&uri_buf);

    const limiter = if (std.mem.startsWith(u8, uri, "/api/auth/"))
        erl.RateLimiter.init(.{
            .rate_counter = "auth_requests",
            .penalty_box = "auth_blocked",
            .window_seconds = 60,
            .limit = 5,        // Very strict
            .ttl_seconds = 900, // Block for 15 minutes
        })
    else
        erl.RateLimiter.init(.{
            .rate_counter = "api_requests",
            .penalty_box = "api_blocked",
            .window_seconds = 60,
            .limit = 100,
            .ttl_seconds = 300,
        });

    const client_ip = try zigly.http.Downstream.getClientIpAddr();
    const ip_str = try client_ip.print(allocator);

    if (try limiter.isBlocked(ip_str, 1)) {
        try sendRateLimitResponse(&downstream);
        return;
    }

    try downstream.proxy("origin", null);
}
```

### Monitoring Without Blocking

Count requests without enforcing limits:

```zig
fn start() !void {
    var downstream = try zigly.downstream();

    const rc = erl.RateCounter.open("all_requests");

    const client_ip = try zigly.http.Downstream.getClientIpAddr();
    const ip_str = try client_ip.print(allocator);

    // Just count, don't block
    try rc.increment(ip_str, 1);

    // Check rate for logging
    const rate = try rc.lookupRate(ip_str, 60);
    std.debug.print("Client {} rate: {}/min\n", .{ip_str, rate * 60});

    try downstream.proxy("origin", null);
}
```

### Weighted Requests

Count more expensive requests higher:

```zig
fn start() !void {
    var downstream = try zigly.downstream();

    var method_buf: [16]u8 = undefined;
    const method = try downstream.request.getMethod(&method_buf);

    // POST/PUT requests count as 5, GET as 1
    const weight: u32 = if (std.mem.eql(u8, method, "GET")) 1 else 5;

    const limiter = erl.RateLimiter.init(.{
        .rate_counter = "weighted_requests",
        .penalty_box = "blocked",
        .window_seconds = 60,
        .limit = 100,
        .ttl_seconds = 300,
    });

    const client_ip = try zigly.http.Downstream.getClientIpAddr();
    const ip_str = try client_ip.print(allocator);

    if (try limiter.isBlocked(ip_str, weight)) {
        try sendRateLimitResponse(&downstream);
        return;
    }

    try downstream.proxy("origin", null);
}
```

## Response Headers

Include rate limit information in responses:

```zig
fn addRateLimitHeaders(response: *OutgoingResponse, rc: erl.RateCounter, key: []const u8) !void {
    const count = try rc.lookupCount(key, 60);
    const limit: u32 = 100;
    const remaining = if (count >= limit) 0 else limit - count;

    var count_buf: [16]u8 = undefined;
    var remaining_buf: [16]u8 = undefined;
    var limit_buf: [16]u8 = undefined;

    const count_str = try std.fmt.bufPrint(&count_buf, "{}", .{count});
    const remaining_str = try std.fmt.bufPrint(&remaining_buf, "{}", .{remaining});
    const limit_str = try std.fmt.bufPrint(&limit_buf, "{}", .{limit});

    try response.headers.set("X-RateLimit-Limit", limit_str);
    try response.headers.set("X-RateLimit-Remaining", remaining_str);
    try response.headers.set("X-RateLimit-Used", count_str);
}
```

## Configuration

Rate counters and penalty boxes are named resources. Configure them in `fastly.toml` for local testing:

```toml
# Local emulators don't require special ERL configuration
# Rate limiting works automatically with named resources
```

## Next Steps

- [Geo Routing](geo-routing.md) - Route based on location
- [ERL Reference](../reference/erl.md) - Full API details
