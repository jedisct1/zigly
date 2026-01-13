const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

const wasm = @import("wasm.zig");
const errors = @import("errors.zig");
const fastly = errors.fastly;
const FastlyError = errors.FastlyError;
const http = @import("http.zig");
const Body = http.Body;

pub const LookupState = struct {
    value: wasm.CacheLookupState,

    pub fn isFound(self: LookupState) bool {
        return (self.value & wasm.CACHE_LOOKUP_STATE_FOUND) != 0;
    }

    pub fn isUsable(self: LookupState) bool {
        return (self.value & wasm.CACHE_LOOKUP_STATE_USABLE) != 0;
    }

    pub fn isStale(self: LookupState) bool {
        return (self.value & wasm.CACHE_LOOKUP_STATE_STALE) != 0;
    }

    pub fn mustInsertOrUpdate(self: LookupState) bool {
        return (self.value & wasm.CACHE_LOOKUP_STATE_MUST_INSERT_OR_UPDATE) != 0;
    }
};

pub const WriteOptions = struct {
    max_age_ns: u64 = 0,
    initial_age_ns: ?u64 = null,
    stale_while_revalidate_ns: ?u64 = null,
    surrogate_keys: ?[]const u8 = null,
    length: ?u64 = null,
    user_metadata: ?[]const u8 = null,
    sensitive_data: bool = false,
    vary_rule: ?[]const u8 = null,
    edge_max_age_ns: ?u64 = null,
};

pub const LookupOptions = struct {
    request_headers: ?wasm.RequestHandle = null,
};

pub const BodyRange = struct {
    from: u64 = 0,
    to: u64 = 0,
};

pub const CacheEntry = struct {
    handle: wasm.CacheHandle,

    pub fn getState(self: CacheEntry) !LookupState {
        var state: wasm.CacheLookupState = undefined;
        try fastly(wasm.FastlyCache.get_state(self.handle, &state));
        return LookupState{ .value = state };
    }

    pub fn getBody(self: CacheEntry, range: ?BodyRange) !Body {
        var body_handle: wasm.BodyHandle = undefined;
        var options_mask: wasm.CacheGetBodyOptionsMask = 0;
        var options = wasm.CacheGetBodyOptions{ .from = 0, .to = 0 };

        if (range) |r| {
            options_mask |= wasm.CACHE_GET_BODY_OPTIONS_MASK_FROM;
            options_mask |= wasm.CACHE_GET_BODY_OPTIONS_MASK_TO;
            options.from = r.from;
            options.to = r.to;
        }

        try fastly(wasm.FastlyCache.get_body(self.handle, options_mask, options, &body_handle));
        return Body{ .handle = body_handle };
    }

    pub fn getUserMetadata(self: CacheEntry, allocator: Allocator) ![]u8 {
        var buf_len: usize = 256;
        var buf = try allocator.alloc(u8, buf_len);
        var nwritten: usize = undefined;

        while (true) {
            const ret = fastly(wasm.FastlyCache.get_user_metadata(self.handle, buf.ptr, buf_len, &nwritten));
            if (ret) break else |err| {
                if (err != FastlyError.FastlyBufferTooSmall) {
                    return err;
                }
                buf_len *= 2;
                buf = try allocator.realloc(buf, buf_len);
            }
        }
        return buf[0..nwritten];
    }

    pub fn getLength(self: CacheEntry) !u64 {
        var length: wasm.CacheObjectLength = undefined;
        try fastly(wasm.FastlyCache.get_length(self.handle, &length));
        return length;
    }

    pub fn getMaxAgeNs(self: CacheEntry) !u64 {
        var max_age: wasm.CacheDurationNs = undefined;
        try fastly(wasm.FastlyCache.get_max_age_ns(self.handle, &max_age));
        return max_age;
    }

    pub fn getStaleWhileRevalidateNs(self: CacheEntry) !u64 {
        var swr: wasm.CacheDurationNs = undefined;
        try fastly(wasm.FastlyCache.get_stale_while_revalidate_ns(self.handle, &swr));
        return swr;
    }

    pub fn getAgeNs(self: CacheEntry) !u64 {
        var age: wasm.CacheDurationNs = undefined;
        try fastly(wasm.FastlyCache.get_age_ns(self.handle, &age));
        return age;
    }

    pub fn getHits(self: CacheEntry) !u64 {
        var hits: wasm.CacheHitCount = undefined;
        try fastly(wasm.FastlyCache.get_hits(self.handle, &hits));
        return hits;
    }

    pub fn close(self: *CacheEntry) !void {
        try fastly(wasm.FastlyCache.close(self.handle));
    }
};

