// Simple Proxy Example
// Proxies requests to an origin server with optional modifications

const std = @import("std");
const zigly = @import("zigly");

pub fn main() !void {
    var downstream = try zigly.downstream();

    // Add a custom header to identify edge processing
    try downstream.request.headers.set("X-Edge-Processed", "true");

    // Proxy to the origin backend
    try downstream.proxy("origin", null);
}
