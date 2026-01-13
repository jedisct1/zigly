const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

const http = @import("http.zig");
const Body = http.Body;

const wasm = @import("wasm.zig");
const errors = @import("errors.zig");
const fastly = errors.fastly;
const FastlyError = errors.FastlyError;

pub const Store = struct {
    handle: wasm.ObjectStoreHandle,

    pub fn open(name: []const u8) !Store {
        var handle: wasm.ObjectStoreHandle = -1;
        try fastly(wasm.FastlyKv.open(name.ptr, name.len, &handle));
        if (handle == -1) {
            return FastlyError.FastlyInvalidValue;
        }
        return Store{ .handle = handle };
    }

    pub fn close(_: *Store) !void {
        // No-op; there is no close() hostcall.
    }

    pub fn getAsHttpBody(store: *Store, key: []const u8) !Body {
        var body_handle: wasm.BodyHandle = -1;
        try fastly(wasm.FastlyKv.lookup(store.handle, key.ptr, key.len, &body_handle));
        if (body_handle == -1) {
            return FastlyError.FastlyNone;
        }
        return Body{ .handle = body_handle };
    }

    pub fn getAll(store: *Store, key: []const u8, allocator: Allocator, max_length: usize) ![]u8 {
        var body = try store.getAsHttpBody(key);
        return try body.readAll(allocator, max_length);
    }

    /// Insert or replace a value in the KV store.
    /// Note: The deprecated object_store API does not support TTL.
    pub fn replace(store: *Store, key: []const u8, value: []const u8) !void {
        var body_handle: wasm.BodyHandle = undefined;
        try fastly(wasm.FastlyHttpBody.new(&body_handle));

        var body: Body = Body{ .handle = body_handle };
        try body.writeAll(value);

        try fastly(wasm.FastlyKv.insert(store.handle, key.ptr, key.len, body_handle));
    }
};
