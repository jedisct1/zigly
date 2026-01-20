# Geo Routing

Route requests based on client location using Fastly's geolocation database.

## Getting Client Location

Look up the client's IP address:

```zig
const std = @import("std");
const zigly = @import("zigly");
const geo = zigly.geo;

fn start() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var downstream = try zigly.downstream();

    // Get client IP
    const client_ip = try zigly.http.Downstream.getClientIpAddr();

    // Look up location
    var buf: [4096]u8 = undefined;
    const result = try geo.lookup(allocator, client_ip, &buf);
    const location = result.value;

    std.debug.print("Country: {s}, City: {s}\n", .{
        location.country_code,
        location.city,
    });

    try downstream.response.setStatus(200);
    try downstream.response.finish();
}
```

## Location Data

The `Location` struct contains:

```zig
const Location = struct {
    area_code: usize,
    as_name: []const u8,        // ISP name
    as_number: usize,           // ASN
    city: []const u8,
    conn_speed: []const u8,     // "broadband", "mobile", etc.
    conn_type: []const u8,      // "wired", "wifi", etc.
    continent: []const u8,      // "NA", "EU", etc.
    country_code: []const u8,   // "US", "DE", etc.
    country_code3: []const u8,  // "USA", "DEU", etc.
    country_name: []const u8,   // "United States", etc.
    latitude: f32,
    longitude: f32,
    metro_code: isize,
    postal_code: []const u8,
    proxy_description: []const u8,
    proxy_type: []const u8,
    region: []const u8,         // State/province code
    utc_offset: isize,          // Timezone offset
};
```

## Patterns

### Country-Based Routing

Route to region-specific backends:

```zig
fn start() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var downstream = try zigly.downstream();
    const client_ip = try zigly.http.Downstream.getClientIpAddr();

    var buf: [4096]u8 = undefined;
    const result = try geo.lookup(allocator, client_ip, &buf);
    const country = result.value.country_code;

    // Route to regional backend
    if (std.mem.eql(u8, country, "US") or std.mem.eql(u8, country, "CA")) {
        try downstream.proxy("us_backend", "api-us.example.com");
    } else if (std.mem.eql(u8, country, "DE") or
               std.mem.eql(u8, country, "FR") or
               std.mem.eql(u8, country, "GB")) {
        try downstream.proxy("eu_backend", "api-eu.example.com");
    } else {
        try downstream.proxy("default_backend", "api.example.com");
    }
}
```

### Country-Based Redirects

Redirect users to localized sites:

```zig
fn start() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var downstream = try zigly.downstream();
    const client_ip = try zigly.http.Downstream.getClientIpAddr();

    var buf: [4096]u8 = undefined;
    const result = try geo.lookup(allocator, client_ip, &buf);
    const country = result.value.country_code;

    // Get original path
    var uri_buf: [4096]u8 = undefined;
    const uri = try downstream.request.getUriString(&uri_buf);

    // Build redirect URL
    var redirect_buf: [4096]u8 = undefined;
    const redirect = try std.fmt.bufPrint(&redirect_buf, "https://{s}.example.com{s}", .{
        countryToSubdomain(country),
        uri,
    });

    try downstream.redirect(302, redirect);
}

fn countryToSubdomain(country: []const u8) []const u8 {
    if (std.mem.eql(u8, country, "DE")) return "de";
    if (std.mem.eql(u8, country, "FR")) return "fr";
    if (std.mem.eql(u8, country, "JP")) return "jp";
    return "www";
}
```

### Geo-Blocking

Block requests from certain regions:

```zig
fn start() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var downstream = try zigly.downstream();
    const client_ip = try zigly.http.Downstream.getClientIpAddr();

    var buf: [4096]u8 = undefined;
    const result = try geo.lookup(allocator, client_ip, &buf);
    const country = result.value.country_code;

    // Block certain countries
    const blocked = [_][]const u8{ "XX", "YY" };  // Example country codes
    for (blocked) |code| {
        if (std.mem.eql(u8, country, code)) {
            try downstream.response.setStatus(403);
            try downstream.response.body.writeAll("Service not available in your region");
            try downstream.response.finish();
            return;
        }
    }

    try downstream.proxy("origin", null);
}
```

### Continent-Based Routing

