// API Gateway Example
// Routes requests to different backends based on path prefix

const std = @import("std");
const zigly = @import("zigly");

fn start() !void {
    var downstream = try zigly.downstream();

    // Get the request path using the built-in helper
    var uri_buf: [4096]u8 = undefined;
    const path = try downstream.request.getPath(&uri_buf);

    // Route based on path prefix
    if (std.mem.startsWith(u8, path, "/api/users")) {
        try downstream.proxy("users_api", null);
    } else if (std.mem.startsWith(u8, path, "/api/products")) {
        try downstream.proxy("products_api", null);
    } else if (std.mem.startsWith(u8, path, "/static/")) {
        try downstream.proxy("cdn", null);
    } else {
        // Default: return 404
        try downstream.response.setStatus(404);
        try downstream.response.headers.set("Content-Type", "application/json");
        try downstream.response.body.writeAll("{\"error\":\"Not found\"}");
        try downstream.response.finish();
    }
}

pub export fn _start() callconv(.c) void {
    start() catch |err| {
        std.debug.print("Error: {}\n", .{err});
    };
}
