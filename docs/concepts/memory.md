# Memory Management

Zigly functions that allocate memory require an explicit allocator. This document covers allocator patterns for edge services.

## Why Explicit Allocators?

Zig doesn't have a global allocator. Functions that need to allocate memory take an `Allocator` parameter:

```zig
// Allocates memory for the header value
const user_agent = try request.headers.get(allocator, "User-Agent");
```

This makes allocation explicit and controllable, which matters in memory-constrained WebAssembly environments.

## Allocator Types

### Page Allocator

The simplest choice, allocates directly from WebAssembly memory pages:

```zig
const allocator = std.heap.page_allocator;
const data = try allocator.alloc(u8, 1024);
defer allocator.free(data);
```

Fast but doesn't track allocations. Memory isn't automatically freed.

### General Purpose Allocator

Tracks allocations, detects leaks in debug builds:

```zig
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
defer _ = gpa.deinit();
const allocator = gpa.allocator();
```

Slower than page allocator but helps find memory issues during development.

### Arena Allocator

Allocates from a growing region, frees everything at once:

```zig
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
defer arena.deinit();  // Frees all allocations
const allocator = arena.allocator();

// These allocations are freed together when arena is deinitialized
const header1 = try request.headers.get(allocator, "Host");
const header2 = try request.headers.get(allocator, "User-Agent");
const body = try request.body.readAll(allocator, 0);
// No individual free() calls needed
```

Arenas are ideal for request handling—allocate throughout the request, free everything at the end.

## Patterns

### Request-Scoped Arena

The recommended pattern for most services:

```zig
fn start() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var downstream = try zigly.downstream();

    // All allocations use the arena
    const user_agent = try downstream.request.headers.get(allocator, "User-Agent");
    const body = try downstream.request.body.readAll(allocator, 0);

    // Process request...

    try downstream.response.setStatus(200);
    try downstream.response.finish();
}
// Arena frees everything when function returns
```

### Scoped Allocations

Use inner arenas for temporary work:

```zig
fn start() !void {
    var main_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer main_arena.deinit();
    const allocator = main_arena.allocator();

    var downstream = try zigly.downstream();

    // Temporary processing with inner arena
    {
        var temp_arena = std.heap.ArenaAllocator.init(allocator);
        defer temp_arena.deinit();
        const temp = temp_arena.allocator();

        const large_data = try fetchLargeData(temp);
        const result = processData(large_data);
        // large_data freed here when temp_arena is deinitialized
    }

    // Continue with main allocator
}
```

### Fixed Buffers

For known-size data, use stack buffers:

```zig
fn start() !void {
    var downstream = try zigly.downstream();

    // Stack buffer for method (methods are short)
    var method_buf: [16]u8 = undefined;
    const method = try downstream.request.getMethod(&method_buf);

    // Stack buffer for URI
    var uri_buf: [4096]u8 = undefined;
    const uri = try downstream.request.getUriString(&uri_buf);

    // No allocation needed for these
}
```

## Memory-Aware Functions

Some Zigly functions allocate, others use provided buffers:

```zig
// ALLOCATES - returns owned memory
const header = try request.headers.get(allocator, "Host");  // allocator required

// BUFFER - writes to provided buffer
var method_buf: [16]u8 = undefined;
const method = try request.getMethod(&method_buf);  // no allocator

// BUFFER - writes to provided buffer
var uri_buf: [4096]u8 = undefined;
const uri = try request.getUriString(&uri_buf);  // no allocator
```

Prefer buffer-based functions when you know the maximum size.

## Reading Bodies

Bodies can be large. Control memory usage:

```zig
// Read entire body (for small bodies)
const body = try request.body.readAll(allocator, 0);  // 0 = no limit

// Limit maximum size
const body = try request.body.readAll(allocator, 1024 * 1024);  // 1MB max

// Streaming read (for large bodies)
var buf: [4096]u8 = undefined;
while (true) {
    const chunk = try request.body.read(&buf);
    if (chunk.len == 0) break;
    // Process chunk...
}
```

## WebAssembly Memory Limits

WebAssembly linear memory starts small and grows on demand. Be aware of:

- **Initial memory**: Usually 1-4 pages (64KB each)
- **Maximum memory**: Platform-dependent, typically 256MB-4GB
- **Growth**: Memory can grow but never shrink

Large allocations can fail if memory can't grow:

```zig
const huge = allocator.alloc(u8, 100 * 1024 * 1024) catch |err| {
    // Handle out of memory
    return err;
};
```

## Avoiding Leaks

### Always Defer Cleanup

```zig
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
defer arena.deinit();  // Always runs, even on error
```

### Close Resources

```zig
var entry = try cache.lookup("key", .{});
defer entry.close() catch {};

var body = try entry.getBody(null);
defer body.close() catch {};
```

### GPA for Development

Use GeneralPurposeAllocator during development to detect leaks:

```zig
fn start() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer {
        const status = gpa.deinit();
        if (status == .leak) {
            std.debug.print("Memory leak detected!\n", .{});
        }
    }
    const allocator = gpa.allocator();
    // ...
}
```

The leak detection only works locally (with `std.debug.print`), not in production.

## Performance Tips

1. **Use arenas** for request-scoped allocations
2. **Reuse buffers** for repeated operations
3. **Limit body sizes** to prevent memory exhaustion
4. **Prefer stack buffers** for small, fixed-size data
5. **Stream large bodies** instead of loading entirely

## Example: Efficient Request Handler

```zig
const std = @import("std");
const zigly = @import("zigly");

fn start() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var downstream = try zigly.downstream();

    // Stack buffers for small data
    var method_buf: [16]u8 = undefined;
    const method = try downstream.request.getMethod(&method_buf);

    var uri_buf: [4096]u8 = undefined;
    const uri = try downstream.request.getUriString(&uri_buf);

    // Arena for variable-size data
    const headers = try downstream.request.headers.names(alloc);

    // Limit body size
    const body = try downstream.request.body.readAll(alloc, 64 * 1024);  // 64KB max

    // Process and respond
    try downstream.response.setStatus(200);
    try downstream.response.finish();
}
// Arena frees everything

pub export fn _start() callconv(.c) void {
    start() catch {};
}
```

## Next Steps

- [Architecture](architecture.md) - Understand the runtime environment
- [Error Handling](error-handling.md) - Handle allocation failures
