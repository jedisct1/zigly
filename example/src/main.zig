const std = @import("std");
const zigly = @import("zigly");

// The backend name (registered as a "host" for that service in the Fastly UI)
const backend_name = "backend";
// The hostname to use in the Host header when making requests to the backend
// It can be set to `null` to use the original Host header
const host_header = "example.com";

// Proxy all incoming requests to the backend, with transparent caching.
pub fn main() !void {
    var downstream = try zigly.downstream();
    try downstream.proxy(backend_name, host_header);
}
