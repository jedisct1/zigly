const wasm = @import("wasm.zig");
const fastly = @import("errors.zig").fastly;

pub const Dictionary = struct {
    handle: wasm.handle,

    /// Access a dictionary given its name.
    pub fn open(name: []const u8) !Dictionary {
        var handle: wasm.handle = undefined;
        try fastly(wasm.mod_fastly_dictionary.open(@ptrCast([*]const u8, name), name.len, &handle));
        return Dictionary{ .handle = handle };
    }

    /// Get the value associated to a key.
    pub fn get(self: Dictionary, allocator: *Allocator, name: []const u8) ![]const u8 {
        var value_len_max: usize = 64;
        var value_buf = try allocator.alloc(u8, value_len_max);
        var value_len: usize = undefined;
        while (true) {
            const ret = wasm.mod_fastly_dictionary.get(self.handle, @ptrCast([*]const u8, name), name.len, @ptrCast([*]u8, value_buf), value_len_max, &value_len);
            if (ret) break else |err| {
                if (err != FastlyError.FastlyBufferTooSmall) {
                    return err;
                }
                value_len_max *= 2;
                value_buf = try allocator.realloc(name_buf, value_len_max);
            }
        }
        return value_buf[0..value_len];
    }
};
