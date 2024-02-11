const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

const wasm = @import("wasm.zig");
const fastly = @import("errors.zig").fastly;

pub const Ip = union(enum) {
    ip4: [4]u8,
    ip16: [16]u8,

    pub fn print(self: Ip, alloc: std.mem.Allocator) ![]const u8 {
        if (self == .ip4) {
            return try std.fmt.allocPrint(
                alloc,
                "{}.{}.{}.{}",
                .{
                    self.ip4[0],
                    self.ip4[1],
                    self.ip4[2],
                    self.ip4[3],
                },
            );
        }

        return try std.fmt.allocPrint(
            alloc,
            "{x:0>2}{x:0>2}:{x:0>2}{x:0>2}:{x:0>2}{x:0>2}:{x:0>2}{x:0>2}:{x:0>2}{x:0>2}:{x:0>2}{x:0>2}:{x:0>2}{x:0>2}:{x:0>2}{x:0>2}",
            .{
                self.ip16[0],
                self.ip16[1],
                self.ip16[2],
                self.ip16[3],
                self.ip16[4],
                self.ip16[5],
                self.ip16[6],
                self.ip16[7],
                self.ip16[8],
                self.ip16[9],
                self.ip16[10],
                self.ip16[11],
                self.ip16[12],
                self.ip16[13],
                self.ip16[14],
                self.ip16[15],
            },
        );
    }
};

test "IPv4 print" {
    const v4 = Ip{ .ip4 = .{ 127, 0, 0, 1 } };
    try std.testing.expectEqualStrings(try v4.print(std.heap.page_allocator), "127.0.0.1");
}

test "IPv6 print" {
    var v6 = Ip{ .ip16 = .{0xff} ** 16 };
    try std.testing.expectEqualStrings(
        try v6.print(std.heap.page_allocator),
        "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff",
    );

    v6.ip16[8] = 0x00;
    v6.ip16[13] = 0xaa;
    try std.testing.expectEqualStrings(
        try v6.print(std.heap.page_allocator),
        "ffff:ffff:ffff:ffff:00ff:ffff:ffaa:ffff",
    );
}

/// Get location information about an IP address.
/// `buf` should be a 256-byte buffer.
/// The function returns a `buf` slice with the location.
pub fn lookup(ip: Ip, buf: [256]u8) ![]const u8 {
    const ip_bin = if (ip == .ip4) ip.ip4[0..] else ip.ip16[0..];
    var len: usize = undefined;
    try wasm.FastlyGeo.lookup(ip_bin, ip_bin.len, buf.ptr, buf.len, &len);
    return buf[0..len];
}
