# Query Router

Routes requests based on query parameters. Demonstrates `parseQueryParams()` for extracting and using URL parameters to control routing, headers, and backend selection.

## Source Code

```zig
const std = @import("std");
const zigly = @import("zigly");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var downstream = try zigly.downstream();

    // Parse query parameters from the request URI
    const params = try downstream.request.parseQueryParams(allocator);

    // Look for specific query parameters to determine routing
    var version: ?[]const u8 = null;
    var format: ?[]const u8 = null;
    var debug: bool = false;

    for (params) |param| {
        if (std.mem.eql(u8, param.key, "version") or std.mem.eql(u8, param.key, "v")) {
            version = param.value;
        } else if (std.mem.eql(u8, param.key, "format")) {
            format = param.value;
        } else if (std.mem.eql(u8, param.key, "debug")) {
            debug = std.mem.eql(u8, param.value, "true") or std.mem.eql(u8, param.value, "1");
        }
    }

    // Route to different API versions based on query param
    const backend = if (version) |v|
        if (std.mem.eql(u8, v, "2") or std.mem.startsWith(u8, v, "2."))
            "api_v2"
        else
            "api_v1"
    else
        "api_v1";

    // Add debug header if requested
    if (debug) {
        try downstream.request.headers.set("X-Debug-Mode", "true");
    }

    // Set response format preference header for the backend
    if (format) |f| {
        if (std.mem.eql(u8, f, "xml")) {
            try downstream.request.headers.set("Accept", "application/xml");
        } else if (std.mem.eql(u8, f, "csv")) {
            try downstream.request.headers.set("Accept", "text/csv");
        }
    }

    try downstream.proxy(backend, null);
}
```

## How It Works

1. Parse query parameters using `parseQueryParams()` - returns an array of key-value pairs
2. Iterate through parameters looking for specific keys (`version`, `format`, `debug`)
3. Route to different backends based on API version parameter
4. Set request headers based on format and debug parameters
5. Proxy to the selected backend

The `parseQueryParams()` function automatically handles URL decoding, including `+` to space conversion and percent-encoded characters.

## Backend Configuration

```toml
[local_server.backends.api_v1]
url = "https://api-v1.example.com"

[local_server.backends.api_v2]
url = "https://api-v2.example.com"
```

## Testing

```bash
# Default routing (api_v1)
curl http://127.0.0.1:7676/data

# Route to api_v2
curl http://127.0.0.1:7676/data?version=2

# Short version param
curl http://127.0.0.1:7676/data?v=2.1

# Request XML format
curl http://127.0.0.1:7676/data?format=xml

# Enable debug mode
curl http://127.0.0.1:7676/data?debug=true

# Combined parameters
curl "http://127.0.0.1:7676/data?v=2&format=xml&debug=1"
```

## Variations

**Pagination handling:**
```zig
var page: u32 = 1;
var per_page: u32 = 20;

for (params) |param| {
    if (std.mem.eql(u8, param.key, "page")) {
        page = std.fmt.parseInt(u32, param.value, 10) catch 1;
    } else if (std.mem.eql(u8, param.key, "per_page")) {
        per_page = @min(std.fmt.parseInt(u32, param.value, 10) catch 20, 100);
    }
}
```

**Feature flags:**
```zig
var features = std.StringHashMap(bool).init(allocator);
defer features.deinit();

for (params) |param| {
    if (std.mem.startsWith(u8, param.key, "feature_")) {
        const feature_name = param.key[8..];
        const enabled = std.mem.eql(u8, param.value, "true") or std.mem.eql(u8, param.value, "1");
        try features.put(feature_name, enabled);
    }
}

if (features.get("beta_ui")) |enabled| {
    if (enabled) {
        try downstream.proxy("beta_backend", null);
        return;
    }
}
```

**Search with multiple filters:**
```zig
var filters = std.ArrayList([]const u8).init(allocator);
defer filters.deinit();

for (params) |param| {
    if (std.mem.eql(u8, param.key, "filter")) {
        try filters.append(param.value);
    }
}

// Build filter header for backend
if (filters.items.len > 0) {
    const filter_header = try std.mem.join(allocator, ",", filters.items);
    try downstream.request.headers.set("X-Filters", filter_header);
}
```

**Callback/JSONP support:**
```zig
var callback: ?[]const u8 = null;

for (params) |param| {
    if (std.mem.eql(u8, param.key, "callback")) {
        callback = param.value;
        break;
    }
}

if (callback) |cb| {
    // Fetch from backend, wrap response in callback
    var resp = try downstream.request.send("api_backend");
    const body = try resp.body.readAll(allocator, 0);

    try downstream.response.setStatus(200);
    try downstream.response.headers.set("Content-Type", "application/javascript");
    try downstream.response.body.write(cb);
    try downstream.response.body.writeAll("(");
    try downstream.response.body.writeAll(body);
    try downstream.response.body.writeAll(");");
    try downstream.response.finish();
}
```

## Related

- [HTTP Reference](../reference/http.md) - `parseQueryParams()` documentation
- [API Gateway Example](api-gateway.md) - Path-based routing
- [URL Rewriter Example](url-rewriter.md) - URI manipulation
