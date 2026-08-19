# KV Store Reference

The KV module provides access to Fastly's key-value storage. It uses the modern `fastly_kv_store` interface. Values can carry metadata, a time-to-live, and a generation number for optimistic concurrency.

## Store

### Opening a Store

```zig
pub fn open(name: []const u8) !Store
```

Open a KV store by name.

```zig
const kv = zigly.kv;

var store = try kv.Store.open("my_store");
```

### Methods

#### lookup

```zig
pub fn lookup(store: Store, key: []const u8, allocator: Allocator) !LookupResult
```

Look up a key. The result contains the value as an HTTP body, the optional metadata, and the generation number. The allocator is only used to copy the metadata.

```zig
var result = try store.lookup("my_key", allocator);
defer result.deinit(allocator);

const value = try result.body.readAll(allocator, 0);
if (result.metadata) |metadata| {
    // Use the metadata
}
```

Returns `error.NotFound` if the key doesn't exist.

#### getAll

```zig
pub fn getAll(store: Store, key: []const u8, allocator: Allocator, max_length: usize) ![]u8
```

Get the entire value as newly allocated bytes. Metadata and generation are discarded. Pass 0 for `max_length` for no limit.

```zig
const value = try store.getAll("my_key", allocator, 0);
defer allocator.free(value);
```

#### insert

```zig
pub fn insert(store: Store, key: []const u8, value: []const u8, options: InsertOptions) !void
```

Insert or update a value. The call waits until the store confirms the write.

```zig
try store.insert("my_key", "my_value", .{});
```

Options:

```zig
pub const InsertOptions = struct {
    mode: InsertMode = .overwrite,
    metadata: ?[]const u8 = null,
    time_to_live_sec: ?u32 = null,
    if_generation_match: ?u64 = null,
    background_fetch: bool = false,
};
```

The mode controls what happens when the key already exists:

- `.overwrite` replaces the value. This is the default.
- `.add` fails with `error.PreconditionFailed` if the key exists.
- `.append` adds the new bytes after the current value.
- `.prepend` adds the new bytes before the current value.

```zig
// Store a value with metadata and a one hour expiration
try store.insert("session", token, .{
    .metadata = "created-by=edge",
    .time_to_live_sec = 3600,
});

// Only update if nobody changed the value in the meantime
var result = try store.lookup("counter", allocator);
defer result.deinit(allocator);
try store.insert("counter", new_value, .{
    .if_generation_match = result.generation,
});
```

#### delete

```zig
pub fn delete(store: Store, key: []const u8) !void
```

Delete a key. Returns `error.NotFound` if the key doesn't exist.

```zig
try store.delete("my_key");
```

#### list

```zig
pub fn list(store: Store, allocator: Allocator, options: ListOptions, max_length: usize) ![]u8
```

List keys. The result is a JSON document with the matching keys and a cursor for pagination.

```zig
const listing = try store.list(allocator, .{ .prefix = "session_" }, 0);
defer allocator.free(listing);
```

Options:

```zig
pub const ListOptions = struct {
    cursor: ?[]const u8 = null,
    limit: ?u32 = null,
    prefix: ?[]const u8 = null,
    eventual_consistency: bool = false,
};
```

`listAsHttpBody` returns the same document as an HTTP body instead, for streaming reads.

### Errors

Store operations can fail with a `KvError` reported by the platform:

```zig
pub const KvError = error{
    Uninitialized,
    BadRequest,
    NotFound,
    PreconditionFailed,
    PayloadTooLarge,
    Internal,
    TooManyRequests,
};
```

Transport-level failures surface as `FastlyError` instead.

---

## Example Usage

### Read and Write

```zig
const std = @import("std");
const zigly = @import("zigly");
const kv = zigly.kv;

fn start() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.wasm_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var downstream = try zigly.downstream();

    var store = try kv.Store.open("config");

    // Read a value, with a default when the key is missing
    const api_url = store.getAll("api_url", allocator, 0) catch |err| switch (err) {
        error.NotFound => "https://api.example.com",
        else => return err,
    };
    _ = api_url;

    // Write a value
    try store.insert("last_request", "timestamp", .{});

    try downstream.response.setStatus(200);
    try downstream.response.finish();
}
```

### Streaming Large Values

```zig
fn streamLargeValue(store: kv.Store, key: []const u8, allocator: std.mem.Allocator) !void {
    var result = try store.lookup(key, allocator);
    defer result.deinit(allocator);
    defer result.body.close() catch {};

    var buf: [8192]u8 = undefined;
    while (true) {
        const chunk = try result.body.read(&buf);
        if (chunk.len == 0) break;
        // Process chunk
    }
}
```

### Check if Key Exists

```zig
fn keyExists(store: kv.Store, key: []const u8, allocator: std.mem.Allocator) bool {
    var result = store.lookup(key, allocator) catch return false;
    result.deinit(allocator);
    result.body.close() catch {};
    return true;
}
```

---

## Local Testing Configuration

Configure KV stores in `fastly.toml`:

```toml
[local_server.object_stores]
  [local_server.object_stores.my_store]
    [local_server.object_stores.my_store.key1]
    data = "inline value"

    [local_server.object_stores.my_store.key2]
    file = "data/large_value.txt"
```