pub const Transaction = struct {
    handle: wasm.CacheHandle,

    pub fn getState(self: Transaction) !LookupState {
        var state: wasm.CacheLookupState = undefined;
        try fastly(wasm.FastlyCache.get_state(self.handle, &state));
        return LookupState{ .value = state };
    }

    pub fn getBody(self: Transaction, range: ?BodyRange) !Body {
        var body_handle: wasm.BodyHandle = undefined;
        var options_mask: wasm.CacheGetBodyOptionsMask = 0;
        var options = wasm.CacheGetBodyOptions{ .from = 0, .to = 0 };

        if (range) |r| {
            options_mask |= wasm.CACHE_GET_BODY_OPTIONS_MASK_FROM;
            options_mask |= wasm.CACHE_GET_BODY_OPTIONS_MASK_TO;
            options.from = r.from;
            options.to = r.to;
        }

        try fastly(wasm.FastlyCache.get_body(self.handle, options_mask, options, &body_handle));
        return Body{ .handle = body_handle };
    }

    pub fn getUserMetadata(self: Transaction, allocator: Allocator) ![]u8 {
        var buf_len: usize = 256;
        var buf = try allocator.alloc(u8, buf_len);
        var nwritten: usize = undefined;

        while (true) {
            const ret = fastly(wasm.FastlyCache.get_user_metadata(self.handle, buf.ptr, buf_len, &nwritten));
            if (ret) break else |err| {
                if (err != FastlyError.FastlyBufferTooSmall) {
                    return err;
                }
                buf_len *= 2;
                buf = try allocator.realloc(buf, buf_len);
            }
        }
        return buf[0..nwritten];
    }

    pub fn getLength(self: Transaction) !u64 {
        var length: wasm.CacheObjectLength = undefined;
        try fastly(wasm.FastlyCache.get_length(self.handle, &length));
        return length;
    }

    pub fn getMaxAgeNs(self: Transaction) !u64 {
        var max_age: wasm.CacheDurationNs = undefined;
        try fastly(wasm.FastlyCache.get_max_age_ns(self.handle, &max_age));
        return max_age;
    }

    pub fn getStaleWhileRevalidateNs(self: Transaction) !u64 {
        var swr: wasm.CacheDurationNs = undefined;
        try fastly(wasm.FastlyCache.get_stale_while_revalidate_ns(self.handle, &swr));
        return swr;
    }

    pub fn getAgeNs(self: Transaction) !u64 {
        var age: wasm.CacheDurationNs = undefined;
        try fastly(wasm.FastlyCache.get_age_ns(self.handle, &age));
        return age;
    }

    pub fn getHits(self: Transaction) !u64 {
        var hits: wasm.CacheHitCount = undefined;
        try fastly(wasm.FastlyCache.get_hits(self.handle, &hits));
        return hits;
    }

    pub const InsertResult = struct {
        body: Body,
    };

    pub const InsertAndStreamBackResult = struct {
        body: Body,
        entry: CacheEntry,
    };

    pub fn insert(self: *Transaction, options: WriteOptions) !InsertResult {
        var body_handle: wasm.BodyHandle = undefined;
        var opts = buildWriteOptions(options);
        const mask = buildWriteOptionsMask(options);

        try fastly(wasm.FastlyCache.transaction_insert(self.handle, mask, &opts, &body_handle));
        return InsertResult{ .body = Body{ .handle = body_handle } };
    }

    pub fn insertAndStreamBack(self: *Transaction, options: WriteOptions) !InsertAndStreamBackResult {
        var body_handle: wasm.BodyHandle = undefined;
        var cache_handle: wasm.CacheHandle = undefined;
        var opts = buildWriteOptions(options);
        const mask = buildWriteOptionsMask(options);

        try fastly(wasm.FastlyCache.transaction_insert_and_stream_back(self.handle, mask, &opts, &body_handle, &cache_handle));
        return InsertAndStreamBackResult{
            .body = Body{ .handle = body_handle },
            .entry = CacheEntry{ .handle = cache_handle },
        };
    }

    pub fn update(self: *Transaction, options: WriteOptions) !void {
        var opts = buildWriteOptions(options);
        const mask = buildWriteOptionsMask(options);
        try fastly(wasm.FastlyCache.transaction_update(self.handle, mask, &opts));
    }

    pub fn cancel(self: *Transaction) !void {
        try fastly(wasm.FastlyCache.transaction_cancel(self.handle));
    }

    pub fn close(self: *Transaction) !void {
        try fastly(wasm.FastlyCache.close(self.handle));
    }
};

pub const BusyHandle = struct {
    handle: wasm.CacheBusyHandle,

    pub fn wait(self: *BusyHandle) !Transaction {
        var cache_handle: wasm.CacheHandle = undefined;
        try fastly(wasm.FastlyCache.cache_busy_handle_wait(self.handle, &cache_handle));
        return Transaction{ .handle = cache_handle };
    }

    pub fn close(self: *BusyHandle) !void {
        try fastly(wasm.FastlyCache.close_busy(self.handle));
    }
};

