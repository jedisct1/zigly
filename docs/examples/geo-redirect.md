# Geo Redirect

Redirects users to country-specific sites based on their IP geolocation. Useful for serving localized content or complying with regional regulations.

## Source Code

```zig
const std = @import("std");
const zigly = @import("zigly");
const geo = zigly.geo;

fn start() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var downstream = try zigly.downstream();

    // Get client IP and look up location
    const client_ip = try zigly.http.Downstream.getClientIpAddr();

    var buf: [4096]u8 = undefined;
    const result = geo.lookup(allocator, client_ip, &buf) catch {
        // If geo lookup fails, proceed to default
        try downstream.proxy("origin", null);
        return;
    };
    const country = result.value.country_code;

    // Get current path
    var uri_buf: [4096]u8 = undefined;
    const full_uri = try downstream.request.getUriString(&uri_buf);

    // Extract the path from the URI
    const path = blk: {
        if (std.mem.indexOf(u8, full_uri, "://")) |scheme_end| {
            const after_scheme = full_uri[scheme_end + 3 ..];
            if (std.mem.indexOfScalar(u8, after_scheme, '/')) |path_start| {
                break :blk after_scheme[path_start..];
            }
        }
        break :blk full_uri;
    };

    // Skip redirect for certain paths
    if (std.mem.startsWith(u8, path, "/api/") or
        std.mem.startsWith(u8, path, "/static/"))
    {
        try downstream.proxy("origin", null);
        return;
    }

    // Redirect based on country
    var redirect_buf: [256]u8 = undefined;
    if (std.mem.eql(u8, country, "DE") or
        std.mem.eql(u8, country, "AT") or
        std.mem.eql(u8, country, "CH"))
    {
        const redirect = try std.fmt.bufPrint(&redirect_buf, "https://de.example.com{s}", .{path});
        try downstream.redirect(302, redirect);
    } else if (std.mem.eql(u8, country, "FR") or
        std.mem.eql(u8, country, "BE"))
    {
        const redirect = try std.fmt.bufPrint(&redirect_buf, "https://fr.example.com{s}", .{path});
        try downstream.redirect(302, redirect);
    } else if (std.mem.eql(u8, country, "JP")) {
        const redirect = try std.fmt.bufPrint(&redirect_buf, "https://jp.example.com{s}", .{path});
        try downstream.redirect(302, redirect);
    } else {
        // Default: proxy to origin without redirect
        try downstream.proxy("origin", null);
    }
}

pub export fn _start() callconv(.c) void {
    start() catch |err| {
        std.debug.print("Error: {}\n", .{err});
    };
}
```

## How It Works

1. Get the client IP address
2. Look up geolocation data for that IP using `geo.lookup()`
3. Extract the country code from the result
4. Skip redirects for API and static asset paths
5. Redirect to the appropriate regional domain based on country
6. Fall back to the default origin for unmatched countries

The `downstream.redirect(302, url)` method sends an HTTP 302 redirect response.

## Geolocation Data

The `geo.lookup()` function returns rich location data:

```zig
const result = geo.lookup(allocator, ip, &buf) catch |err| {
    // Handle lookup failure
};

const data = result.value;
// Available fields:
// data.country_code  - "US", "DE", "JP", etc.
// data.country_name  - "United States", "Germany", etc.
// data.region        - State/province
// data.city          - City name
// data.postal_code   - ZIP/postal code
// data.latitude      - GPS latitude
// data.longitude     - GPS longitude
// data.utc_offset    - Timezone offset
// data.continent     - "NA", "EU", "AS", etc.
```

## Testing

With local emulators, localhost IPs won't have geolocation data unless configured, so the request falls through to the default origin. In production, real client IPs will have geolocation data.

```bash
curl -v http://127.0.0.1:7676/products
# Falls through to origin since localhost has no geo data

curl -v http://127.0.0.1:7676/api/data
# Skips redirect, proxies to origin
```

## Variations

**Continent-based routing:**
```zig
if (std.mem.eql(u8, data.continent, "EU")) {
    try downstream.proxy("eu_origin", null);
} else if (std.mem.eql(u8, data.continent, "AS")) {
    try downstream.proxy("asia_origin", null);
} else {
    try downstream.proxy("us_origin", null);
}
```

**City-level targeting:**
```zig
if (std.mem.eql(u8, data.city, "San Francisco")) {
    try downstream.response.headers.set("X-Promo", "sf-special");
}
```

**GDPR compliance:**
```zig
const eu_countries = [_][]const u8{ "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IE", "IT", "LV", "LT", "LU", "MT", "NL", "PL", "PT", "RO", "SK", "SI", "ES", "SE" };

for (eu_countries) |eu| {
    if (std.mem.eql(u8, country, eu)) {
        try downstream.response.headers.set("X-GDPR-Region", "true");
        break;
    }
}
```

**Cookie-based override:**
```zig
var cookie_buf: [256]u8 = undefined;
if (downstream.request.headers.get("Cookie", &cookie_buf)) |cookies| {
    if (std.mem.indexOf(u8, cookies, "region=us")) |_| {
        // User chose US region, respect their preference
        try downstream.proxy("us_origin", null);
        return;
    }
}
// Otherwise use geo-based routing
```

## Related

- [Geo Routing Guide](../guides/geo-routing.md)
- [Geo Reference](../reference/geo.md)
- [HTTP Reference](../reference/http.md)
