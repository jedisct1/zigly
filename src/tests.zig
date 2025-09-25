// These are just examples to exercise the bindings
// Only `zigly.zig` and the `zigly` directory need to be included in your actual applications.

const std = @import("std");
const ArenaAllocator = std.heap.ArenaAllocator;

const zigly = @import("zigly.zig");
const Dictionary = zigly.Dictionary;
const UserAgent = zigly.UserAgent;
const Request = zigly.http.Request;
const Logger = zigly.Logger;

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

    {
        var arena = ArenaAllocator.init(allocator);
        defer arena.deinit();

        var response = downstream.response;
        try response.headers.set("X-MyHeader", "XYZ");

        try response.setStatus(205);
        try response.body.writeAll("OK!\n");
        try response.finish();
    }

    {
        var arena = ArenaAllocator.init(allocator);
        defer arena.deinit();
        var query = try Request.new("GET", "https://www.google.com");
        var upstream_response = try query.send("google");
        try downstream.response.pipe(&upstream_response, false, false);
    }
}

pub export fn _start() callconv(.c) void {
    start() catch unreachable;
}
