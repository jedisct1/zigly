// These are just examples to exercise the bindings
// Only `zigly.zig` and the `zigly` directory need to be included in your actual applications.

const std = @import("std");
const ArenaAllocator = std.heap.ArenaAllocator;

const zigly = @import("zigly.zig");
const Dictionary = zigly.Dictionary;
const UserAgent = zigly.UserAgent;
const Request = zigly.http.Request;
const PendingRequest = zigly.http.PendingRequest;
const Logger = zigly.Logger;
const Backend = zigly.Backend;
const DynamicBackend = zigly.DynamicBackend;
const cache = zigly.cache;
const erl = zigly.erl;

fn start() !void {
    const allocator = std.heap.wasm_allocator;

    try zigly.compatibilityCheck();

    const downstream = try zigly.downstream();
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
            // A leftover NUL means the packed host buffer was not split apart.
            if (std.mem.indexOfScalar(u8, name, 0) != null) {
                return error.HeaderNameContainsNul;
            }
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

    // Test URI helpers
    {
        var uri_buf: [4096]u8 = undefined;

        // Test getUriString (already exists, just verify it works)
        const full_uri = try request.getUriString(&uri_buf);
        std.debug.print("Full URI: [{s}]\n", .{full_uri});

        // Test getUri - parses into std.Uri components
        const uri = try request.getUri(&uri_buf);
        std.debug.print("URI scheme: [{s}]\n", .{uri.scheme});
        const path_str = switch (uri.path) {
            .raw => |r| r,
            .percent_encoded => |e| e,
        };
        std.debug.print("URI path: [{s}]\n", .{path_str});

        // Test getPath - extracts just the path
        const path = try request.getPath(&uri_buf);
        std.debug.print("Path only: [{s}]\n", .{path});

        // Test getPathAndQuery
        var out_buf: [4096]u8 = undefined;
        const path_query = try request.getPathAndQuery(&uri_buf, &out_buf);
        std.debug.print("Path and query: [{s}]\n", .{path_query});
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

    // Test async (parallel) requests against the local delay server
    async_test: {
        std.debug.print("Testing async requests...\n", .{});

        var start_ns: std.os.wasi.timestamp_t = undefined;
        _ = std.os.wasi.clock_time_get(.MONOTONIC, 1, &start_ns);

        // Send three requests in parallel; the backend delays each response
        // by the number of milliseconds in the path.
        const urls = [_][]const u8{
            "http://127.0.0.1:9876/delay/600",
            "http://127.0.0.1:9876/delay/200",
            "http://127.0.0.1:9876/delay/400",
        };
        var pending: [urls.len]PendingRequest = undefined;
        for (urls, 0..) |url, i| {
            var query = Request.new("GET", url) catch |err| {
                std.debug.print("Async request creation error: {}\n", .{err});
                break :async_test;
            };
            pending[i] = query.sendAsync("local") catch |err| {
                std.debug.print("sendAsync error: {}\n", .{err});
                break :async_test;
            };
        }

        // The slowest request cannot be done yet.
        const early_ready = pending[0].isReady() catch |err| {
            std.debug.print("isReady error: {}\n", .{err});
            break :async_test;
        };
        std.debug.print("Slowest request ready immediately: {}\n", .{early_ready});

        const early_poll = pending[0].poll() catch |err| {
            std.debug.print("poll error: {}\n", .{err});
            break :async_test;
        };
        std.debug.print("Slowest request polled immediately: {}\n", .{early_poll != null});
        if (early_poll != null) {
            // The poll consumed the pending request, so the handle can no
            // longer take part in the select below.
            return error.UnexpectedEarlyResponse;
        }

        var arena = ArenaAllocator.init(allocator);
        defer arena.deinit();

        // The 200ms request must win the select, with the index pointing at
        // its slot in the slice.
        const first = PendingRequest.select(&pending) catch |err| {
            std.debug.print("select error: {}\n", .{err});
            break :async_test;
        };
        var first_response = first.response;
        const first_body = first_response.body.readAll(arena.allocator(), 0) catch |err| {
            std.debug.print("Async body read error: {}\n", .{err});
            break :async_test;
        };
        std.debug.print("First completion: index {}, status {}, body [{s}]\n", .{
            first.index,
            first_response.getStatus() catch 0,
            first_body,
        });
        if (first.index != 1 or !std.mem.eql(u8, first_body, "delayed 200")) {
            return error.UnexpectedCompletionOrder;
        }

        // Drain the remaining requests with the completion-order iterator.
        pending[first.index] = pending[pending.len - 1];
        var responses = PendingRequest.iterator(pending[0 .. pending.len - 1]);
        const expected = [_][]const u8{ "delayed 400", "delayed 600" };
        var done: usize = 0;
        while (responses.next() catch |err| {
            std.debug.print("iterator error: {}\n", .{err});
            break :async_test;
        }) |next_response| {
            var response = next_response;
            const body = response.body.readAll(arena.allocator(), 0) catch |err| {
                std.debug.print("Async body read error: {}\n", .{err});
                break :async_test;
            };
            std.debug.print("Next completion: body [{s}]\n", .{body});
            if (done >= expected.len or !std.mem.eql(u8, body, expected[done])) {
                return error.UnexpectedCompletionOrder;
            }
            done += 1;
        }
        if (done != expected.len) {
            return error.UnexpectedCompletionOrder;
        }

        var end_ns: std.os.wasi.timestamp_t = undefined;
        _ = std.os.wasi.clock_time_get(.MONOTONIC, 1, &end_ns);
        const elapsed_ms = (end_ns - start_ns) / std.time.ns_per_ms;
        std.debug.print("Elapsed: {}ms (sequential would be >= 1200ms)\n", .{elapsed_ms});
        if (elapsed_ms >= 1200) {
            return error.RequestsNotParallel;
        }

        std.debug.print("Async requests test completed\n", .{});
    }

    // Test a streaming async request: headers go out first, the body is
    // written afterwards, and the response is waited on.
    streaming_test: {
        std.debug.print("Testing streaming async request...\n", .{});

        var arena = ArenaAllocator.init(allocator);
        defer arena.deinit();

        var query = Request.new("POST", "http://127.0.0.1:9876/echo") catch |err| {
            std.debug.print("Streaming request creation error: {}\n", .{err});
            break :streaming_test;
        };
        const pending = query.sendAsyncStreaming("local") catch |err| {
            std.debug.print("sendAsyncStreaming error: {}\n", .{err});
            break :streaming_test;
        };
        query.body.writeAll("hello ") catch |err| {
            std.debug.print("Streaming body write error: {}\n", .{err});
            break :streaming_test;
        };
        query.body.writeAll("world") catch |err| {
            std.debug.print("Streaming body write error: {}\n", .{err});
            break :streaming_test;
        };
        query.body.close() catch |err| {
            std.debug.print("Streaming body close error: {}\n", .{err});
            break :streaming_test;
        };
        var response = pending.wait() catch |err| {
            std.debug.print("Streaming wait error: {}\n", .{err});
            break :streaming_test;
        };
        const body = response.body.readAll(arena.allocator(), 0) catch |err| {
            std.debug.print("Streaming body read error: {}\n", .{err});
            break :streaming_test;
        };
        std.debug.print("Echoed body: [{s}]\n", .{body});
        if (!std.mem.eql(u8, body, "hello world")) {
            return error.UnexpectedEchoedBody;
        }

        std.debug.print("Streaming async request test completed\n", .{});
    }

    // Write trailers to a body, then read them back after consuming it.
    trailer_test: {
        std.debug.print("Testing body trailers...\n", .{});

        var arena = ArenaAllocator.init(allocator);
        defer arena.deinit();

        var query = Request.new("POST", "http://127.0.0.1:9876/echo") catch |err| {
            std.debug.print("Trailer request creation error: {}\n", .{err});
            break :trailer_test;
        };
        query.body.writeAll("trailer test") catch |err| {
            std.debug.print("Trailer body write error: {}\n", .{err});
            break :trailer_test;
        };
        query.body.appendTrailer("x-checksum", "abc123") catch |err| {
            std.debug.print("appendTrailer error: {}\n", .{err});
            break :trailer_test;
        };
        try query.body.appendTrailer("x-tag", "one");
        try query.body.appendTrailer("x-tag", "two");

        // Trailers stay unreadable until the content has been consumed.
        if (query.body.getTrailer(arena.allocator(), "x-checksum")) |_| {
            return error.TrailersReadableTooEarly;
        } else |err| if (err != zigly.FastlyError.FastlyAgain) {
            std.debug.print("Unexpected early trailer read error: {}\n", .{err});
            return error.UnexpectedTrailerError;
        }

        const content = try query.body.readAll(arena.allocator(), 0);
        if (!std.mem.eql(u8, content, "trailer test")) {
            return error.UnexpectedTrailerBody;
        }

        const checksum = try query.body.getTrailer(arena.allocator(), "x-checksum");
        std.debug.print("Trailer x-checksum: [{s}]\n", .{checksum});
        if (!std.mem.eql(u8, checksum, "abc123")) {
            return error.UnexpectedTrailerValue;
        }

        const names = try query.body.trailerNames(arena.allocator());
        std.debug.print("Trailer count: {}\n", .{names.len});
        if (names.len != 2) {
            return error.UnexpectedTrailerNames;
        }

        const tags = try query.body.getAllTrailers(arena.allocator(), "x-tag");
        if (tags.len != 2 or !std.mem.eql(u8, tags[0], "one") or !std.mem.eql(u8, tags[1], "two")) {
            return error.UnexpectedTrailerValues;
        }

        std.debug.print("Body trailers test completed\n", .{});
    }

    // Send requests whose bodies carry trailers, buffered and streaming.
    trailer_send_test: {
        std.debug.print("Testing requests with trailers...\n", .{});

        var arena = ArenaAllocator.init(allocator);
        defer arena.deinit();

        var query = Request.new("POST", "http://127.0.0.1:9876/echo") catch |err| {
            std.debug.print("Trailer send request creation error: {}\n", .{err});
            break :trailer_send_test;
        };
        query.body.writeAll("buffered with trailers") catch |err| {
            std.debug.print("Trailer send body write error: {}\n", .{err});
            break :trailer_send_test;
        };
        try query.body.appendTrailer("x-checksum", "deadbeef");
        var response = query.send("local") catch |err| {
            std.debug.print("Trailer send error: {}\n", .{err});
            break :trailer_send_test;
        };
        const body = response.body.readAll(arena.allocator(), 0) catch |err| {
            std.debug.print("Trailer send body read error: {}\n", .{err});
            break :trailer_send_test;
        };
        if (!std.mem.eql(u8, body, "buffered with trailers")) {
            return error.UnexpectedEchoedBody;
        }

        // Streaming requests accept trailers up to the closing of the body.
        var streaming_query = Request.new("POST", "http://127.0.0.1:9876/echo") catch |err| {
            std.debug.print("Streaming trailer request creation error: {}\n", .{err});
            break :trailer_send_test;
        };
        const pending = streaming_query.sendAsyncStreaming("local") catch |err| {
            std.debug.print("Streaming trailer sendAsyncStreaming error: {}\n", .{err});
            break :trailer_send_test;
        };
        try streaming_query.body.writeAll("streaming with trailers");
        try streaming_query.body.appendTrailer("x-checksum", "cafebabe");
        try streaming_query.body.close();
        var streaming_response = pending.wait() catch |err| {
            std.debug.print("Streaming trailer wait error: {}\n", .{err});
            break :trailer_send_test;
        };
        const streamed = streaming_response.body.readAll(arena.allocator(), 0) catch |err| {
            std.debug.print("Streaming trailer body read error: {}\n", .{err});
            break :trailer_send_test;
        };
        if (!std.mem.eql(u8, streamed, "streaming with trailers")) {
            return error.UnexpectedEchoedBody;
        }

        std.debug.print("Requests with trailers test completed\n", .{});
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

    // Test the KV store
    {
        var arena = ArenaAllocator.init(allocator);
        defer arena.deinit();

        var store = try zigly.kv.Store.open("test_store");

        try store.insert("kv_test_key", "kv_test_value", .{
            .metadata = "kv_test_metadata",
            .time_to_live_sec = 60,
        });
        std.debug.print("KV insert completed\n", .{});

        var result = try store.lookup("kv_test_key", arena.allocator());
        const value = try result.body.readAll(arena.allocator(), 0);
        std.debug.print("KV lookup value: [{s}]\n", .{value});
        std.debug.assert(std.mem.eql(u8, value, "kv_test_value"));
        if (result.metadata) |metadata| {
            std.debug.print("KV lookup metadata: [{s}]\n", .{metadata});
            std.debug.assert(std.mem.eql(u8, metadata, "kv_test_metadata"));
        }
        std.debug.print("KV lookup generation: {}\n", .{result.generation});

        const all = try store.getAll("kv_test_key", arena.allocator(), 0);
        std.debug.assert(std.mem.eql(u8, all, "kv_test_value"));

        try store.insert("kv_test_key", "!", .{ .mode = .append });
        const appended = try store.getAll("kv_test_key", arena.allocator(), 0);
        std.debug.print("KV appended value: [{s}]\n", .{appended});
        std.debug.assert(std.mem.eql(u8, appended, "kv_test_value!"));

        const listing = try store.list(arena.allocator(), .{ .prefix = "kv_test_" }, 0);
        std.debug.print("KV list: [{s}]\n", .{listing});

        try store.delete("kv_test_key");
        if (store.lookup("kv_test_key", arena.allocator())) |_| {
            std.debug.print("KV delete failed, key still present\n", .{});
            std.debug.assert(false);
        } else |err| {
            std.debug.assert(err == error.NotFound);
            std.debug.print("KV delete confirmed\n", .{});
        }

        std.debug.print("KV store test completed\n", .{});
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

pub fn main() void {
    start() catch unreachable;
}