pub const ReplaceHandle = struct {
    handle: wasm.CacheReplaceHandle,

    pub fn insert(self: *ReplaceHandle, options: WriteOptions) !Body {
        var body_handle: wasm.BodyHandle = undefined;
        var opts = buildWriteOptions(options);
        const mask = buildWriteOptionsMask(options);

        try fastly(wasm.FastlyCache.replace_insert(self.handle, mask, &opts, &body_handle));
        return Body{ .handle = body_handle };
    }

    pub fn getState(self: ReplaceHandle) !LookupState {
        var state: wasm.CacheLookupState = undefined;
        try fastly(wasm.FastlyCache.replace_get_state(self.handle, &state));
        return LookupState{ .value = state };
    }

    pub fn getBody(self: ReplaceHandle, range: ?BodyRange) !Body {
        var body_handle: wasm.BodyHandle = undefined;
        var options_mask: wasm.CacheGetBodyOptionsMask = 0;
        var options = wasm.CacheGetBodyOptions{ .from = 0, .to = 0 };

        if (range) |r| {
            options_mask |= wasm.CACHE_GET_BODY_OPTIONS_MASK_FROM;
            options_mask |= wasm.CACHE_GET_BODY_OPTIONS_MASK_TO;
            options.from = r.from;
            options.to = r.to;
        }

        try fastly(wasm.FastlyCache.replace_get_body(self.handle, options_mask, options, &body_handle));
        return Body{ .handle = body_handle };
    }

    pub fn getUserMetadata(self: ReplaceHandle, allocator: Allocator) ![]u8 {
        var buf_len: usize = 256;
        var buf = try allocator.alloc(u8, buf_len);
        var nwritten: usize = undefined;

        while (true) {
            const ret = fastly(wasm.FastlyCache.replace_get_user_metadata(self.handle, buf.ptr, buf_len, &nwritten));
            if (ret) break else |err| {
                if (err != FastlyError.FastlyBufferTooSmall) {
                    return err;
                }
                buf_len *= 2;
                buf = try allocator.realloc(buf, buf_len);
            }
        }
        return buf[0..nwritten];
    }

    pub fn getLength(self: ReplaceHandle) !u64 {
        var length: wasm.CacheObjectLength = undefined;
        try fastly(wasm.FastlyCache.replace_get_length(self.handle, &length));
        return length;
    }

    pub fn getMaxAgeNs(self: ReplaceHandle) !u64 {
        var max_age: wasm.CacheDurationNs = undefined;
        try fastly(wasm.FastlyCache.replace_get_max_age_ns(self.handle, &max_age));
        return max_age;
    }

    pub fn getStaleWhileRevalidateNs(self: ReplaceHandle) !u64 {
        var swr: wasm.CacheDurationNs = undefined;
        try fastly(wasm.FastlyCache.replace_get_stale_while_revalidate_ns(self.handle, &swr));
        return swr;
    }

    pub fn getAgeNs(self: ReplaceHandle) !u64 {
        var age: wasm.CacheDurationNs = undefined;
        try fastly(wasm.FastlyCache.replace_get_age_ns(self.handle, &age));
        return age;
    }

    pub fn getHits(self: ReplaceHandle) !u64 {
        var hits: wasm.CacheHitCount = undefined;
        try fastly(wasm.FastlyCache.replace_get_hits(self.handle, &hits));
        return hits;
    }
};

fn buildWriteOptions(options: WriteOptions) wasm.CacheWriteOptions {
    return wasm.CacheWriteOptions{
        .max_age_ns = options.max_age_ns,
        .request_headers = 0,
        .vary_rule_ptr = if (options.vary_rule) |v| @constCast(v.ptr) else null,
        .vary_rule_len = if (options.vary_rule) |v| v.len else 0,
        .initial_age_ns = options.initial_age_ns orelse 0,
        .stale_while_revalidate_ns = options.stale_while_revalidate_ns orelse 0,
        .surrogate_keys_ptr = if (options.surrogate_keys) |s| @constCast(s.ptr) else null,
        .surrogate_keys_len = if (options.surrogate_keys) |s| s.len else 0,
        .length = options.length orelse 0,
        .user_metadata_ptr = if (options.user_metadata) |u| @constCast(u.ptr) else null,
        .user_metadata_len = if (options.user_metadata) |u| u.len else 0,
        .edge_max_age_ns = options.edge_max_age_ns orelse 0,
        .service_id = null,
        .service_id_len = 0,
    };
}

