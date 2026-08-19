const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

const http = @import("http.zig");
const Body = http.Body;

const wasm = @import("wasm.zig");
const errors = @import("errors.zig");
const fastly = errors.fastly;
const FastlyError = errors.FastlyError;

/// Errors reported by the KV store itself.
/// Transport-level failures surface as `FastlyError` instead.
pub const KvError = error{
    Uninitialized,
    BadRequest,
    NotFound,
    PreconditionFailed,
    PayloadTooLarge,
    Internal,
    TooManyRequests,
};

fn check(kv_error: wasm.KvError) KvError!void {
    switch (kv_error) {
        .OK => {},
        .UNINITIALIZED => return KvError.Uninitialized,
        .BAD_REQUEST => return KvError.BadRequest,
        .NOT_FOUND => return KvError.NotFound,
        .PRECONDITION_FAILED => return KvError.PreconditionFailed,
        .PAYLOAD_TOO_LARGE => return KvError.PayloadTooLarge,
        .INTERNAL_ERROR => return KvError.Internal,
        .TOO_MANY_REQUESTS => return KvError.TooManyRequests,
    }
}

/// The platform caps metadata at 2000 bytes, so this buffer always fits.
const max_metadata_length: usize = 2048;

/// How an insert behaves when the key already exists.
pub const InsertMode = enum {
    overwrite,
    add,
    append,
    prepend,

    fn toWasm(mode: InsertMode) wasm.KvInsertMode {
        return switch (mode) {
            .overwrite => .OVERWRITE,
            .add => .ADD,
            .append => .APPEND,
            .prepend => .PREPEND,
        };
    }
};

pub const InsertOptions = struct {
    mode: InsertMode = .overwrite,
    /// Optional metadata stored along with the value, up to 2000 bytes.
    metadata: ?[]const u8 = null,
    /// Expiration delay in seconds.
    time_to_live_sec: ?u32 = null,
    /// Only perform the insert if the current generation matches this value.
    if_generation_match: ?u64 = null,
    background_fetch: bool = false,
};

pub const ListOptions = struct {
    /// Cursor returned by a previous list call, to resume pagination.
    cursor: ?[]const u8 = null,
    /// Maximum number of keys to return.
    limit: ?u32 = null,
    /// Only list keys starting with this prefix.
    prefix: ?[]const u8 = null,
    eventual_consistency: bool = false,
};

/// A value found by `lookup`.
/// The body still has to be read, and the metadata is owned by the caller.
pub const LookupResult = struct {
    body: Body,
    metadata: ?[]const u8,
    generation: u64,

    pub fn deinit(self: *LookupResult, allocator: Allocator) void {
        if (self.metadata) |metadata| allocator.free(metadata);
        self.metadata = null;
    }
};

