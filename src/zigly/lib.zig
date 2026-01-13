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

/// Check that the module is compatible with the current version of the API.
pub fn compatibilityCheck() !void {
    try fastly(wasm.FastlyAbi.init(1));
}
