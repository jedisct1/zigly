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

/// Response from the call to `lookup`.
///
/// {
///   "area_code": 415,
///   "as_name": "Fastly, Inc",
///   "as_number": 54113,
///   "city": "San Francisco",
///   "conn_speed": "broadband",
///   "conn_type": "wired",
///   "continent": "NA",
///   "country_code": "US",
///   "country_code3": "USA",
///   "country_name": "United States of America",
///   "latitude": 37.77869,
///   "longitude": -122.39557,
///   "metro_code": 0,
///   "postal_code": "94107",
///   "proxy_description": "?",
///   "proxy_type": "?",
///   "region": "CA",
///   "utc_offset": -700
/// }
const Location = struct {
    area_code: usize,
    as_name: []const u8,
    as_number: usize,
    city: []const u8,
    conn_speed: []const u8,
    conn_type: []const u8,
    continent: []const u8,
    country_code: []const u8,
    country_code3: []const u8,
    country_name: []const u8,
    latitude: f32,
    longitude: f32,
    metro_code: usize,
    postal_code: []const u8,
    proxy_description: []const u8,
    proxy_type: []const u8,
    region: []const u8,
    utc_offset: isize,
};

/// Get location information about an IP address.
/// The function returns a `buf` slice with the location filled with a json
/// response.
///
/// If `buf` is too small, `FastlyBufferTooSmall` will be returned.
/// 4096 should be a safe size to use.
pub fn lookup(allocator: std.mem.Allocator, ip: Ip, buf: []u8) !std.json.Parsed(Location) {
    const ip_bin = if (ip == .ip4) ip.ip4[0..] else ip.ip16[0..];
    var len: usize = undefined;

    try fastly(wasm.FastlyGeo.lookup(ip_bin.ptr, ip_bin.len, buf.ptr, buf.len, &len));

    return try std.json.parseFromSlice(Location, allocator, buf[0..len], .{});
}
