# User Agent Reference

The UserAgent module provides User-Agent string parsing.

## UserAgent

### parse

```zig
pub fn parse(
    user_agent: []const u8,
    family: []u8,
    major: []u8,
    minor: []u8,
    patch: []u8,
) !ParseResult
```

Parse a User-Agent string to extract browser information.

```zig
const UserAgent = zigly.UserAgent;

var family_buf: [64]u8 = undefined;
var major_buf: [16]u8 = undefined;
var minor_buf: [16]u8 = undefined;
var patch_buf: [16]u8 = undefined;

const result = try UserAgent.parse(
    user_agent,
    &family_buf,
    &major_buf,
    &minor_buf,
    &patch_buf,
);

std.debug.print("Browser: {s} {s}.{s}.{s}\n", .{
    result.family,
    result.major,
    result.minor,
    result.patch,
});
```

---

## ParseResult

```zig
pub const ParseResult = struct {
    family: []u8,  // Browser family ("Chrome", "Firefox", "Safari")
    major: []u8,   // Major version
    minor: []u8,   // Minor version
    patch: []u8,   // Patch version
};
```

---

## Example Usage

### Browser Detection

```zig
const std = @import("std");
const zigly = @import("zigly");
const UserAgent = zigly.UserAgent;

fn start() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var downstream = try zigly.downstream();

    const ua = downstream.request.headers.get(allocator, "User-Agent") catch {
        try downstream.proxy("origin", null);
        return;
    };

    var family_buf: [64]u8 = undefined;
    var major_buf: [16]u8 = undefined;
    var minor_buf: [16]u8 = undefined;
    var patch_buf: [16]u8 = undefined;

    if (UserAgent.parse(ua, &family_buf, &major_buf, &minor_buf, &patch_buf)) |result| {
        // Add browser info to request
        try downstream.request.headers.set("X-Browser-Family", result.family);
        try downstream.request.headers.set("X-Browser-Version", result.major);
    } else |_| {}

    try downstream.proxy("origin", null);
}
```

### Legacy Browser Detection

```zig
fn isLegacyBrowser(ua: []const u8) bool {
    var family_buf: [64]u8 = undefined;
    var major_buf: [16]u8 = undefined;
    var minor_buf: [16]u8 = undefined;
    var patch_buf: [16]u8 = undefined;

    const result = UserAgent.parse(ua, &family_buf, &major_buf, &minor_buf, &patch_buf) catch return false;

    const major = std.fmt.parseInt(u32, result.major, 10) catch return false;

    // Check for old browsers
    if (std.mem.eql(u8, result.family, "IE")) {
        return major < 11;
    }
    if (std.mem.eql(u8, result.family, "Chrome")) {
        return major < 80;
    }
    if (std.mem.eql(u8, result.family, "Firefox")) {
        return major < 75;
    }
    if (std.mem.eql(u8, result.family, "Safari")) {
        return major < 13;
    }

    return false;
}

fn start() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var downstream = try zigly.downstream();

    const ua = downstream.request.headers.get(allocator, "User-Agent") catch "";

    if (isLegacyBrowser(ua)) {
        try downstream.redirect(302, "/legacy-browser-warning");
        return;
    }

    try downstream.proxy("origin", null);
}
```

### Browser-Specific Caching

```zig
fn start() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var downstream = try zigly.downstream();

    const ua = downstream.request.headers.get(allocator, "User-Agent") catch "";

    var family_buf: [64]u8 = undefined;
    var major_buf: [16]u8 = undefined;
    var minor_buf: [16]u8 = undefined;
    var patch_buf: [16]u8 = undefined;

    const browser_key = if (UserAgent.parse(ua, &family_buf, &major_buf, &minor_buf, &patch_buf)) |result|
        result.family
    else |_|
        "unknown";

    // Vary cache by browser family
    try downstream.request.headers.set("X-Browser-Family", browser_key);

    try downstream.proxy("origin", null);
}
```

---

## Notes

- User-Agent parsing is best-effort; not all UAs will be recognized
- For device type detection (mobile/tablet/desktop), use the [device module](device.md) instead
- Browser families include: Chrome, Firefox, Safari, Edge, IE, Opera, and others
- Version numbers may be empty strings if not detected
