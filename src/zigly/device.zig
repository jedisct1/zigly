const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

const wasm = @import("wasm.zig");
const errors = @import("errors.zig");
const fastly = errors.fastly;
const FastlyError = errors.FastlyError;

/// Device properties from device detection.
pub const Device = struct {
    /// Device name (e.g., "iPhone", "Galaxy S21").
    name: ?[]const u8 = null,
    /// Device brand (e.g., "Apple", "Samsung").
    brand: ?[]const u8 = null,
    /// Device model.
    model: ?[]const u8 = null,
    /// Hardware type (e.g., "Mobile Phone", "Tablet", "Desktop").
    hwtype: ?[]const u8 = null,
    /// Whether this is a mobile device.
    is_mobile: ?bool = null,
    /// Whether this is a tablet.
    is_tablet: ?bool = null,
    /// Whether this is a desktop.
    is_desktop: ?bool = null,
    /// Whether this is a smart TV.
    is_smarttv: ?bool = null,
    /// Whether this is a game console.
    is_gameconsole: ?bool = null,
    /// Whether this is an ebook reader.
    is_ereader: ?bool = null,
    /// Whether this is a media player.
    is_mediaplayer: ?bool = null,
    /// Whether this is a TV player.
    is_tvplayer: ?bool = null,
    /// Whether touch screen is supported.
    is_touchscreen: ?bool = null,
};

/// Full device detection response containing device, OS, and user agent info.
pub const DetectionResult = struct {
    device: Device = .{},
    // These are present in the response but currently empty objects
    // user_agent: struct {} = .{},
    // os: struct {} = .{},
};

/// Detect device information from a User-Agent string.
/// Returns parsed detection result with device information.
pub fn lookup(allocator: Allocator, user_agent: []const u8, buf: []u8) !std.json.Parsed(DetectionResult) {
    var len: usize = undefined;

    try fastly(wasm.FastlyDeviceDetection.lookup(
        user_agent.ptr,
        user_agent.len,
        buf.ptr,
        buf.len,
        &len,
    ));

    return try std.json.parseFromSlice(
        DetectionResult,
        allocator,
        buf[0..len],
        .{ .ignore_unknown_fields = true },
    );
}

/// Detect device information from a User-Agent string.
/// Returns raw JSON response.
pub fn lookupRaw(user_agent: []const u8, buf: []u8) ![]const u8 {
    var len: usize = undefined;

    try fastly(wasm.FastlyDeviceDetection.lookup(
        user_agent.ptr,
        user_agent.len,
        buf.ptr,
        buf.len,
        &len,
    ));

    return buf[0..len];
}

/// Check if a User-Agent represents a mobile device.
pub fn isMobile(allocator: Allocator, user_agent: []const u8) !bool {
    var buf: [4096]u8 = undefined;
    const result = try lookup(allocator, user_agent, &buf);
    defer result.deinit();
    return result.value.device.is_mobile orelse false;
}

/// Check if a User-Agent represents a tablet.
pub fn isTablet(allocator: Allocator, user_agent: []const u8) !bool {
    var buf: [4096]u8 = undefined;
    const result = try lookup(allocator, user_agent, &buf);
    defer result.deinit();
    return result.value.device.is_tablet orelse false;
}

/// Check if a User-Agent represents a desktop.
pub fn isDesktop(allocator: Allocator, user_agent: []const u8) !bool {
    var buf: [4096]u8 = undefined;
    const result = try lookup(allocator, user_agent, &buf);
    defer result.deinit();
    return result.value.device.is_desktop orelse false;
}
