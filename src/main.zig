// These are just examples to exercise the bindings
// Only `zigly.zig` needs to be included in your actual applications.

const std = @import("std");
const ArenaAllocator = std.heap.ArenaAllocator;

const zigly = @import("zigly.zig");
const UserAgent = zigly.UserAgent;
const Request = zigly.Request;

fn start() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer _ = gpa.deinit();
    var allocator = &gpa.allocator;

    try zigly.compatibilityCheck();

    var downstream = try zigly.downstream();
    var request = downstream.request;

    {
        var arena = ArenaAllocator.init(allocator);
        defer arena.deinit();
        const body = try request.body.readAll(&arena.allocator);
        std.debug.print("[{}]\n", .{body});
    }

    {
        var arena = ArenaAllocator.init(allocator);
        defer arena.deinit();
        const names = try request.headers.names(&arena.allocator);
        for (names) |name| {
            std.debug.print("[{}]\n", .{name});
        }
    }

    {
        var arena = ArenaAllocator.init(allocator);
        defer arena.deinit();
        try request.headers.set(&arena.allocator, "x-test", "test");
        try request.headers.remove("x-test");
    }

    {
        var arena = ArenaAllocator.init(allocator);
        defer arena.deinit();
        const ua = try request.headers.get(&arena.allocator, "user-agent");
        std.debug.print("UA: [{}]\n", .{ua});
    }

    {
        var method_buf: [16]u8 = undefined;
        const method = try request.getMethod(&method_buf);
        std.debug.print("[{}]\n", .{method});
        _ = try request.isPost();
    }

    {
        var arena = ArenaAllocator.init(allocator);
        defer arena.deinit();
        var query = try Request.new("GET", "https://google.com");
        try query.setCachingPolicy(.{ .no_cache = true });
        var response = try query.send("google.com");
        const body = try response.body.readAll(&arena.allocator);
        std.debug.print("{}\n", .{body});
    }

    {
        var arena = ArenaAllocator.init(allocator);
        defer arena.deinit();

        var response = downstream.response;
        try response.headers.set(&arena.allocator, "X-MyHeader", "XYZ");

        try response.setStatus(205);
        try response.body.writeAll("OK!\n");
        try response.finish();
    }

    {
        var arena = ArenaAllocator.init(allocator);
        defer arena.deinit();
        var query = try Request.new("GET", "https://google.com");
        var upstream_response = try query.send("google.com");
        try downstream.response.pipe(&upstream_response, false, false);
    }
}

pub export fn _start() callconv(.C) void {
    start() catch unreachable;
}