pub const Store = struct {
    handle: wasm.KvStoreHandle,

    /// Open the KV store with the given name.
    pub fn open(name: []const u8) !Store {
        var handle: wasm.KvStoreHandle = undefined;
        try fastly(wasm.FastlyKvStore.open(name.ptr, name.len, &handle));
        return Store{ .handle = handle };
    }

    /// Look up a key and return its body, metadata and generation.
    /// The allocator is only used for the metadata copy.
    /// Returns `error.NotFound` if the key doesn't exist.
    pub fn lookup(store: Store, key: []const u8, allocator: Allocator) !LookupResult {
        var config = wasm.KvLookupConfig{ .reserved = 0 };
        var lookup_handle: wasm.KvStoreLookupHandle = undefined;
        try fastly(wasm.FastlyKvStore.lookup(store.handle, key.ptr, key.len, 0, &config, &lookup_handle));

        var body_handle: wasm.BodyHandle = undefined;
        var metadata_buf: [max_metadata_length]u8 = undefined;
        var metadata_len: usize = 0;
        var generation: u64 = undefined;
        var kv_error = wasm.KvError.UNINITIALIZED;
        try fastly(wasm.FastlyKvStore.lookup_wait_v2(
            lookup_handle,
            &body_handle,
            &metadata_buf,
            metadata_buf.len,
            &metadata_len,
            &generation,
            &kv_error,
        ));
        try check(kv_error);

        const metadata: ?[]const u8 = if (metadata_len == 0) null else try allocator.dupe(u8, metadata_buf[0..metadata_len]);
        return LookupResult{
            .body = Body{ .handle = body_handle },
            .metadata = metadata,
            .generation = generation,
        };
    }

    /// Look up a key and return its value as newly allocated bytes.
    /// Metadata and generation are discarded; use `lookup` to get them.
    pub fn getAll(store: Store, key: []const u8, allocator: Allocator, max_length: usize) ![]u8 {
        var result = try store.lookup(key, allocator);
        defer result.deinit(allocator);
        return try result.body.readAll(allocator, max_length);
    }

    /// Insert or update a value.
    pub fn insert(store: Store, key: []const u8, value: []const u8, options: InsertOptions) !void {
        var body_handle: wasm.BodyHandle = undefined;
        try fastly(wasm.FastlyHttpBody.new(&body_handle));
        var body = Body{ .handle = body_handle };
        try body.writeAll(value);

        var mask: wasm.KvInsertConfigOptions = 0;
        var config = wasm.KvInsertConfig{
            .mode = options.mode.toWasm(),
            .unused = 0,
            .metadata = null,
            .metadata_len = 0,
            .time_to_live_sec = 0,
            .if_generation_match = 0,
        };
        if (options.metadata) |metadata| {
            mask |= wasm.KV_INSERT_CONFIG_OPTIONS_METADATA;
            config.metadata = @constCast(metadata.ptr);
            config.metadata_len = @intCast(metadata.len);
        }
        if (options.time_to_live_sec) |ttl| {
            mask |= wasm.KV_INSERT_CONFIG_OPTIONS_TIME_TO_LIVE_SEC;
            config.time_to_live_sec = ttl;
        }
        if (options.if_generation_match) |generation| {
            mask |= wasm.KV_INSERT_CONFIG_OPTIONS_IF_GENERATION_MATCH;
            config.if_generation_match = generation;
        }
        if (options.background_fetch) {
            mask |= wasm.KV_INSERT_CONFIG_OPTIONS_BACKGROUND_FETCH;
        }

        var insert_handle: wasm.KvStoreInsertHandle = undefined;
        try fastly(wasm.FastlyKvStore.insert(store.handle, key.ptr, key.len, body_handle, mask, &config, &insert_handle));

        var kv_error = wasm.KvError.UNINITIALIZED;
        try fastly(wasm.FastlyKvStore.insert_wait(insert_handle, &kv_error));
        try check(kv_error);
    }

    /// Delete a key.
    /// Returns `error.NotFound` if the key doesn't exist.
    pub fn delete(store: Store, key: []const u8) !void {
        var config = wasm.KvDeleteConfig{ .reserved = 0 };
        var delete_handle: wasm.KvStoreDeleteHandle = undefined;
        try fastly(wasm.FastlyKvStore.delete(store.handle, key.ptr, key.len, 0, &config, &delete_handle));

        var kv_error = wasm.KvError.UNINITIALIZED;
        try fastly(wasm.FastlyKvStore.delete_wait(delete_handle, &kv_error));
        try check(kv_error);
    }

    /// List keys, returned as a JSON document in an HTTP body.
    /// The document contains the matching keys and a cursor for pagination.
    pub fn listAsHttpBody(store: Store, options: ListOptions) !Body {
        var mask: wasm.KvListConfigOptions = 0;
        var config = wasm.KvListConfig{
            .mode = if (options.eventual_consistency) .EVENTUAL else .STRONG,
            .cursor = null,
            .cursor_len = 0,
            .limit = 0,
            .prefix = null,
            .prefix_len = 0,
        };
        if (options.cursor) |cursor| {
            mask |= wasm.KV_LIST_CONFIG_OPTIONS_CURSOR;
            config.cursor = @constCast(cursor.ptr);
            config.cursor_len = @intCast(cursor.len);
        }
        if (options.limit) |limit| {
            mask |= wasm.KV_LIST_CONFIG_OPTIONS_LIMIT;
            config.limit = limit;
        }
        if (options.prefix) |prefix| {
            mask |= wasm.KV_LIST_CONFIG_OPTIONS_PREFIX;
            config.prefix = @constCast(prefix.ptr);
            config.prefix_len = @intCast(prefix.len);
        }

        var list_handle: wasm.KvStoreListHandle = undefined;
        try fastly(wasm.FastlyKvStore.list(store.handle, mask, &config, &list_handle));

        var body_handle: wasm.BodyHandle = undefined;
        var kv_error = wasm.KvError.UNINITIALIZED;
        try fastly(wasm.FastlyKvStore.list_wait(list_handle, &body_handle, &kv_error));
        try check(kv_error);

        return Body{ .handle = body_handle };
    }

    /// List keys and return the JSON document as newly allocated bytes.
    pub fn list(store: Store, allocator: Allocator, options: ListOptions, max_length: usize) ![]u8 {
        var body = try store.listAsHttpBody(options);
        return try body.readAll(allocator, max_length);
    }
};
