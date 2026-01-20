# Cache Reference

The cache module provides simple and transactional caching APIs.

## Module Functions

### lookup

```zig
pub fn lookup(key: []const u8, options: LookupOptions) !CacheEntry
```

Look up an entry in the cache.

```zig
const cache = zigly.cache;

var entry = try cache.lookup("my-key", .{});
defer entry.close() catch {};

const state = try entry.getState();
if (state.isUsable()) {
    var body = try entry.getBody(null);
    // Read cached data
}
```

### insert

```zig
pub fn insert(key: []const u8, options: WriteOptions) !Body
```

Insert a new cache entry. Returns a body to write content to.

```zig
var body = try cache.insert("my-key", .{
    .max_age_ns = cache.secondsToNs(3600),
});
try body.writeAll("cached content");
try body.close();
```

### transactionLookup

```zig
pub fn transactionLookup(key: []const u8, options: LookupOptions) !Transaction
```

Transactional cache lookup. Prevents cache stampedes by allowing only one request to populate a missing entry.

```zig
var tx = try cache.transactionLookup("my-key", .{});
defer tx.close() catch {};

const state = try tx.getState();
if (state.mustInsertOrUpdate()) {
    // We're responsible for populating the cache
    var result = try tx.insert(.{ .max_age_ns = cache.secondsToNs(300) });
    try result.body.writeAll("new data");
    try result.body.close();
}
```

### transactionLookupAsync

```zig
pub fn transactionLookupAsync(key: []const u8, options: LookupOptions) !BusyHandle
```

Async transactional lookup. Returns immediately with a handle to wait on.

```zig
var busy = try cache.transactionLookupAsync("key", .{});
// Do other work...
var tx = try busy.wait();
```

### replace

```zig
pub fn replace(key: []const u8, options: ReplaceOptions) !ReplaceHandle
```

Atomically replace a cache entry.

```zig
var handle = try cache.replace("key", .{});
var body = try handle.insert(.{ .max_age_ns = cache.secondsToNs(300) });
try body.writeAll("new content");
try body.close();
```

---

## Time Helpers

### secondsToNs

```zig
pub fn secondsToNs(seconds: u64) u64
```

Convert seconds to nanoseconds.

```zig
const ttl = cache.secondsToNs(3600);  // 1 hour in nanoseconds
```

### msToNs

```zig
pub fn msToNs(ms: u64) u64
```

Convert milliseconds to nanoseconds.

```zig
const delay = cache.msToNs(500);  // 500ms in nanoseconds
```

### Constants

```zig
pub const seconds_per_ns: u64 = 1_000_000_000;
pub const ms_per_ns: u64 = 1_000_000;
```

---

## WriteOptions

Configuration for cache writes.

```zig
pub const WriteOptions = struct {
    max_age_ns: u64 = 0,                    // Required: TTL
    initial_age_ns: ?u64 = null,            // Initial age of the entry
    stale_while_revalidate_ns: ?u64 = null, // Serve stale period
    surrogate_keys: ?[]const u8 = null,     // Space-separated keys for purging
    length: ?u64 = null,                    // Known content length
    user_metadata: ?[]const u8 = null,      // Custom metadata
    sensitive_data: bool = false,           // PCI compliance flag
    vary_rule: ?[]const u8 = null,          // Vary rule
    edge_max_age_ns: ?u64 = null,           // Edge-only TTL
};
```

### Example

```zig
var body = try cache.insert("key", .{
    .max_age_ns = cache.secondsToNs(300),
    .stale_while_revalidate_ns = cache.secondsToNs(60),
    .surrogate_keys = "product-123 category-electronics",
    .user_metadata = "version=2",
});
```

---

## LookupOptions

Configuration for cache lookups.

```zig
pub const LookupOptions = struct {
    request_headers: ?wasm.RequestHandle = null,
};
```

Typically used with default values:

```zig
var entry = try cache.lookup("key", .{});
```

---

## LookupState

State of a cache entry.

### Methods

#### isFound

```zig
pub fn isFound(self: LookupState) bool
```

Entry exists in cache (may be stale).

#### isUsable

```zig
pub fn isUsable(self: LookupState) bool
```

Entry can be served to clients.

#### isStale

```zig
pub fn isStale(self: LookupState) bool
```

Entry is past its TTL but within stale-while-revalidate window.

