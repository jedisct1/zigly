const wasm = @import("wasm.zig");
const fastly = @import("errors.zig").fastly;

/// Parse user agent information.
pub const UserAgent = struct {
    pub fn parse(user_agent: []const u8, family: []u8, major: []u8, minor: []u8, patch: []u8) !struct { family: []u8, major: []u8, minor: []u8, patch: []u8 } {
        var family_len: usize = undefined;
        var major_len: usize = undefined;
        var minor_len: usize = undefined;
        var patch_len: usize = undefined;
        try fastly(wasm.mod_fastly_uap.parse(@ptrCast([*]const u8, user_agent.ptr), user_agent.len, &family, family.len, &family_len, &major, major.len, &major_len, &minor, minor.len, &minor_len, &patch, patch.len, &patch_len));
        const ret = .{
            .family = family[0..family_len],
            .major = major[0..major_len],
            .minor = minor[0..minor_len],
            .patch = patch[0..patch_len],
        };
        return ret;
    }
};