```zig
fn routeByContinent(downstream: *Downstream, continent: []const u8) !void {
    const backend = if (std.mem.eql(u8, continent, "NA"))
        "us_backend"
    else if (std.mem.eql(u8, continent, "EU"))
        "eu_backend"
    else if (std.mem.eql(u8, continent, "AS"))
        "asia_backend"
    else
        "default_backend";

    try downstream.proxy(backend, null);
}
```

### Distance-Based Selection

Select the closest server:

```zig
const ServerLocation = struct {
    name: []const u8,
    lat: f32,
    lon: f32,
};

const servers = [_]ServerLocation{
    .{ .name = "us_west", .lat = 37.7749, .lon = -122.4194 },   // San Francisco
    .{ .name = "us_east", .lat = 40.7128, .lon = -74.0060 },    // New York
    .{ .name = "eu_west", .lat = 51.5074, .lon = -0.1278 },     // London
    .{ .name = "asia", .lat = 35.6762, .lon = 139.6503 },       // Tokyo
};

fn findClosestServer(lat: f32, lon: f32) []const u8 {
    var min_distance: f32 = std.math.inf(f32);
    var closest: []const u8 = "default";

    for (servers) |server| {
        const d = haversineDistance(lat, lon, server.lat, server.lon);
        if (d < min_distance) {
            min_distance = d;
            closest = server.name;
        }
    }

    return closest;
}

fn haversineDistance(lat1: f32, lon1: f32, lat2: f32, lon2: f32) f32 {
    const R = 6371.0;  // Earth radius in km
    const dLat = (lat2 - lat1) * std.math.pi / 180.0;
    const dLon = (lon2 - lon1) * std.math.pi / 180.0;
    const a = std.math.sin(dLat / 2) * std.math.sin(dLat / 2) +
              std.math.cos(lat1 * std.math.pi / 180.0) *
              std.math.cos(lat2 * std.math.pi / 180.0) *
              std.math.sin(dLon / 2) * std.math.sin(dLon / 2);
    const c = 2 * std.math.atan2(@sqrt(a), @sqrt(1 - a));
    return R * c;
}
```

### Add Location Headers

Pass location information to the origin:

```zig
fn start() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var downstream = try zigly.downstream();
    const client_ip = try zigly.http.Downstream.getClientIpAddr();

    var buf: [4096]u8 = undefined;
    const result = try geo.lookup(allocator, client_ip, &buf);
    const loc = result.value;

    // Add geo headers for origin
    try downstream.request.headers.set("X-Geo-Country", loc.country_code);
    try downstream.request.headers.set("X-Geo-City", loc.city);
    try downstream.request.headers.set("X-Geo-Region", loc.region);

    try downstream.proxy("origin", null);
}
```

### Localized Content

Serve different content based on location:

```zig
fn start() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var downstream = try zigly.downstream();
    const client_ip = try zigly.http.Downstream.getClientIpAddr();

    var buf: [4096]u8 = undefined;
    const result = try geo.lookup(allocator, client_ip, &buf);
    const country = result.value.country_code;

    // Modify request path for localized content
    var uri_buf: [4096]u8 = undefined;
    const original_uri = try downstream.request.getUriString(&uri_buf);

    var new_uri_buf: [4096]u8 = undefined;
    const new_uri = try std.fmt.bufPrint(&new_uri_buf, "/{s}{s}", .{
        country,
        original_uri,
    });

    try downstream.request.setUriString(new_uri);
    try downstream.proxy("origin", null);
}
```

## IP Address Formatting

Convert IP addresses to strings:

```zig
const client_ip = try zigly.http.Downstream.getClientIpAddr();
const ip_str = try client_ip.print(allocator);
defer allocator.free(ip_str);

// ip_str is "192.168.1.1" or "2001:0db8:..."
```

## Local Testing

Configure mock geolocation data in `fastly.toml`:

```toml
[local_server.geolocation]
  [local_server.geolocation.addresses]
    [local_server.geolocation.addresses."127.0.0.1"]
    as_name = "Test ISP"
    city = "San Francisco"
    country_code = "US"
    country_code3 = "USA"
    country_name = "United States"
    region = "CA"
    latitude = 37.7749
    longitude = -122.4194
    utc_offset = -800

    [local_server.geolocation.addresses."::1"]
    country_code = "DE"
    city = "Berlin"
```

Test with different client IPs using the `Fastly-Client-IP` header:

```bash
curl -H "Fastly-Client-IP: 127.0.0.1" http://localhost:7878/
```

## Next Steps

- [Device Detection](device-detection.md) - Detect client devices
- [Geo Reference](../reference/geo.md) - Full API details
