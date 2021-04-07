const wasm = @import("wasm.zig");
const fastly = @import("errors.zig").fastly;

pub const Logger = struct {
    handle: wasm.EndpointHandle,

    /// Create a logger for a given endpoint.
    pub fn open(name: []const u8) !Logger {
        var handle: wasm.EndpointHandle = undefined;
        try fastly(wasm.FastlyLog.endpoint_get(name.ptr, name.len, &handle));
        return Logger{ .handle = handle };
    }

    /// Send a message to a logging endpoint.
    pub fn write(self: *Logger, msg: []const u8) !void {
        var written: usize = undefined;
        try fastly(wasm.FastlyLog.write(self.handle, msg.ptr, msg.len, &written));
    }
};