#### mustInsertOrUpdate

```zig
pub fn mustInsertOrUpdate(self: LookupState) bool
```

For transactions: this request must populate the cache.

### Example

```zig
const state = try entry.getState();

if (!state.isFound()) {
    // Not in cache
} else if (state.isStale()) {
    // Stale but usable, consider revalidating
} else if (state.isUsable()) {
    // Fresh cache hit
}
```

---

## CacheEntry

A cache entry from a non-transactional lookup.

### Methods

#### getState

```zig
pub fn getState(self: CacheEntry) !LookupState
```

Get the entry state.

#### getBody

```zig
pub fn getBody(self: CacheEntry, range: ?BodyRange) !Body
```

Get the entry body. Pass `null` for full content or a `BodyRange` for partial.

```zig
// Full content
var body = try entry.getBody(null);

// Partial content (bytes 0-99)
var partial = try entry.getBody(.{ .from = 0, .to = 100 });
```

#### getUserMetadata

```zig
pub fn getUserMetadata(self: CacheEntry, allocator: Allocator) ![]u8
```

Get custom metadata stored with the entry.

#### getLength

```zig
pub fn getLength(self: CacheEntry) !u64
```

Get content length in bytes.

#### getMaxAgeNs

```zig
pub fn getMaxAgeNs(self: CacheEntry) !u64
```

Get the TTL in nanoseconds.

#### getStaleWhileRevalidateNs

```zig
pub fn getStaleWhileRevalidateNs(self: CacheEntry) !u64
```

Get the stale-while-revalidate period.

#### getAgeNs

```zig
pub fn getAgeNs(self: CacheEntry) !u64
```

Get the current age of the entry.

#### getHits

```zig
pub fn getHits(self: CacheEntry) !u64
```

Get the number of times this entry has been served.

#### close

```zig
pub fn close(self: *CacheEntry) !void
```

Close the cache entry.

---

## Transaction

A transactional cache handle for request-collapsing.

### Methods

All `CacheEntry` methods, plus:

#### insert

```zig
pub fn insert(self: *Transaction, options: WriteOptions) !InsertResult
```

Insert content into the cache.

```zig
var result = try tx.insert(.{
    .max_age_ns = cache.secondsToNs(300),
});
try result.body.writeAll("cached content");
try result.body.close();
```

Returns `InsertResult` with a `body` field.

#### insertAndStreamBack

```zig
pub fn insertAndStreamBack(self: *Transaction, options: WriteOptions) !InsertAndStreamBackResult
```

Insert and get a readable handle to the inserted content.

```zig
var result = try tx.insertAndStreamBack(.{
    .max_age_ns = cache.secondsToNs(300),
});
try result.body.writeAll("content");
try result.body.close();

// Read back what we just inserted
var cached = try result.entry.getBody(null);
const data = try cached.readAll(allocator, 0);
```

Returns `InsertAndStreamBackResult` with `body` and `entry` fields.

#### update

```zig
pub fn update(self: *Transaction, options: WriteOptions) !void
```

Update metadata without changing the body.

```zig
try tx.update(.{
    .max_age_ns = cache.secondsToNs(600),  // Extend TTL
});
```

#### cancel

```zig
pub fn cancel(self: *Transaction) !void
```

Cancel the transaction without inserting.

---

## BusyHandle

Handle for async cache lookups.

### Methods

#### wait

```zig
pub fn wait(self: *BusyHandle) !Transaction
```

Wait for the lookup to complete.

#### close

```zig
pub fn close(self: *BusyHandle) !void
```

Close without waiting.

---

## ReplaceHandle

Handle for atomic cache replacement.

### Methods

All `CacheEntry` methods for reading the existing entry, plus:

#### insert

```zig
pub fn insert(self: *ReplaceHandle, options: WriteOptions) !Body
```

Insert the replacement content.

---

## BodyRange

Range for partial content reads.

```zig
pub const BodyRange = struct {
    from: u64 = 0,
    to: u64 = 0,
};
```

### Example

```zig
// Read bytes 1000-1999
var body = try entry.getBody(.{ .from = 1000, .to = 2000 });
```

---

## ReplaceOptions

Options for cache replacement.

```zig
pub const ReplaceOptions = struct {
    request_headers: ?wasm.RequestHandle = null,
};
```
