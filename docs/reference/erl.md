# ERL Reference

Edge Rate Limiting (ERL) provides rate counters, penalty boxes, and a combined rate limiter.

## RateCounter

Tracks request counts over sliding time windows.

### Static Methods

#### open

```zig
pub fn open(name: []const u8) RateCounter
```

Open a rate counter by name. Creates it if it doesn't exist.

```zig
const erl = zigly.erl;

const rc = erl.RateCounter.open("my_counter");
```

### Instance Methods

#### increment

```zig
pub fn increment(self: RateCounter, entry: []const u8, delta: u32) !void
```

Increment the counter for an entry.

```zig
try rc.increment("client-ip", 1);

// Increment by more for weighted counting
try rc.increment("client-ip", 5);
```

#### lookupRate

```zig
pub fn lookupRate(self: RateCounter, entry: []const u8, window_seconds: u32) !u32
```

Get the request rate (per second) over a time window.

```zig
const rate = try rc.lookupRate("client-ip", 10);  // 10 second window
// rate = requests per second averaged over the window
```

#### lookupCount

```zig
pub fn lookupCount(self: RateCounter, entry: []const u8, duration_seconds: u32) !u32
```

Get the total count over a duration.

```zig
const count = try rc.lookupCount("client-ip", 60);  // Last 60 seconds
```

---

## PenaltyBox

Tracks blocked entries with TTL.

### Static Methods

#### open

```zig
pub fn open(name: []const u8) PenaltyBox
```

Open a penalty box by name.

```zig
const pb = erl.PenaltyBox.open("blocked_clients");
```

### Instance Methods

#### add

```zig
pub fn add(self: PenaltyBox, entry: []const u8, ttl_seconds: u32) !void
```

Add an entry to the penalty box.

```zig
try pb.add("bad-actor", 300);  // Block for 5 minutes
```

#### has

```zig
pub fn has(self: PenaltyBox, entry: []const u8) !bool
```

Check if an entry is in the penalty box.

```zig
if (try pb.has("client-ip")) {
    // Client is blocked
}
```

---

## RateLimiter

Combines rate counter and penalty box for common rate limiting patterns.

### Initialization

```zig
pub fn init(options: struct {
    rate_counter: []const u8,
    penalty_box: []const u8,
    window_seconds: u32,
    limit: u32,
    ttl_seconds: u32,
}) RateLimiter
```

Create a rate limiter.

```zig
const limiter = erl.RateLimiter.init(.{
    .rate_counter = "requests",     // Counter name
    .penalty_box = "blocked",       // Penalty box name
    .window_seconds = 60,           // 1 minute window
    .limit = 100,                   // 100 requests per window
    .ttl_seconds = 300,             // Block for 5 minutes when exceeded
});
```

### Instance Methods

#### checkRate

```zig
pub fn checkRate(self: RateLimiter, entry: []const u8, delta: u32) !CheckRateResult
```

Check and increment atomically. Returns `.allowed` or `.blocked`.

```zig
const result = try limiter.checkRate("client-ip", 1);
if (result == .blocked) {
    // Request is rate limited
}
```

#### isAllowed

```zig
pub fn isAllowed(self: RateLimiter, entry: []const u8, delta: u32) !bool
```

Check if the request is allowed.

```zig
if (try limiter.isAllowed("client-ip", 1)) {
    // Process request
} else {
    // Rate limited
}
```

#### isBlocked

```zig
pub fn isBlocked(self: RateLimiter, entry: []const u8, delta: u32) !bool
```

Check if the request is blocked.

```zig
if (try limiter.isBlocked("client-ip", 1)) {
    // Return 429
}
```

---

## checkRate (Module Function)

Standalone rate check without creating a RateLimiter.

```zig
pub fn checkRate(
    rate_counter: []const u8,
    entry: []const u8,
    delta: u32,
    window_seconds: u32,
    limit: u32,
    penalty_box: []const u8,
    ttl_seconds: u32,
) !CheckRateResult
```

```zig
const result = try erl.checkRate(
    "requests",    // rate_counter
    "client-ip",   // entry
    1,             // delta
    60,            // window_seconds
    100,           // limit
    "blocked",     // penalty_box
    300,           // ttl_seconds
);
```

---

## CheckRateResult

Result of a rate check.

```zig
pub const CheckRateResult = enum(u32) {
    allowed = 0,
    blocked = 1,
};
```

---

## Usage Patterns

### IP-Based Rate Limiting

```zig
fn start() !void {
    var downstream = try zigly.downstream();

    const client_ip = try zigly.http.Downstream.getClientIpAddr();
    const ip_str = try client_ip.print(allocator);
    defer allocator.free(ip_str);

    const limiter = erl.RateLimiter.init(.{
        .rate_counter = "ip_requests",
        .penalty_box = "ip_blocked",
        .window_seconds = 60,
        .limit = 100,
        .ttl_seconds = 300,
    });

    if (try limiter.isBlocked(ip_str, 1)) {
        try downstream.response.setStatus(429);
        try downstream.response.headers.set("Retry-After", "300");
        try downstream.response.body.writeAll("Rate limit exceeded");
        try downstream.response.finish();
        return;
    }

    try downstream.proxy("origin", null);
}
```

### API Key Rate Limiting

```zig
fn start() !void {
    var downstream = try zigly.downstream();

    const api_key = downstream.request.headers.get(allocator, "X-API-Key") catch {
        try downstream.response.setStatus(401);
        try downstream.response.finish();
        return;
    };

    const limiter = erl.RateLimiter.init(.{
        .rate_counter = "api_keys",
        .penalty_box = "api_blocked",
        .window_seconds = 3600,  // 1 hour
        .limit = 10000,          // 10,000/hour
        .ttl_seconds = 3600,
    });

    if (try limiter.isBlocked(api_key, 1)) {
        try downstream.response.setStatus(429);
        try downstream.response.finish();
        return;
    }

    try downstream.proxy("origin", null);
}
```

### Monitoring Without Blocking

```zig
fn start() !void {
    var downstream = try zigly.downstream();

    const rc = erl.RateCounter.open("all_requests");
    const client_ip = try zigly.http.Downstream.getClientIpAddr();
    const ip_str = try client_ip.print(allocator);

    // Just count
    try rc.increment(ip_str, 1);

    // Log rate
    const rate = try rc.lookupRate(ip_str, 60);
    std.debug.print("Client rate: {}/min\n", .{rate * 60});

    try downstream.proxy("origin", null);
}
```

---

## Related

- [Rate Limiting Guide](../guides/rate-limiting.md) - Practical patterns
- [Rate Limiter Example](../examples/rate-limiter.md) - Complete example
