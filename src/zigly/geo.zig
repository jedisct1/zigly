const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

const wasm = @import("wasm.zig");
const fastly = @import("errors.zig").fastly;

pub const Ip = enum(u1) {
    ip4 = [4]u8,
    ip16 = [16]u8,
};

/// Get location information about an IP address.
/// `buf` should be a 256-byte buffer.
/// The function returns a `buf` slice with the location.
pub fn lookup(ip: Ip, buf: [256]u8) ![]const u8 {
    const ip_bin = if (ip == .ip4) ip.ip4[0..] else ip.ip16[0..];
    var len: usize = undefined;
    try wasm.FastlyGeo.lookup(ip_bin, ip_bin.len, buf.ptr, buf.len, &len);
    return buf[0..len];
}
