# URL Rewriter

Rewrites and transforms request URLs before proxying. Demonstrates `getUri()`, `getPathAndQuery()`, and `setUriString()` for URL manipulation including path rewriting, prefix stripping, and trailing slash normalization.

## Source Code

```zig
const std = @import("std");
const zigly = @import("zigly");

pub fn main() !void {
    var downstream = try zigly.downstream();

    var uri_buf: [4096]u8 = undefined;
    var out_buf: [4096]u8 = undefined;

    // Get full parsed URI to access individual components
    const uri = try downstream.request.getUri(&uri_buf);
    const path = switch (uri.path) {
        .raw => |raw| raw,
        .percent_encoded => |encoded| encoded,
    };

    // Example 1: Rewrite legacy paths to new API structure
    // /v1/users/123 -> /api/v1/users/123
    if (std.mem.startsWith(u8, path, "/v1/") or std.mem.startsWith(u8, path, "/v2/")) {
        // Get path with query string preserved
        const path_and_query = try downstream.request.getPathAndQuery(&uri_buf, &out_buf);

        // Build new URI with /api prefix
        var new_uri_buf: [4096]u8 = undefined;
        const new_uri = try std.fmt.bufPrint(&new_uri_buf, "/api{s}", .{path_and_query});

        // Update the request URI
        try downstream.request.setUriString(new_uri);
        try downstream.proxy("api_backend", null);
        return;
    }

    // Example 2: Strip /old/ prefix from legacy URLs
    if (std.mem.startsWith(u8, path, "/old/")) {
        const path_and_query = try downstream.request.getPathAndQuery(&uri_buf, &out_buf);

        // Remove /old prefix, keep the rest including query string
        const new_path = path_and_query[4..]; // Skip "/old"
        try downstream.request.setUriString(new_path);
        try downstream.proxy("origin", null);
        return;
    }

    // Example 3: Add trailing slash to directory paths (no extension, no query)
    if (!std.mem.endsWith(u8, path, "/") and
        std.mem.lastIndexOfScalar(u8, path, '.') == null and
        uri.query == null)
    {
        var new_path_buf: [4096]u8 = undefined;
        const new_path = try std.fmt.bufPrint(&new_path_buf, "{s}/", .{path});
        try downstream.request.setUriString(new_path);
    }

    try downstream.proxy("origin", null);
}
```

## How It Works

1. Use `getUri()` to parse the request URI into components (scheme, host, path, query, port)
2. Use `getPathAndQuery()` when you need to preserve query strings during rewrites
3. Use `setUriString()` to modify the request URI before proxying
4. Route to appropriate backends based on the original or rewritten path

The URI helpers handle percent-encoding automatically and work with Fastly's full URI format (`http://host:port/path?query`).

## Backend Configuration

```toml
[local_server.backends.origin]
url = "https://www.example.com"

[local_server.backends.api_backend]
url = "https://api.example.com"
```

## Testing

```bash
# Rewrite /v1/ to /api/v1/
curl http://127.0.0.1:7676/v1/users/123
# Becomes: /api/v1/users/123

# Preserve query string during rewrite
curl "http://127.0.0.1:7676/v2/data?id=456&format=json"
# Becomes: /api/v2/data?id=456&format=json

# Strip /old/ prefix
curl http://127.0.0.1:7676/old/products
# Becomes: /products

# Add trailing slash to directory paths
curl http://127.0.0.1:7676/about
# Becomes: /about/

# File paths unchanged (have extension)
curl http://127.0.0.1:7676/style.css
# Stays: /style.css

# Paths with query unchanged (already have query)
curl "http://127.0.0.1:7676/search?q=test"
# Stays: /search?q=test
```

## Variations

**Version prefix rewriting:**
```zig
// /api/v1/* -> /v1/* (strip /api prefix for legacy backend)
if (std.mem.startsWith(u8, path, "/api/")) {
    const new_path = path[4..]; // Remove "/api"
    try downstream.request.setUriString(new_path);
}
```

**Language prefix routing:**
```zig
const languages = [_][]const u8{ "/en/", "/de/", "/fr/", "/es/" };
for (languages) |lang| {
    if (std.mem.startsWith(u8, path, lang)) {
        // Extract language code and strip from path
        const lang_code = lang[1..3];
        try downstream.request.headers.set("Accept-Language", lang_code);

        const new_path = path[3..]; // Remove language prefix
        try downstream.request.setUriString(new_path);
        break;
    }
}
```

**Vanity URL mapping:**
```zig
const vanity_urls = .{
    .{ "/blog", "/articles/index.html" },
    .{ "/contact", "/pages/contact-us.html" },
    .{ "/pricing", "/products/pricing.html" },
};

inline for (vanity_urls) |mapping| {
    if (std.mem.eql(u8, path, mapping[0])) {
        try downstream.request.setUriString(mapping[1]);
        break;
    }
}
```

**Query string manipulation:**
```zig
var uri_buf: [4096]u8 = undefined;
const uri = try downstream.request.getUri(&uri_buf);

// Add default query parameters
var new_uri_buf: [4096]u8 = undefined;
const new_uri = if (uri.query) |q|
    try std.fmt.bufPrint(&new_uri_buf, "{s}?{s}&source=edge", .{
        switch (uri.path) { .raw => |r| r, .percent_encoded => |e| e },
        switch (q) { .raw => |r| r, .percent_encoded => |e| e },
    })
else
    try std.fmt.bufPrint(&new_uri_buf, "{s}?source=edge", .{
        switch (uri.path) { .raw => |r| r, .percent_encoded => |e| e },
    });

try downstream.request.setUriString(new_uri);
```

**Protocol-based routing:**
```zig
var uri_buf: [4096]u8 = undefined;
const uri = try downstream.request.getUri(&uri_buf);

// Redirect HTTP to HTTPS
if (std.mem.eql(u8, uri.scheme, "http")) {
    var redirect_buf: [4096]u8 = undefined;
    const path_str = switch (uri.path) {
        .raw => |r| r,
        .percent_encoded => |e| e,
    };
    const https_url = try std.fmt.bufPrint(&redirect_buf, "https://example.com{s}", .{path_str});
    try downstream.redirect(301, https_url);
    return;
}
```

## Related

- [HTTP Reference](../reference/http.md) - URI helper documentation
- [API Gateway Example](api-gateway.md) - Path-based routing
- [Query Router Example](query-router.md) - Query parameter handling
