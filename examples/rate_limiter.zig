// Rate Limiter Example
// Implements IP-based rate limiting at the edge

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
