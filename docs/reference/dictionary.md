# Dictionary Reference

The Dictionary module provides access to Fastly Edge Dictionaries (read-only key-value configuration).

## Dictionary

### Opening a Dictionary

```zig
pub fn open(name: []const u8) !Dictionary
```

Open an edge dictionary by name.

```zig
const Dictionary = zigly.Dictionary;

var config = try Dictionary.open("site_config");
```

### Methods

#### get

```zig
pub fn get(self: Dictionary, allocator: Allocator, name: []const u8) ![]const u8
```

Get a value by key.

```zig
const api_key = try config.get(allocator, "api_key");
```

Returns `FastlyError.FastlyNone` if the key doesn't exist.

---

## Example Usage

### Configuration Lookup

```zig
const std = @import("std");
const zigly = @import("zigly");
const Dictionary = zigly.Dictionary;

fn start() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var downstream = try zigly.downstream();

    var config = try Dictionary.open("site_config");

    // Get configuration values
    const backend_url = try config.get(allocator, "backend_url");
    const feature_flag = config.get(allocator, "feature_x_enabled") catch "false";

    // Use configuration
    if (std.mem.eql(u8, feature_flag, "true")) {
        // Feature X is enabled
    }

    try downstream.proxy("origin", null);
}
```

### Feature Flags

```zig
fn isFeatureEnabled(allocator: Allocator, feature: []const u8) bool {
    var features = Dictionary.open("feature_flags") catch return false;
    const value = features.get(allocator, feature) catch return false;
    return std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "1");
}

fn start() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var downstream = try zigly.downstream();

    if (isFeatureEnabled(allocator, "new_checkout")) {
        try downstream.proxy("new_backend", "new.example.com");
    } else {
        try downstream.proxy("legacy_backend", "old.example.com");
    }
}
```

### Default Values

```zig
fn getConfigValue(allocator: Allocator, key: []const u8, default: []const u8) []const u8 {
    var config = Dictionary.open("config") catch return default;
    return config.get(allocator, key) catch default;
}
```

---

## Local Testing Configuration

Configure dictionaries in `fastly.toml`:

```toml
[local_server.dictionaries]
  [local_server.dictionaries.site_config]
  format = "json"
  file = "config/site_config.json"

  [local_server.dictionaries.feature_flags]
  format = "json"
  file = "config/features.json"
```

Create `config/site_config.json`:

```json
{
  "api_key": "test-key-123",
  "backend_url": "https://api.example.com",
  "cache_ttl": "3600"
}
```

Create `config/features.json`:

```json
{
  "new_checkout": "true",
  "dark_mode": "false",
  "beta_api": "true"
}
```

---

## Notes

- Edge dictionaries are read-only at runtime
- Changes require a new service version deployment
- Maximum 1000 items per dictionary
- Maximum 8KB per item
- Use KV stores for larger or writable data
