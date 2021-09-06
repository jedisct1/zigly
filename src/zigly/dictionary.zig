const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

const wasm = @import("wasm.zig");
const fastly = @import("errors.zig").fastly;
const errors = fastly.errors;
const FastlyError = errors.FastlyError;

pub const Dictionary = struct {
    handle: wasm.DictionaryHandle,

    /// Access a dictionary given its name.
    pub fn open(name: []const u8) !Dictionary {
        var handle: wasm.DictionaryHandle = undefined;
        try fastly(wasm.FastlyDictionary.open(name.ptr, name.len, &handle));
        return Dictionary{ .handle = handle };
    }

    /// Get the value associated to a key.
    pub fn get(self: Dictionary, allocator: *Allocator, name: []const u8) ![]const u8 {
        var value_len_max: usize = 64;
        var value_buf = try allocator.alloc(u8, value_len_max);
        var value_len: usize = undefined;
        while (true) {
            const ret = wasm.FastlyDictionary.get(self.handle, name.ptr, name.len, value_buf.ptr, value_len_max, &value_len);
            if (ret) break else |err| {
                if (err != FastlyError.FastlyBufferTooSmall) {
                    return err;
                }
                value_len_max *= 2;
                value_buf = try allocator.realloc(value_buf, value_len_max);
            }
        }
        return value_buf[0..value_len];
    }
};
