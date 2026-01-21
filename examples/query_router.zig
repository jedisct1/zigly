// Query Router Example
// Routes requests based on query parameters using parseQueryParams()

const std = @import("std");
const zigly = @import("zigly");

fn start() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var downstream = try zigly.downstream();

    // Parse query parameters from the request URI
    const params = try downstream.request.parseQueryParams(allocator);

    // Look for specific query parameters to determine routing
    var version: ?[]const u8 = null;
    var format: ?[]const u8 = null;
    var debug: bool = false;

    for (params) |param| {
        if (std.mem.eql(u8, param.key, "version") or std.mem.eql(u8, param.key, "v")) {
            version = param.value;
        } else if (std.mem.eql(u8, param.key, "format")) {
            format = param.value;
        } else if (std.mem.eql(u8, param.key, "debug")) {
            debug = std.mem.eql(u8, param.value, "true") or std.mem.eql(u8, param.value, "1");
        }
    }

    // Route to different API versions based on query param
    const backend = if (version) |v|
        if (std.mem.eql(u8, v, "2") or std.mem.startsWith(u8, v, "2."))
            "api_v2"
        else
            "api_v1"
    else
        "api_v1";

    // Add debug header if requested
    if (debug) {
        try downstream.request.headers.set("X-Debug-Mode", "true");
    }

    // Set response format preference header for the backend
    if (format) |f| {
        if (std.mem.eql(u8, f, "xml")) {
            try downstream.request.headers.set("Accept", "application/xml");
        } else if (std.mem.eql(u8, f, "csv")) {
            try downstream.request.headers.set("Accept", "text/csv");
        }
    }

    try downstream.proxy(backend, null);
}

pub export fn _start() callconv(.c) void {
    start() catch |err| {
        std.debug.print("Error: {}\n", .{err});
    };
}
