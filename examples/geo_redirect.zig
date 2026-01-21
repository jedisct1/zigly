// Geo Redirect Example
// Redirects users to country-specific sites based on their IP location

const std = @import("std");
const zigly = @import("zigly");
const geo = zigly.geo;

fn start() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var downstream = try zigly.downstream();

    // Get client IP and look up location
    const client_ip = try zigly.http.Downstream.getClientIpAddr();

    var buf: [4096]u8 = undefined;
    const result = geo.lookup(allocator, client_ip, &buf) catch {
        // If geo lookup fails, proceed to default
        try downstream.proxy("origin", null);
        return;
    };
    const country = result.value.country_code;

    // Get current path using the URI helper
    var uri_buf: [4096]u8 = undefined;
    const path = try downstream.request.getPath(&uri_buf);

    // Skip redirect for certain paths
    if (std.mem.startsWith(u8, path, "/api/") or
        std.mem.startsWith(u8, path, "/static/"))
    {
        try downstream.proxy("origin", null);
        return;
    }

    // Redirect based on country
    var redirect_buf: [256]u8 = undefined;
    if (std.mem.eql(u8, country, "DE") or
        std.mem.eql(u8, country, "AT") or
        std.mem.eql(u8, country, "CH"))
    {
        const redirect = try std.fmt.bufPrint(&redirect_buf, "https://de.example.com{s}", .{path});
        try downstream.redirect(302, redirect);
    } else if (std.mem.eql(u8, country, "FR") or
        std.mem.eql(u8, country, "BE"))
    {
        const redirect = try std.fmt.bufPrint(&redirect_buf, "https://fr.example.com{s}", .{path});
        try downstream.redirect(302, redirect);
    } else if (std.mem.eql(u8, country, "JP")) {
        const redirect = try std.fmt.bufPrint(&redirect_buf, "https://jp.example.com{s}", .{path});
        try downstream.redirect(302, redirect);
    } else {
        // Default: proxy to origin without redirect
        try downstream.proxy("origin", null);
    }
}

pub export fn _start() callconv(.c) void {
    start() catch |err| {
        std.debug.print("Error: {}\n", .{err});
    };
}
