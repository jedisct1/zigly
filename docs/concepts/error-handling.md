# Error Handling

Zigly functions return errors from the Fastly runtime. Understanding these errors helps debug issues and build robust services.

## FastlyError

All Fastly API calls can return errors from the `FastlyError` error set:

```zig
pub const FastlyError = error{
    FastlyGenericError,       // General error
    FastlyInvalidValue,       // Invalid parameter
    FastlyBadDescriptor,      // Invalid handle
    FastlyBufferTooSmall,     // Buffer needs to be larger
    FastlyUnsupported,        // Operation not supported
    FastlyWrongAlignment,     // Memory alignment issue
    FastlyHttpParserError,    // HTTP parsing failed
    FastlyHttpUserError,      // User-caused HTTP error
    FastlyHttpIncomplete,     // Incomplete HTTP data
    FastlyNone,               // No result (not always an error)
    FastlyHttpHeaderTooLarge, // Header exceeds limit
    FastlyHttpInvalidStatus,  // Invalid HTTP status code
    FastlyLimitExceeded,      // Rate or resource limit hit
    FastlyAgain,              // Try again later
};
```

## Common Errors and Causes

### FastlyInvalidValue

An argument was invalid:

```zig
// Invalid backend name (doesn't exist)
try request.send("nonexistent_backend");  // FastlyInvalidValue

// Invalid header name
try headers.get(alloc, "");  // FastlyInvalidValue
```

### FastlyNone

No result found. This is sometimes expected:

```zig
// Header doesn't exist
const maybe_header = headers.get(alloc, "X-Custom") catch |err| {
    if (err == FastlyError.FastlyNone) {
        // Header not present, use default
        return "default";
    }
    return err;
};
```

### FastlyBufferTooSmall

The provided buffer is too small. Zigly handles this internally by growing buffers, but you might see it if providing fixed-size buffers:

```zig
var small_buf: [8]u8 = undefined;
const method = request.getMethod(&small_buf) catch |err| {
    if (err == FastlyError.FastlyBufferTooSmall) {
        // Use larger buffer
    }
    return err;
};
```

### FastlyBadDescriptor

The handle is invalid, usually because the resource was closed:

```zig
var body = try entry.getBody(null);
try body.close();

// After close, the handle is invalid
_ = body.read(&buf);  // FastlyBadDescriptor
```

### FastlyLimitExceeded

A rate or resource limit was hit:

```zig
// Too many concurrent requests to backends
// Too many cache operations
// Rate limiting triggered
```

## Error Handling Patterns

### Try-Catch

Standard Zig error handling:

```zig
fn processRequest() !void {
    var downstream = try zigly.downstream();

    const backend_resp = downstream.proxy("origin", null) catch |err| {
        // Handle proxy failure
        try downstream.response.setStatus(503);
        try downstream.response.body.writeAll("Service unavailable");
        try downstream.response.finish();
        return;
    };
}
```

### Specific Error Handling

Handle specific errors differently:

```zig
const cache_entry = zigly.cache.lookup(key, .{}) catch |err| switch (err) {
    FastlyError.FastlyNone => {
        // Not in cache, fetch from origin
        return fetchFromOrigin(key);
    },
    FastlyError.FastlyLimitExceeded => {
        // Cache overwhelmed, go direct to origin
        return fetchFromOrigin(key);
    },
    else => return err,  // Propagate other errors
};
```

### Optional Results

For operations that might not have results:

```zig
fn getOptionalHeader(headers: anytype, alloc: Allocator, name: []const u8) ?[]const u8 {
    return headers.get(alloc, name) catch return null;
}

const auth = getOptionalHeader(request.headers, alloc, "Authorization");
if (auth) |token| {
    // Validate token
}
```

### Cleanup on Error

Use `defer` and `errdefer`:

```zig
fn processWithCache() !void {
    var entry = try zigly.cache.lookup("key", .{});
    defer entry.close() catch {};  // Always close

    var body = try entry.getBody(null);
    errdefer body.close() catch {};  // Close only on error

    const data = try body.readAll(alloc, 0);
    // Use data...
}
```

## Sending Error Responses

When errors occur, send appropriate HTTP responses:

```zig
fn start() !void {
    handleRequest() catch |err| {
        sendErrorResponse(err) catch {};
    };
}

fn sendErrorResponse(err: anyerror) !void {
    var downstream = try zigly.downstream();

    const status: u16 = switch (err) {
        FastlyError.FastlyInvalidValue => 400,
        FastlyError.FastlyNone => 404,
        FastlyError.FastlyLimitExceeded => 429,
        else => 500,
    };

    try downstream.response.setStatus(status);
    try downstream.response.headers.set("Content-Type", "text/plain");
    try downstream.response.body.writeAll("An error occurred");
    try downstream.response.finish();
}
```

## Logging Errors

Log errors for debugging:

```zig
const std = @import("std");

fn handleError(err: anyerror) void {
    std.debug.print("Error occurred: {}\n", .{err});

    // Or log to Fastly endpoint
    if (zigly.Logger.open("errors")) |*logger| {
        var buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "Error: {}", .{err}) catch return;
        logger.write(msg) catch {};
    } else |_| {}
}
```

## Compatibility Check

Verify API compatibility at startup:

```zig
fn start() !void {
    try zigly.compatibilityCheck();
    // Proceed with request handling
}
```

This catches version mismatches between your code and the runtime.

## Testing Error Paths

Test error handling locally:

1. Configure missing backends to test backend errors
2. Use invalid dictionary names to test lookup errors
3. Set cache limits to test limit errors

```toml
# fastly.toml - deliberately omit a backend to test error handling
[local_server.backends]
  [local_server.backends.origin]
  url = "https://httpbin.org"
  # No "backup" backend - accessing it will error
```

## Next Steps

- [Memory Management](memory.md) - Avoid allocation errors
- [Architecture](architecture.md) - Understanding the runtime
