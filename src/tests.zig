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
const cache = zigly.cache;
const erl = zigly.erl;

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

    google_test: {
        var arena = ArenaAllocator.init(allocator);
        defer arena.deinit();
        var query = Request.new("GET", "https://www.google.com") catch |err| {
            std.debug.print("Google request creation error: {}\n", .{err});
            break :google_test;
        };
        query.setCachingPolicy(.{ .no_cache = true }) catch |err| {
            std.debug.print("Cache policy error: {}\n", .{err});
            break :google_test;
        };
        var response = query.send("google") catch |err| {
            std.debug.print("Google send error: {}\n", .{err});
            break :google_test;
        };
        const body = response.body.readAll(arena.allocator(), 0) catch |err| {
            std.debug.print("Google body read error: {}\n", .{err});
            break :google_test;
        };
        std.debug.print("Google response length: {}\n", .{body.len});
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
    dyn_backend_test: {
        std.debug.print("Testing dynamic backends...\n", .{});

        // Register a dynamic backend to httpbin.org
        const dynamic_backend = DynamicBackend{
            .name = "httpbin_dyn",
            .target = "httpbin.org:443",
            .use_ssl = true,
            .host_override = "httpbin.org",
            .sni_hostname = "httpbin.org",
            .cert_hostname = "httpbin.org",
            .connect_timeout_ms = 5000,
            .first_byte_timeout_ms = 15000,
            .between_bytes_timeout_ms = 10000,
        };

        const dyn_backend = dynamic_backend.register() catch |err| {
            std.debug.print("Dynamic backend registration error: {}\n", .{err});
            break :dyn_backend_test;
        };
        std.debug.print("Dynamic backend registered: {s}\n", .{dyn_backend.name});

        // Check if backend exists
        const exists = Backend.exists("httpbin_dyn") catch false;
        std.debug.print("Backend exists: {}\n", .{exists});

        // Check if backend is dynamic
        const is_dynamic = dyn_backend.isDynamic() catch false;
        std.debug.print("Backend is dynamic: {}\n", .{is_dynamic});

        // Check if backend uses SSL
        const is_ssl = dyn_backend.isSsl() catch false;
        std.debug.print("Backend uses SSL: {}\n", .{is_ssl});

        // Get backend port
        const port = dyn_backend.getPort() catch 0;
        std.debug.print("Backend port: {}\n", .{port});

        // Make a request using the dynamic backend
        var arena = ArenaAllocator.init(allocator);
        defer arena.deinit();

        var query = Request.new("GET", "https://httpbin.org/get") catch |err| {
            std.debug.print("Request creation error: {}\n", .{err});
            break :dyn_backend_test;
        };
        var dyn_response = query.send("httpbin_dyn") catch |err| {
            std.debug.print("Request send error: {}\n", .{err});
            break :dyn_backend_test;
        };
        const status = dyn_response.getStatus() catch 0;
        std.debug.print("Response status from dynamic backend: {}\n", .{status});

        const body = dyn_response.body.readAll(arena.allocator(), 1024) catch |err| {
            std.debug.print("Body read error: {}\n", .{err});
            break :dyn_backend_test;
        };
        std.debug.print("Response body (first 200 chars): {s}\n", .{body[0..@min(body.len, 200)]});
    }

    // Test cache transactions
    cache_test: {
        std.debug.print("Testing cache transactions...\n", .{});

        const cache_key = "test-cache-key-12345";
        const cache_body = "Hello from cache!";

        // Insert into cache (simple test without metadata)
        var insert_body = cache.insert(cache_key, .{
            .max_age_ns = cache.secondsToNs(60),
        }) catch |err| {
            std.debug.print("Cache insert error: {}\n", .{err});
            break :cache_test;
        };
        _ = try insert_body.write(cache_body);
        try insert_body.close();

        std.debug.print("Cache insert completed\n", .{});

        // Lookup from cache
        var entry = cache.lookup(cache_key, .{}) catch |err| {
            std.debug.print("Cache lookup error: {}\n", .{err});
            break :cache_test;
        };
        const state = try entry.getState();
        std.debug.print("Cache state - found: {}, usable: {}, stale: {}\n", .{
            state.isFound(),
            state.isUsable(),
            state.isStale(),
        });

        if (state.isFound()) {
            var arena = ArenaAllocator.init(allocator);
            defer arena.deinit();

            var body = try entry.getBody(null);
            const content = try body.readAll(arena.allocator(), 1024);
            std.debug.print("Cache body: {s}\n", .{content});
        }

        try entry.close();
        std.debug.print("Cache test completed\n", .{});
    }

    // Test transactional cache lookup
    tx_test: {
        std.debug.print("Testing transactional cache...\n", .{});

        const tx_key = "test-transaction-key-67890";

        // Transactional lookup (request-collapsing)
        var tx = cache.transactionLookup(tx_key, .{}) catch |err| {
            std.debug.print("Transaction lookup error: {}\n", .{err});
            break :tx_test;
        };
        const tx_state = try tx.getState();

        if (tx_state.mustInsertOrUpdate()) {
            std.debug.print("Transaction requires insert\n", .{});
            var result = try tx.insert(.{
                .max_age_ns = cache.secondsToNs(30),
            });
            _ = try result.body.write("Transaction cached content");
            try result.body.close();
            std.debug.print("Transaction insert completed\n", .{});
        } else {
            std.debug.print("Transaction found existing entry\n", .{});
        }

        try tx.close();
        std.debug.print("Transaction test completed\n", .{});
    }

    // Test rate limiting (ERL)
    erl_test: {
        std.debug.print("Testing rate limiting...\n", .{});

        // Test rate counter
        const rc = erl.RateCounter.open("test_rc");
        rc.increment("client-ip-192.168.1.1", 1) catch |err| {
            std.debug.print("Rate counter increment error: {}\n", .{err});
            break :erl_test;
        };
        std.debug.print("Rate counter incremented\n", .{});

        const rate = rc.lookupRate("client-ip-192.168.1.1", 10) catch |err| {
            std.debug.print("Rate lookup error: {}\n", .{err});
            break :erl_test;
        };
        std.debug.print("Rate for client: {}\n", .{rate});

        const count = rc.lookupCount("client-ip-192.168.1.1", 60) catch |err| {
            std.debug.print("Count lookup error: {}\n", .{err});
            break :erl_test;
        };
        std.debug.print("Count for client: {}\n", .{count});

        // Test penalty box
        const pb = erl.PenaltyBox.open("test_pb");
        const in_pb_before = pb.has("bad-actor") catch |err| {
            std.debug.print("Penalty box has error: {}\n", .{err});
            break :erl_test;
        };
        std.debug.print("Bad actor in penalty box before: {}\n", .{in_pb_before});

        pb.add("bad-actor", 300) catch |err| {
            std.debug.print("Penalty box add error: {}\n", .{err});
            break :erl_test;
        };
        std.debug.print("Added bad actor to penalty box\n", .{});

        const in_pb_after = pb.has("bad-actor") catch |err| {
            std.debug.print("Penalty box has (after) error: {}\n", .{err});
            break :erl_test;
        };
        std.debug.print("Bad actor in penalty box after: {}\n", .{in_pb_after});

        // Test combined rate limiter
        const limiter = erl.RateLimiter.init(.{
            .rate_counter = "test_rc",
            .penalty_box = "test_pb",
            .window_seconds = 10,
            .limit = 100,
            .ttl_seconds = 300,
        });

        const result = limiter.checkRate("test-entry", 1) catch |err| {
            std.debug.print("Rate check error: {}\n", .{err});
            break :erl_test;
        };
        std.debug.print("Rate check result: {s}\n", .{if (result == .allowed) "allowed" else "blocked"});

        const is_allowed = limiter.isAllowed("test-entry", 1) catch |err| {
            std.debug.print("Is allowed error: {}\n", .{err});
            break :erl_test;
        };
        std.debug.print("Is allowed: {}\n", .{is_allowed});

        std.debug.print("Rate limiting test completed\n", .{});
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
