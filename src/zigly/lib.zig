const wasm = @import("wasm.zig");
const errors = @import("errors.zig");
const fastly = errors.fastly;

pub const Uri = @import("zuri/zuri.zig").Uri;

pub const FastlyError = errors.FastlyError;
pub const UserAgent = @import("useragent.zig").UserAgent;
pub const Dictionary = @import("dictionary.zig").Dictionary;
pub const Logger = @import("logger.zig").Logger;
const http = @import("http.zig");
pub const Request = http.Request;
pub const Downstream = http.Downstream;
pub const downstream = http.downstream;
pub const geo = @import("geo.zig");
pub const kv = @import("kv.zig");

/// Check that the module is compatible with the current version of the API.
pub fn compatibilityCheck() !void {
    try fastly(wasm.FastlyAbi.init(1));
}
