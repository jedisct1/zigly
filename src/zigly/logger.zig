const wasm = @import("wasm.zig");
const fastly = @import("errors.zig").fastly;

pub const Logger = struct {
    handle: wasm.handle,

    /// Create a logger for a given endpoint.
    pub fn open(name: []const u8) !Logger {
        var handle: wasm.handle = undefined;
        try fastly(wasm.mod_fastly_log.endpoint_get(@ptrCast([*]const u8, name), name.len, &handle));
        return Logger{ .handle = handle };
    }

    /// Send a message to a logging endpoint.
    pub fn write(self: *Logger, msg: []const u8) !void {
        var written: usize = undefined;
        try fastly(wasm.mod_fastly_log.write(self.handle, @ptrCast([*]const u8, msg), msg.len, &written));
    }
};