fn buildWriteOptionsMask(options: WriteOptions) wasm.CacheWriteOptionsMask {
    var mask: wasm.CacheWriteOptionsMask = 0;

    if (options.initial_age_ns != null) {
        mask |= wasm.CACHE_WRITE_OPTIONS_MASK_INITIAL_AGE_NS;
    }
    if (options.stale_while_revalidate_ns != null) {
        mask |= wasm.CACHE_WRITE_OPTIONS_MASK_STALE_WHILE_REVALIDATE_NS;
    }
    if (options.surrogate_keys != null) {
        mask |= wasm.CACHE_WRITE_OPTIONS_MASK_SURROGATE_KEYS;
    }
    if (options.length != null) {
        mask |= wasm.CACHE_WRITE_OPTIONS_MASK_LENGTH;
    }
    if (options.user_metadata != null) {
        mask |= wasm.CACHE_WRITE_OPTIONS_MASK_USER_METADATA;
    }
    if (options.sensitive_data) {
        mask |= wasm.CACHE_WRITE_OPTIONS_MASK_SENSITIVE_DATA;
    }
    if (options.vary_rule != null) {
        mask |= wasm.CACHE_WRITE_OPTIONS_MASK_VARY_RULE;
    }
    if (options.edge_max_age_ns != null) {
        mask |= wasm.CACHE_WRITE_OPTIONS_MASK_EDGE_MAX_AGE_NS;
    }

    return mask;
}

fn buildLookupOptions(options: LookupOptions) wasm.CacheLookupOptions {
    return wasm.CacheLookupOptions{
        .request_headers = options.request_headers orelse 0,
        .service_id = null,
        .service_id_len = 0,
    };
}

fn buildLookupOptionsMask(options: LookupOptions) wasm.CacheLookupOptionsMask {
    var mask: wasm.CacheLookupOptionsMask = 0;
    if (options.request_headers != null) {
        mask |= wasm.CACHE_LOOKUP_OPTIONS_MASK_REQUEST_HEADERS;
    }
    return mask;
}

pub fn lookup(key: []const u8, options: LookupOptions) !CacheEntry {
    var cache_handle: wasm.CacheHandle = undefined;
    var opts = buildLookupOptions(options);
    const mask = buildLookupOptionsMask(options);

    try fastly(wasm.FastlyCache.lookup(key.ptr, key.len, mask, &opts, &cache_handle));
    return CacheEntry{ .handle = cache_handle };
}

pub fn insert(key: []const u8, options: WriteOptions) !Body {
    var body_handle: wasm.BodyHandle = undefined;
    var opts = buildWriteOptions(options);
    const mask = buildWriteOptionsMask(options);

    try fastly(wasm.FastlyCache.insert(key.ptr, key.len, mask, &opts, &body_handle));
    return Body{ .handle = body_handle };
}

pub fn transactionLookup(key: []const u8, options: LookupOptions) !Transaction {
    var cache_handle: wasm.CacheHandle = undefined;
    var opts = buildLookupOptions(options);
    const mask = buildLookupOptionsMask(options);

    try fastly(wasm.FastlyCache.transaction_lookup(key.ptr, key.len, mask, &opts, &cache_handle));
    return Transaction{ .handle = cache_handle };
}

pub fn transactionLookupAsync(key: []const u8, options: LookupOptions) !BusyHandle {
    var busy_handle: wasm.CacheBusyHandle = undefined;
    var opts = buildLookupOptions(options);
    const mask = buildLookupOptionsMask(options);

    try fastly(wasm.FastlyCache.transaction_lookup_async(key.ptr, key.len, mask, &opts, &busy_handle));
    return BusyHandle{ .handle = busy_handle };
}

pub const ReplaceOptions = struct {
    request_headers: ?wasm.RequestHandle = null,
};

pub fn replace(key: []const u8, options: ReplaceOptions) !ReplaceHandle {
    var replace_handle: wasm.CacheReplaceHandle = undefined;
    var mask: wasm.CacheReplaceOptionsMask = 0;
    var opts = wasm.CacheReplaceOptions{
        .request_headers = options.request_headers orelse 0,
        .replace_strategy = 0,
        .service_id = undefined,
        .service_id_len = 0,
    };

    if (options.request_headers != null) {
        mask |= wasm.CACHE_REPLACE_OPTIONS_MASK_REQUEST_HEADERS;
    }

    try fastly(wasm.FastlyCache.replace(key.ptr, key.len, mask, &opts, &replace_handle));
    return ReplaceHandle{ .handle = replace_handle };
}

pub const seconds_per_ns: u64 = 1_000_000_000;
pub const ms_per_ns: u64 = 1_000_000;

pub fn secondsToNs(seconds: u64) u64 {
    return seconds * seconds_per_ns;
}

pub fn msToNs(ms: u64) u64 {
    return ms * ms_per_ns;
}
