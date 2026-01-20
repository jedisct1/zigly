# Device Reference

The device module provides User-Agent-based device detection.

## Quick Checks

### isMobile

```zig
pub fn isMobile(allocator: Allocator, user_agent: []const u8) !bool
```

Check if the User-Agent represents a mobile device.

```zig
const device = zigly.device;

const ua = try request.headers.get(allocator, "User-Agent");
if (try device.isMobile(allocator, ua)) {
    // Mobile device
}
```

### isTablet

```zig
pub fn isTablet(allocator: Allocator, user_agent: []const u8) !bool
```

Check if the User-Agent represents a tablet.

### isDesktop

```zig
pub fn isDesktop(allocator: Allocator, user_agent: []const u8) !bool
```

Check if the User-Agent represents a desktop device.

---

## Full Detection

### lookup

```zig
pub fn lookup(
    allocator: Allocator,
    user_agent: []const u8,
    buf: []u8
) !std.json.Parsed(DetectionResult)
```

Get complete device information.

```zig
var buf: [4096]u8 = undefined;
const result = try device.lookup(allocator, user_agent, &buf);
defer result.deinit();

const dev = result.value.device;
if (dev.brand) |brand| {
    std.debug.print("Brand: {s}\n", .{brand});
}
```

### lookupRaw

```zig
pub fn lookupRaw(user_agent: []const u8, buf: []u8) ![]const u8
```

Get the raw JSON response from device detection.

```zig
var buf: [4096]u8 = undefined;
const json = try device.lookupRaw(user_agent, &buf);
// Parse or inspect json directly
```

---

## DetectionResult

The parsed detection result.

```zig
pub const DetectionResult = struct {
    device: Device = .{},
};
```

---

## Device

Device properties from detection.

```zig
pub const Device = struct {
    name: ?[]const u8 = null,         // "iPhone", "Galaxy S21"
    brand: ?[]const u8 = null,        // "Apple", "Samsung"
    model: ?[]const u8 = null,        // Device model
    hwtype: ?[]const u8 = null,       // "Mobile Phone", "Tablet", "Desktop"
    is_mobile: ?bool = null,          // Mobile phone
    is_tablet: ?bool = null,          // Tablet
    is_desktop: ?bool = null,         // Desktop/laptop
    is_smarttv: ?bool = null,         // Smart TV
    is_gameconsole: ?bool = null,     // Game console
    is_ereader: ?bool = null,         // E-reader
    is_mediaplayer: ?bool = null,     // Media player
    is_tvplayer: ?bool = null,        // TV player/set-top box
    is_touchscreen: ?bool = null,     // Has touchscreen
};
```

All fields are optional because detection may not identify all properties.

---

## Example Usage

### Device-Based Routing

```zig
const std = @import("std");
const zigly = @import("zigly");
const device = zigly.device;

fn start() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var downstream = try zigly.downstream();

    const ua = downstream.request.headers.get(allocator, "User-Agent") catch "";

    if (try device.isMobile(allocator, ua)) {
        try downstream.proxy("mobile_backend", "m.example.com");
    } else if (try device.isTablet(allocator, ua)) {
        try downstream.proxy("tablet_backend", "tablet.example.com");
    } else {
        try downstream.proxy("desktop_backend", "www.example.com");
    }
}
```

### Device Information Headers

```zig
fn start() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var downstream = try zigly.downstream();

    const ua = downstream.request.headers.get(allocator, "User-Agent") catch "";

    var buf: [4096]u8 = undefined;
    if (device.lookup(allocator, ua, &buf)) |result| {
        defer result.deinit();
        const dev = result.value.device;

        if (dev.brand) |brand| {
            try downstream.request.headers.set("X-Device-Brand", brand);
        }
        if (dev.name) |name| {
            try downstream.request.headers.set("X-Device-Name", name);
        }
        if (dev.is_touchscreen) |ts| {
            try downstream.request.headers.set("X-Has-Touch", if (ts) "true" else "false");
        }
    } else |_| {}

    try downstream.proxy("origin", null);
}
```

### Cache Key Based on Device

```zig
fn start() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var downstream = try zigly.downstream();

    const ua = downstream.request.headers.get(allocator, "User-Agent") catch "";

    const device_class = if (try device.isMobile(allocator, ua))
        "mobile"
    else if (try device.isTablet(allocator, ua))
        "tablet"
    else
        "desktop";

    // Add to Vary for proper caching
    try downstream.request.headers.set("X-Device-Class", device_class);

    try downstream.proxy("origin", null);
}
```

---

## Testing

Device detection works locally. Test with different User-Agent strings:

```bash
# iPhone
curl -H "User-Agent: Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15" \
     http://localhost:7878/

# Android
curl -H "User-Agent: Mozilla/5.0 (Linux; Android 12; Pixel 6) AppleWebKit/537.36 Chrome/100.0" \
     http://localhost:7878/

# iPad
curl -H "User-Agent: Mozilla/5.0 (iPad; CPU OS 15_0 like Mac OS X) AppleWebKit/605.1.15" \
     http://localhost:7878/

# Desktop Chrome
curl -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/100.0" \
     http://localhost:7878/
```
