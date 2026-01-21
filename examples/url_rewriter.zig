// URL Rewriter Example
// Demonstrates URI manipulation: rewriting paths, preserving query strings,
// and accessing URI components

const std = @import("std");
const zigly = @import("zigly");

fn start() !void {
    var downstream = try zigly.downstream();

    var uri_buf: [4096]u8 = undefined;
    var out_buf: [4096]u8 = undefined;

    // Get full parsed URI to access individual components
    const uri = try downstream.request.getUri(&uri_buf);
    const path = switch (uri.path) {
        .raw => |raw| raw,
        .percent_encoded => |encoded| encoded,
    };

    // Example 1: Rewrite legacy paths to new API structure
    // /v1/users/123 -> /api/v1/users/123
    if (std.mem.startsWith(u8, path, "/v1/") or std.mem.startsWith(u8, path, "/v2/")) {
        // Get path with query string preserved
        const path_and_query = try downstream.request.getPathAndQuery(&uri_buf, &out_buf);

        // Build new URI with /api prefix
        var new_uri_buf: [4096]u8 = undefined;
        const new_uri = try std.fmt.bufPrint(&new_uri_buf, "/api{s}", .{path_and_query});

        // Update the request URI
        try downstream.request.setUriString(new_uri);
        try downstream.proxy("api_backend", null);
        return;
    }

    // Example 2: Strip /old/ prefix from legacy URLs
    if (std.mem.startsWith(u8, path, "/old/")) {
        const path_and_query = try downstream.request.getPathAndQuery(&uri_buf, &out_buf);

        // Remove /old prefix, keep the rest including query string
        const new_path = path_and_query[4..]; // Skip "/old"
        try downstream.request.setUriString(new_path);
        try downstream.proxy("origin", null);
        return;
    }

    // Example 3: Add trailing slash to directory paths (no extension, no query)
    if (!std.mem.endsWith(u8, path, "/") and
        std.mem.lastIndexOfScalar(u8, path, '.') == null and
        uri.query == null)
    {
        var new_path_buf: [4096]u8 = undefined;
        const new_path = try std.fmt.bufPrint(&new_path_buf, "{s}/", .{path});
        try downstream.request.setUriString(new_path);
    }

    try downstream.proxy("origin", null);
}

pub export fn _start() callconv(.c) void {
    start() catch |err| {
        std.debug.print("Error: {}\n", .{err});
    };
}
