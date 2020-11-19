const wasm = @import("wasm.zig");
const errors = @import("errors.zig");
const fastly = errors.fastly;

pub const FastlyError = errors.FastlyError;
pub const UserAgent = @import("useragent.zig");
pub const Dictionary = @import("dictionary.zig");
pub const Logger = @import("logger.zig");

const http = @import("http.zig");
pub const Request = http.Request;
pub const downstream = http.downstream;

/// Check that the module is compatible with the current version of the API.
pub fn compatibilityCheck() !void {
    try fastly(wasm.mod_fastly_abi.init(1));
}
