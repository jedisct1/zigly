# Device Detection

Detect client devices from User-Agent strings to serve optimized content.

## Quick Start

```zig
const std = @import("std");
const zigly = @import("zigly");
const device = zigly.device;

fn start() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var downstream = try zigly.downstream();

    // Get User-Agent
    const ua = try downstream.request.headers.get(allocator, "User-Agent");

    // Simple checks
    if (try device.isMobile(allocator, ua)) {
        try downstream.proxy("mobile_backend", "m.example.com");
    } else if (try device.isTablet(allocator, ua)) {
        try downstream.proxy("tablet_backend", "tablet.example.com");
    } else {
        try downstream.proxy("desktop_backend", "www.example.com");
    }
}
```

## Detection Functions

### Quick Checks

```zig
const device = zigly.device;

// Check device type
const is_mobile = try device.isMobile(allocator, user_agent);
const is_tablet = try device.isTablet(allocator, user_agent);
const is_desktop = try device.isDesktop(allocator, user_agent);
```

### Full Detection

Get complete device information:

```zig
var buf: [4096]u8 = undefined;
const result = try device.lookup(allocator, user_agent, &buf);
defer result.deinit();

const dev = result.value.device;

// Device properties
if (dev.name) |name| std.debug.print("Device: {s}\n", .{name});
if (dev.brand) |brand| std.debug.print("Brand: {s}\n", .{brand});
if (dev.model) |model| std.debug.print("Model: {s}\n", .{model});
if (dev.hwtype) |hwtype| std.debug.print("Type: {s}\n", .{hwtype});

// Device categories
if (dev.is_mobile) |m| std.debug.print("Mobile: {}\n", .{m});
if (dev.is_tablet) |t| std.debug.print("Tablet: {}\n", .{t});
if (dev.is_desktop) |d| std.debug.print("Desktop: {}\n", .{d});
if (dev.is_smarttv) |tv| std.debug.print("Smart TV: {}\n", .{tv});
if (dev.is_gameconsole) |g| std.debug.print("Game Console: {}\n", .{g});
if (dev.is_ereader) |e| std.debug.print("E-Reader: {}\n", .{e});
if (dev.is_mediaplayer) |mp| std.debug.print("Media Player: {}\n", .{mp});
if (dev.is_touchscreen) |ts| std.debug.print("Touchscreen: {}\n", .{ts});
```

### Raw JSON

Get the raw detection response:

```zig
var buf: [4096]u8 = undefined;
const json = try device.lookupRaw(user_agent, &buf);
// json contains the full Fastly device detection response
```

## Device Properties

The `Device` struct contains:

```zig
pub const Device = struct {
    name: ?[]const u8 = null,         // "iPhone", "Galaxy S21"
    brand: ?[]const u8 = null,        // "Apple", "Samsung"
    model: ?[]const u8 = null,        // Device model
    hwtype: ?[]const u8 = null,       // "Mobile Phone", "Tablet", "Desktop"
    is_mobile: ?bool = null,
    is_tablet: ?bool = null,
    is_desktop: ?bool = null,
    is_smarttv: ?bool = null,
    is_gameconsole: ?bool = null,
    is_ereader: ?bool = null,
    is_mediaplayer: ?bool = null,
    is_tvplayer: ?bool = null,
    is_touchscreen: ?bool = null,
};
```

## Patterns

### Mobile-First Routing

```zig
fn start() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var downstream = try zigly.downstream();
    const ua = downstream.request.headers.get(allocator, "User-Agent") catch "";

    // Check mobile first (most common)
    if (try device.isMobile(allocator, ua)) {
        // Serve mobile-optimized content
        try downstream.request.headers.set("X-Device-Type", "mobile");
        try downstream.proxy("origin", "m.example.com");
        return;
    }

    // Desktop fallback
    try downstream.request.headers.set("X-Device-Type", "desktop");
    try downstream.proxy("origin", "www.example.com");
}
```

### Responsive Redirects

```zig
fn start() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var downstream = try zigly.downstream();
    const ua = downstream.request.headers.get(allocator, "User-Agent") catch "";

    var uri_buf: [4096]u8 = undefined;
    const uri = try downstream.request.getUriString(&uri_buf);

    // Redirect mobile users to mobile site
    if (try device.isMobile(allocator, ua)) {
        if (!std.mem.startsWith(u8, uri, "https://m.")) {
            var redirect_buf: [4096]u8 = undefined;
            const redirect = try std.fmt.bufPrint(&redirect_buf, "https://m.example.com{s}", .{uri});
            try downstream.redirect(302, redirect);
            return;
        }
    }

    try downstream.proxy("origin", null);
}
```

