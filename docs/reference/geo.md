# Geo Reference

The geo module provides IP-based geolocation.

## lookup

```zig
pub fn lookup(allocator: Allocator, ip: Ip, buf: []u8) !std.json.Parsed(Location)
```

Look up location information for an IP address.

```zig
const geo = zigly.geo;

const client_ip = try zigly.http.Downstream.getClientIpAddr();

var buf: [4096]u8 = undefined;
const result = try geo.lookup(allocator, client_ip, &buf);
defer result.deinit();

const location = result.value;
std.debug.print("Country: {s}, City: {s}\n", .{
    location.country_code,
    location.city,
});
```

**Parameters:**
- `allocator` - Allocator for parsing the JSON response
- `ip` - IP address to look up
- `buf` - Buffer for the raw JSON response (4096 bytes recommended)

**Returns:** Parsed location data. Call `result.deinit()` when done.

---

## Ip

IP address union type.

```zig
pub const Ip = union(enum) {
    ip4: [4]u8,
    ip16: [16]u8,
};
```

### Methods

#### print

```zig
pub fn print(self: Ip, alloc: Allocator) ![]const u8
```

Format the IP address as a string.

```zig
const ip = try zigly.http.Downstream.getClientIpAddr();
const ip_str = try ip.print(allocator);
defer allocator.free(ip_str);
// "192.168.1.1" or "2001:0db8:..."
```

---

## Location

Geolocation data returned by `lookup`.

```zig
const Location = struct {
    area_code: usize,          // Telephone area code
    as_name: []const u8,       // ISP/AS name ("Comcast", "AWS")
    as_number: usize,          // Autonomous System Number
    city: []const u8,          // City name
    conn_speed: []const u8,    // "broadband", "mobile", "dialup"
    conn_type: []const u8,     // "wired", "wifi", "cellular"
    continent: []const u8,     // "NA", "EU", "AS", "AF", "OC", "SA", "AN"
    country_code: []const u8,  // ISO 3166-1 alpha-2 ("US", "DE", "JP")
    country_code3: []const u8, // ISO 3166-1 alpha-3 ("USA", "DEU", "JPN")
    country_name: []const u8,  // Full country name
    latitude: f32,             // Latitude
    longitude: f32,            // Longitude
    metro_code: isize,         // Metro/DMA code
    postal_code: []const u8,   // Postal/ZIP code
    proxy_description: []const u8,
    proxy_type: []const u8,    // Proxy type if detected
    region: []const u8,        // State/province code ("CA", "TX")
    utc_offset: isize,         // UTC offset in HHMM format
};
```

---

## Example Usage

### Country-Based Routing

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

    if (std.mem.eql(u8, country, "US")) {
        try downstream.proxy("us_backend", "us.example.com");
    } else if (std.mem.eql(u8, country, "DE")) {
        try downstream.proxy("eu_backend", "eu.example.com");
    } else {
        try downstream.proxy("default", "www.example.com");
    }
}
```

### Add Geo Headers

```zig
fn start() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var downstream = try zigly.downstream();
    const client_ip = try zigly.http.Downstream.getClientIpAddr();

    var buf: [4096]u8 = undefined;
    if (geo.lookup(allocator, client_ip, &buf)) |result| {
        const loc = result.value;
        try downstream.request.headers.set("X-Geo-Country", loc.country_code);
        try downstream.request.headers.set("X-Geo-City", loc.city);
        try downstream.request.headers.set("X-Geo-Region", loc.region);
    } else |_| {}

    try downstream.proxy("origin", null);
}
```

---

## Local Testing Configuration

Configure mock geolocation data for local testing in `fastly.toml`:

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
    conn_speed = "broadband"
    conn_type = "wired"
    continent = "NA"
```

Test with different IPs using the `Fastly-Client-IP` header:

```bash
curl -H "Fastly-Client-IP: 127.0.0.1" http://localhost:7878/
```

---

## Related

- [Geo Routing Guide](../guides/geo-routing.md) - Practical routing patterns
- [Geo Redirect Example](../examples/geo-redirect.md) - Country-based redirects
