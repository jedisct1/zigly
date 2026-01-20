# API Gateway

Routes requests to different backends based on the URL path prefix. Useful for microservices architectures where different services handle different parts of the API.

## Source Code

```zig
const std = @import("std");
const zigly = @import("zigly");

fn start() !void {
    var downstream = try zigly.downstream();

    // Get the request URI and extract the path
    var uri_buf: [4096]u8 = undefined;
    const full_uri = try downstream.request.getUriString(&uri_buf);

    // Extract the path from the URI (find path after scheme://host)
    const path = blk: {
        if (std.mem.indexOf(u8, full_uri, "://")) |scheme_end| {
            const after_scheme = full_uri[scheme_end + 3 ..];
            if (std.mem.indexOfScalar(u8, after_scheme, '/')) |path_start| {
                break :blk after_scheme[path_start..];
            }
        }
        break :blk full_uri;
    };

    // Route based on path prefix
    if (std.mem.startsWith(u8, path, "/api/users")) {
        try downstream.proxy("users_api", null);
    } else if (std.mem.startsWith(u8, path, "/api/products")) {
        try downstream.proxy("products_api", null);
    } else if (std.mem.startsWith(u8, path, "/static/")) {
        try downstream.proxy("cdn", null);
    } else {
        // Default: return 404
        try downstream.response.setStatus(404);
        try downstream.response.headers.set("Content-Type", "application/json");
        try downstream.response.body.writeAll("{\"error\":\"Not found\"}");
        try downstream.response.finish();
    }
}

pub export fn _start() callconv(.c) void {
    start() catch |err| {
        std.debug.print("Error: {}\n", .{err});
    };
}
```

## How It Works

1. Extract the full URI from the request using `getUriString()`
2. Parse out just the path component (the URI includes scheme and host)
3. Match the path against known prefixes
4. Route to the appropriate backend or return a 404 response

The path extraction handles the full URI format returned by Fastly's runtime: `http://host:port/path`.

## Backend Configuration

```toml
[local_server.backends.users_api]
url = "https://users.internal.example.com"

[local_server.backends.products_api]
url = "https://products.internal.example.com"

[local_server.backends.cdn]
url = "https://cdn.example.com"
```

## Testing

```bash
# Routes to users_api backend
curl http://127.0.0.1:7676/api/users/123

# Routes to products_api backend
curl http://127.0.0.1:7676/api/products/456

# Routes to cdn backend
curl http://127.0.0.1:7676/static/app.js

# Returns 404
curl http://127.0.0.1:7676/unknown
```

## Variations

**Path rewriting:**
```zig
// Strip /api/v2 prefix before proxying
if (std.mem.startsWith(u8, path, "/api/v2/")) {
    const new_path = path[7..]; // Remove "/api/v2"
    try downstream.request.setUri(new_path);
    try downstream.proxy("v2_backend", null);
}
```

**Header-based routing:**
```zig
var version_buf: [32]u8 = undefined;
if (downstream.request.headers.get("API-Version", &version_buf)) |version| {
    if (std.mem.eql(u8, version, "2")) {
        try downstream.proxy("v2_backend", null);
        return;
    }
}
try downstream.proxy("v1_backend", null);
```

**Method-based routing:**
```zig
var method_buf: [16]u8 = undefined;
const method = try downstream.request.getMethod(&method_buf);

if (std.mem.eql(u8, method, "GET")) {
    try downstream.proxy("read_replica", null);
} else {
    try downstream.proxy("primary", null);
}
```

## Related

- [Proxying Guide](../guides/proxying.md)
- [Backend Reference](../reference/backend.md)
- [HTTP Reference](../reference/http.md)
