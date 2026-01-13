const wasm = @import("wasm.zig");
const fastly = @import("errors.zig").fastly;

pub const PurgeOptions = struct {
    /// Perform a soft purge (mark as stale) instead of a hard purge (immediate removal).
    soft_purge: bool = false,
};

/// Purge cached content by surrogate key.
pub fn purgeSurrogateKey(surrogate_key: []const u8, options: PurgeOptions) !void {
    var options_mask: wasm.PurgeOptionsMask = 0;
    if (options.soft_purge) {
        options_mask |= wasm.PURGE_OPTIONS_MASK_SOFT_PURGE;
    }

    var purge_options = wasm.PurgeOptions{
        .ret_buf_ptr = undefined,
        .ret_buf_len = 0,
        .ret_buf_nwritten_out = undefined,
    };

    try fastly(wasm.FastlyPurge.purge_surrogate_key(
        surrogate_key.ptr,
        surrogate_key.len,
        options_mask,
        &purge_options,
    ));
}

/// Purge cached content by surrogate key (hard purge).
pub fn purge(surrogate_key: []const u8) !void {
    return purgeSurrogateKey(surrogate_key, .{});
}

/// Soft purge cached content by surrogate key (mark as stale).
pub fn softPurge(surrogate_key: []const u8) !void {
    return purgeSurrogateKey(surrogate_key, .{ .soft_purge = true });
}
