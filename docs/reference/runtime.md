# Runtime Reference

The runtime module provides information about the Fastly Compute execution environment.

## Functions

### getVcpuMs

```zig
pub fn getVcpuMs() !u64
```

Get the amount of vCPU time used by this request in milliseconds.

```zig
const runtime = zigly.runtime;

const vcpu_ms = try runtime.getVcpuMs();
std.debug.print("vCPU time: {}ms\n", .{vcpu_ms});
```

---

## Example Usage

### Performance Monitoring

```zig
const std = @import("std");
const zigly = @import("zigly");
const runtime = zigly.runtime;

fn start() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var downstream = try zigly.downstream();

    // Process request
    try downstream.proxy("origin", null);

    // Log vCPU usage
    const vcpu_ms = try runtime.getVcpuMs();

    var log = try zigly.Logger.open("metrics");
    var buf: [64]u8 = undefined;
    const msg = try std.fmt.bufPrint(&buf, "{{\"vcpu_ms\":{d}}}", .{vcpu_ms});
    try log.write(msg);
}
```

### Cost Tracking

```zig
fn start() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var downstream = try zigly.downstream();

    // Heavy processing
    // ...

    try downstream.proxy("origin", null);

    // Track expensive requests
    const vcpu_ms = try runtime.getVcpuMs();
    if (vcpu_ms > 50) {
        var log = try zigly.Logger.open("expensive_requests");

        var uri_buf: [4096]u8 = undefined;
        const uri = try downstream.request.getUriString(&uri_buf);

        var buf: [256]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, "Expensive request: {s} took {}ms vCPU", .{ uri, vcpu_ms });
        try log.write(msg);
    }
}
```

### Add to Response Headers

```zig
fn start() !void {
    var downstream = try zigly.downstream();

    // Process request
    try downstream.proxy("origin", null);

    // Add timing header (useful for debugging)
    const vcpu_ms = try runtime.getVcpuMs();
    var buf: [16]u8 = undefined;
    const vcpu_str = try std.fmt.bufPrint(&buf, "{d}", .{vcpu_ms});

    // Note: Headers must be set before finish() when using proxy()
    // This example is for manual response handling
}
```

### Request Complexity Limiting

```zig
fn processWithLimit() !void {
    var downstream = try zigly.downstream();

    // Check initial CPU usage
    const start_vcpu = try runtime.getVcpuMs();

    // Do some processing
    // ...

    // Check if we've used too much CPU
    const current_vcpu = try runtime.getVcpuMs();
    if (current_vcpu - start_vcpu > 100) {
        // Bail out - request is too expensive
        try downstream.response.setStatus(503);
        try downstream.response.body.writeAll("Request too complex");
        try downstream.response.finish();
        return;
    }

    // Continue processing
    // ...
}
```

---

## Notes

- vCPU time measures actual compute time, not wall clock time
- Time spent waiting for backends doesn't count toward vCPU
- Fastly bills based on vCPU usage
- Use this to identify expensive operations and optimize
- Values are cumulative for the current request
