const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

const wasm = @import("wasm.zig");
const errors = @import("errors.zig");
const fastly = errors.fastly;
const FastlyError = errors.FastlyError;
const http = @import("http.zig");
const Body = http.Body;
const geo = @import("geo.zig");
const Ip = geo.Ip;

pub const AclError = enum(u32) {
    ok = 1,
    no_content = 2,
    too_many_requests = 3,
};

pub const LookupResult = struct {
    body: Body,
    acl_error: AclError,
};

pub const Acl = struct {
    handle: wasm.AclHandle,

    /// Open an ACL by name.
    pub fn open(name: []const u8) !Acl {
        var handle: wasm.AclHandle = undefined;
        try fastly(wasm.FastlyAcl.open(name.ptr, name.len, &handle));
        return Acl{ .handle = handle };
    }

    /// Look up an IP address in the ACL.
    /// Returns a body containing JSON with the lookup result and an ACL-specific error code.
    pub fn lookup(self: Acl, ip: Ip) !LookupResult {
        const ip_bin = if (ip == .ip4) ip.ip4[0..] else ip.ip16[0..];
        var body_handle: wasm.BodyHandle = undefined;
        var acl_error: wasm.AclError = undefined;

        try fastly(wasm.FastlyAcl.lookup(self.handle, ip_bin.ptr, ip_bin.len, &body_handle, &acl_error));

        return LookupResult{
            .body = Body{ .handle = body_handle },
            .acl_error = @enumFromInt(@intFromEnum(acl_error)),
        };
    }

    /// Look up an IP address and read the full JSON response.
    /// Returns the parsed match result or null if no match was found.
    pub fn match(self: Acl, allocator: Allocator, ip: Ip) !?std.json.Parsed(MatchResult) {
        var result = try self.lookup(ip);
        defer result.body.close() catch {};

        if (result.acl_error == .no_content) {
            return null;
        }

        const json_data = try result.body.readAll(allocator, 4096);
        return try std.json.parseFromSlice(
            MatchResult,
            allocator,
            json_data,
            .{ .ignore_unknown_fields = true },
        );
    }
};

/// Result from an ACL match operation.
pub const MatchResult = struct {
    /// The action to take ("ALLOW" or "BLOCK").
    action: []const u8,
    /// The prefix that matched (e.g., "192.168.0.0/16").
    prefix: []const u8,

    /// Check if the action is BLOCK.
    pub fn isBlock(self: MatchResult) bool {
        return std.mem.eql(u8, self.action, "BLOCK");
    }

    /// Check if the action is ALLOW.
    pub fn isAllow(self: MatchResult) bool {
        return std.mem.eql(u8, self.action, "ALLOW");
    }
};
