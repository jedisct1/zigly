// These are just examples to exercise the bindings
// Only `zigly.zig` and the `zigly` directory need to be included in your actual applications.

const std = @import("std");
const ArenaAllocator = std.heap.ArenaAllocator;

const zigly = @import("zigly.zig");
const Dictionary = zigly.Dictionary;
const UserAgent = zigly.UserAgent;
const Request = zigly.http.Request;
const Logger = zigly.Logger;
const Backend = zigly.Backend;
const DynamicBackend = zigly.DynamicBackend;

fn start() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try zigly.compatibilityCheck();

    var downstream = try zigly.downstream();
    var request = downstream.request;

    {
        var arena = ArenaAllocator.init(allocator);
        defer arena.deinit();
        try request.setAutoDecompressResponse(true);
        const body = try request.body.readAll(arena.allocator(), 0);
        std.debug.print("[{s}]\n", .{body});
    }

    {
        var arena = ArenaAllocator.init(allocator);
        defer arena.deinit();
        const names = try request.headers.names(arena.allocator());
        for (names) |name| {
            std.debug.print("[{s}]\n", .{name});
        }
    }

    {
        var arena = ArenaAllocator.init(allocator);
        defer arena.deinit();
        try request.headers.set("x-test", "test");
        try request.headers.remove("x-test");
    }

    {
        var arena = ArenaAllocator.init(allocator);
        defer arena.deinit();
        const ua = try request.headers.get(arena.allocator(), "user-agent");
        std.debug.print("UA: [{s}]\n", .{ua});
    }

    {
        var method_buf: [16]u8 = undefined;
        const method = try request.getMethod(&method_buf);
        std.debug.print("[{s}]\n", .{method});
        _ = try request.isPost();
    }

    {
        var arena = ArenaAllocator.init(allocator);
        defer arena.deinit();
        var query = try Request.new("GET", "https://www.google.com");
        try query.setCachingPolicy(.{ .no_cache = true });
        var response = try query.send("google");
        const body = try response.body.readAll(arena.allocator(), 0);
        std.debug.print("{s}\n", .{body});
    }

    // Test the Apache combined log format function
    {
        var arena = ArenaAllocator.init(allocator);
        defer arena.deinit();

        // Log request in Apache combined format
        // Simulating a 200 OK response with 1234 bytes
        try request.logApacheCombined(arena.allocator(), "access_log", 200, 1234);

        // Log request with 404 and no content
        try request.logApacheCombined(arena.allocator(), "access_log", 404, 0);
    }

    // Test dynamic backend registration (must be before finishing downstream response)
    {
        std.debug.print("Testing dynamic backends...\n", .{});

        // Register a dynamic backend to httpbin.org
        const dynamic_backend = DynamicBackend{
            .name = "httpbin",
            .target = "httpbin.org:443",
            .use_ssl = true,
            .host_override = "httpbin.org",
            .sni_hostname = "httpbin.org",
            .cert_hostname = "httpbin.org",
            .connect_timeout_ms = 5000,
            .first_byte_timeout_ms = 15000,
            .between_bytes_timeout_ms = 10000,
        };

        const dyn_backend = try dynamic_backend.register();
        std.debug.print("Dynamic backend registered: {s}\n", .{dyn_backend.name});

        // Check if backend exists
        const exists = try Backend.exists("httpbin");
        std.debug.print("Backend exists: {}\n", .{exists});

        // Check if backend is dynamic
        const is_dynamic = try dyn_backend.isDynamic();
        std.debug.print("Backend is dynamic: {}\n", .{is_dynamic});

        // Check if backend uses SSL
        const is_ssl = try dyn_backend.isSsl();
        std.debug.print("Backend uses SSL: {}\n", .{is_ssl});

        // Get backend port
        const port = try dyn_backend.getPort();
        std.debug.print("Backend port: {}\n", .{port});

        // Make a request using the dynamic backend
        var arena = ArenaAllocator.init(allocator);
        defer arena.deinit();

        var query = try Request.new("GET", "https://httpbin.org/get");
        var dyn_response = try query.send("httpbin");
        const status = try dyn_response.getStatus();
        std.debug.print("Response status from dynamic backend: {}\n", .{status});

        const body = try dyn_response.body.readAll(arena.allocator(), 1024);
        std.debug.print("Response body (first 200 chars): {s}\n", .{body[0..@min(body.len, 200)]});
    }

    // Final response to client
    {
        var response = downstream.response;
        try response.headers.set("X-MyHeader", "XYZ");
        try response.setStatus(200);
        try response.body.writeAll("All tests passed!\n");
        try response.finish();
    }
}

pub export fn _start() callconv(.c) void {
    start() catch unreachable;
}
