// Rate Limiter Example
// Implements IP and path-based rate limiting at the edge

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

pub export fn _start() callconv(.c) void {
    start() catch |err| {
        std.debug.print("Error: {}\n", .{err});
    };
}
