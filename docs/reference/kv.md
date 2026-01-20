# KV Store Reference

The KV module provides access to Fastly's key-value storage.

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

#### getAsHttpBody

```zig
pub fn getAsHttpBody(store: *Store, key: []const u8) !Body
```

Get a value as an HTTP body for streaming reads.

```zig
var body = try store.getAsHttpBody("my_key");
var buf: [4096]u8 = undefined;
const data = try body.read(&buf);
```

Returns `FastlyError.FastlyNone` if the key doesn't exist.

#### getAll

```zig
pub fn getAll(store: *Store, key: []const u8, allocator: Allocator, max_length: usize) ![]u8
```

Get the entire value. Pass 0 for `max_length` for no limit.

```zig
const value = try store.getAll("my_key", allocator, 0);
defer allocator.free(value);
```

#### replace

```zig
pub fn replace(store: *Store, key: []const u8, value: []const u8) !void
```

Insert or replace a value.

```zig
try store.replace("my_key", "my_value");
```

#### close

```zig
pub fn close(_: *Store) !void
```

Close the store. (Currently a no-op as there's no close hostcall.)

---

## Example Usage

### Read and Write

```zig
const std = @import("std");
const zigly = @import("zigly");
const kv = zigly.kv;

fn start() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var downstream = try zigly.downstream();

    var store = try kv.Store.open("config");

    // Read a value
    const api_url = store.getAll("api_url", allocator, 0) catch |err| {
        if (err == zigly.FastlyError.FastlyNone) {
            // Key not found, use default
            return "https://api.example.com";
        }
        return err;
    };

    // Write a value
    try store.replace("last_request", "timestamp");

    try downstream.response.setStatus(200);
    try downstream.response.finish();
}
```

### Streaming Large Values

```zig
fn streamLargeValue(store: *kv.Store, key: []const u8) !void {
    var body = try store.getAsHttpBody(key);
    defer body.close() catch {};

    var buf: [8192]u8 = undefined;
    while (true) {
        const chunk = try body.read(&buf);
        if (chunk.len == 0) break;
        // Process chunk
    }
}
```

### Check if Key Exists

```zig
fn keyExists(store: *kv.Store, key: []const u8) bool {
    _ = store.getAsHttpBody(key) catch return false;
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
