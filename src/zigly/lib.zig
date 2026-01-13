const std = @import("std");
const wasm = @import("wasm.zig");
const errors = @import("errors.zig");
const fastly = errors.fastly;

pub const Uri = std.Uri;

pub const FastlyError = errors.FastlyError;
pub const UserAgent = @import("useragent.zig").UserAgent;
pub const Dictionary = @import("dictionary.zig").Dictionary;
pub const Logger = @import("logger.zig").Logger;
pub const http = @import("http.zig");
pub const downstream = http.downstream;
pub const geo = @import("geo.zig");
pub const kv = @import("kv.zig");
pub const backend = @import("backend.zig");
pub const Backend = backend.Backend;
pub const DynamicBackend = backend.DynamicBackend;
pub const acl = @import("acl.zig");
pub const Acl = acl.Acl;
pub const purge = @import("purge.zig");
pub const device = @import("device.zig");
pub const runtime = @import("runtime.zig");
pub const cache = @import("cache.zig");
pub const erl = @import("erl.zig");
pub const RateLimiter = erl.RateLimiter;
pub const RateCounter = erl.RateCounter;
pub const PenaltyBox = erl.PenaltyBox;

/// Check that the module is compatible with the current version of the API.
pub fn compatibilityCheck() !void {
    try fastly(wasm.FastlyAbi.init(1));
}