### Device-Based Caching

```zig
fn start() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var downstream = try zigly.downstream();
    const ua = downstream.request.headers.get(allocator, "User-Agent") catch "";

    // Determine device class for cache key
    const device_class = if (try device.isMobile(allocator, ua))
        "mobile"
    else if (try device.isTablet(allocator, ua))
        "tablet"
    else
        "desktop";

    // Add to cache key via Vary header
    try downstream.request.headers.set("X-Device-Class", device_class);

    // Configure caching with surrogate key
    try downstream.request.setCachingPolicy(.{
        .ttl = 3600,
        .surrogate_key = device_class,
    });

    try downstream.proxy("origin", null);
}
```

### Image Optimization

Serve different image sizes based on device:

```zig
fn start() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var downstream = try zigly.downstream();

    var uri_buf: [4096]u8 = undefined;
    const uri = try downstream.request.getUriString(&uri_buf);

    // Check if image request
    if (std.mem.endsWith(u8, uri, ".jpg") or
        std.mem.endsWith(u8, uri, ".png") or
        std.mem.endsWith(u8, uri, ".webp")) {

        const ua = downstream.request.headers.get(allocator, "User-Agent") catch "";

        const size = if (try device.isMobile(allocator, ua))
            "small"
        else if (try device.isTablet(allocator, ua))
            "medium"
        else
            "large";

        // Rewrite to sized image
        var new_uri_buf: [4096]u8 = undefined;
        const ext_start = std.mem.lastIndexOf(u8, uri, ".") orelse uri.len;
        const new_uri = try std.fmt.bufPrint(&new_uri_buf, "{s}-{s}{s}", .{
            uri[0..ext_start],
            size,
            uri[ext_start..],
        });

        try downstream.request.setUriString(new_uri);
    }

    try downstream.proxy("origin", null);
}
```

### Add Device Headers

Pass device info to origin:

```zig
fn start() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var downstream = try zigly.downstream();
    const ua = downstream.request.headers.get(allocator, "User-Agent") catch "";

    var buf: [4096]u8 = undefined;
    const result = device.lookup(allocator, ua, &buf) catch {
        try downstream.proxy("origin", null);
        return;
    };
    defer result.deinit();

    const dev = result.value.device;

    // Add device headers
    if (dev.brand) |brand| {
        try downstream.request.headers.set("X-Device-Brand", brand);
    }
    if (dev.name) |name| {
        try downstream.request.headers.set("X-Device-Name", name);
    }
    if (dev.is_touchscreen) |ts| {
        try downstream.request.headers.set("X-Device-Touch", if (ts) "true" else "false");
    }

    try downstream.proxy("origin", null);
}
```

### Bot Detection

Basic bot detection (for more robust detection, use dedicated services):

```zig
fn start() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var downstream = try zigly.downstream();
    const ua = downstream.request.headers.get(allocator, "User-Agent") catch "";

    var buf: [4096]u8 = undefined;
    const result = device.lookup(allocator, ua, &buf) catch {
        try downstream.proxy("origin", null);
        return;
    };
    defer result.deinit();

    const dev = result.value.device;

    // If no device type detected, might be a bot
    const is_likely_bot = dev.is_mobile == null and
                         dev.is_tablet == null and
                         dev.is_desktop == null;

    if (is_likely_bot) {
        try downstream.request.headers.set("X-Bot-Suspected", "true");
    }

    try downstream.proxy("origin", null);
}
```

## User-Agent Parsing

For basic UA parsing (browser family, version), use `UserAgent`:

```zig
const UserAgent = zigly.UserAgent;

var family_buf: [64]u8 = undefined;
var major_buf: [16]u8 = undefined;
var minor_buf: [16]u8 = undefined;
var patch_buf: [16]u8 = undefined;

const parsed = try UserAgent.parse(
    user_agent,
    &family_buf,
    &major_buf,
    &minor_buf,
    &patch_buf,
);

std.debug.print("Browser: {s} {s}.{s}.{s}\n", .{
    parsed.family,
    parsed.major,
    parsed.minor,
    parsed.patch,
});
```

## Testing

Device detection works locally. Send different User-Agent strings:

```bash
# Mobile
curl -H "User-Agent: Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X)" \
     http://localhost:7878/

# Desktop
curl -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/100.0" \
     http://localhost:7878/

# Tablet
curl -H "User-Agent: Mozilla/5.0 (iPad; CPU OS 15_0 like Mac OS X)" \
     http://localhost:7878/
```

## Next Steps

- [Device Reference](../reference/device.md) - Full API details
- [User Agent Reference](../reference/useragent.md) - UA parsing
