const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

const Body = @import("http").Body;

const wasm = @import("wasm.zig");
const errors = @import("errors.zig");
const fastly = errors.fastly;

pub const Store = struct {
    handle: wasm.KvStoreHandle,

    pub fn open(name: []const u8) !Store {
        var handle: wasm.KvStoreHandle = -1;
        try fastly(wasm.FastlyKv.open(name.ptr, name.len, &handle));
        if (handle == -1) {
            return errors.FastlyError.FastlyInvalidValue;
        }
        return Store{ .handle = handle };
    }

    pub fn close(_: *Store) !void {
        // No-op; there is no close() hostcall.
    }

    pub fn getAsHttpBody(store: *Store, key: []const u8) !Body {
        var body_handle: wasm.KvStoreBodyHandle = -1;
        try fastly(wasm.FastlyKv.lookup(store.handle, key.ptr, key.len, &body_handle));
        if (body_handle == -1) {
            return fastly(wasm.FastlyStatus.INVAL);
        }
        return Body{ .handle = body_handle };
    }

    pub fn getAll(store: *Store, key: []const u8, allocator: Allocator, max_length: usize) !void {
        var body = try getAsHttpBody(store, key);
        try body.readAll(allocator, max_length);
    }

    pub fn replace(store: *Store, key: []const u8, value: []const u8, ttl: u32) !void {
        var body_handle: wasm.KvStoreBodyHandle = undefined;
        try fastly(wasm.FastlyHttpBody.new(&body_handle));

        var body: Body = Body{ .handle = body_handle };
        try body.writeAll(value);

        var inserted: wasm.Inserted = undefined;
        try fastly(wasm.FastlyKv.insert(store.handle, key.ptr, key.len, body_handle, ttl, inserted));
    }
};
