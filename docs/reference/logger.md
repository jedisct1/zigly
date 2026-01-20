# Logger Reference

The Logger module provides access to Fastly logging endpoints.

## Logger

### Opening a Logger

```zig
pub fn open(name: []const u8) !Logger
```

Open a logging endpoint by name.

```zig
const Logger = zigly.Logger;

var log = try Logger.open("my_log_endpoint");
```

### Methods

#### write

```zig
pub fn write(self: *Logger, msg: []const u8) !void
```

Send a message to the logging endpoint.

```zig
try log.write("Request processed successfully");
```

---

## Example Usage

### Basic Logging

```zig
const std = @import("std");
const zigly = @import("zigly");
const Logger = zigly.Logger;

fn start() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var downstream = try zigly.downstream();

    // Open log endpoint
    var log = try Logger.open("access_log");

    // Get request info
    var method_buf: [16]u8 = undefined;
    const method = try downstream.request.getMethod(&method_buf);

    var uri_buf: [4096]u8 = undefined;
    const uri = try downstream.request.getUriString(&uri_buf);

    // Log request
    var log_buf: [512]u8 = undefined;
    const log_msg = try std.fmt.bufPrint(&log_buf, "{s} {s}", .{ method, uri });
    try log.write(log_msg);

    try downstream.proxy("origin", null);
}
```

### Structured Logging

```zig
fn logRequest(
    allocator: Allocator,
    log: *Logger,
    request: anytype,
    status: u16,
    duration_ms: u64,
) !void {
    var method_buf: [16]u8 = undefined;
    const method = try request.getMethod(&method_buf);

    var uri_buf: [4096]u8 = undefined;
    const uri = try request.getUriString(&uri_buf);

    const client_ip = zigly.http.Downstream.getClientIpAddr() catch unreachable;
    const ip_str = try client_ip.print(allocator);
    defer allocator.free(ip_str);

    // JSON structured log
    const log_msg = try std.fmt.allocPrint(allocator,
        \\{{"method":"{s}","uri":"{s}","status":{d},"client_ip":"{s}","duration_ms":{d}}}
    , .{ method, uri, status, ip_str, duration_ms });
    defer allocator.free(log_msg);

    try log.write(log_msg);
}
```

### Error Logging

```zig
fn logError(err: anyerror, context: []const u8) void {
    var log = Logger.open("error_log") catch return;

    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "ERROR: {} - {s}", .{ err, context }) catch return;
    log.write(msg) catch {};
}

fn start() !void {
    var downstream = try zigly.downstream();

    downstream.proxy("origin", null) catch |err| {
        logError(err, "proxy to origin failed");
        try downstream.response.setStatus(503);
        try downstream.response.finish();
        return;
    };
}
```

### Apache Combined Log Format

Use the built-in Apache log function:

```zig
fn start() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var downstream = try zigly.downstream();

    // Process request and track response details
    try downstream.proxy("origin", null);

    // Log in Apache combined format
    try downstream.request.logApacheCombined(
        allocator,
        "access_log",  // Log endpoint name
        200,           // Status code
        1234,          // Response size in bytes
    );
}
```

---

## Local Testing Configuration

Configure logging endpoints in `fastly.toml`:

```toml
[local_server.log_endpoints]
  [local_server.log_endpoints.access_log]
  file = "logs/access.log"

  [local_server.log_endpoints.error_log]
  file = "logs/error.log"
```

Logs will be written to the specified files.

---

## Production Configuration

In production, configure logging endpoints through the Fastly UI or CLI:

```bash
# S3 logging
fastly logging s3 create \
  --name access_log \
  --bucket my-logs-bucket \
  --access-key $AWS_ACCESS_KEY \
  --secret-key $AWS_SECRET_KEY \
  --version latest

# Datadog logging
fastly logging datadog create \
  --name datadog_log \
  --token $DATADOG_API_KEY \
  --region US \
  --version latest

# BigQuery logging
fastly logging bigquery create \
  --name bigquery_log \
  --project my-project \
  --dataset my_dataset \
  --table request_logs \
  --user $SERVICE_ACCOUNT \
  --secret-key $PRIVATE_KEY \
  --version latest
```
