# HTTP Reference

The HTTP module provides types for handling requests and responses.

## downstream()

Get the client connection:

```zig
const zigly = @import("zigly");

var downstream = try zigly.downstream();
// downstream.request  - The incoming request
// downstream.response - Your outgoing response
```

Returns a `Downstream` struct.

---

## Downstream

The connection from the client to your edge service.

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `request` | `Request` | The incoming HTTP request |
| `response` | `OutgoingResponse` | The response to send back |

### Methods

#### proxy

```zig
pub fn proxy(self: *Downstream, backend: []const u8, host_header: ?[]const u8) !void
```

Proxy the request to a backend and send the response to the client.

- `backend` - Name of the backend to send to
- `host_header` - Optional Host header value. Pass `null` to preserve the original.

```zig
try downstream.proxy("origin", "api.example.com");
```

#### redirect

```zig
pub fn redirect(self: *Downstream, status: u16, uri: []const u8) !void
```

Send an HTTP redirect response.

- `status` - HTTP status code (301, 302, 307, 308)
- `uri` - Redirect destination

```zig
try downstream.redirect(301, "https://example.com/new-path");
```

#### getClientIpAddr

```zig
pub fn getClientIpAddr() !geo.Ip
```

Get the client's IP address.

```zig
const ip = try Downstream.getClientIpAddr();
const ip_str = try ip.print(allocator);
```

---

## Request

An HTTP request, either from the client or created programmatically.

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `headers` | `RequestHeaders` | Request headers |
| `body` | `Body` | Request body |

### Static Methods

#### downstream

```zig
pub fn downstream() !Request
```

Get the incoming client request. Typically accessed via `zigly.downstream().request`.

#### new

```zig
pub fn new(method: []const u8, uri: []const u8) !Request
```

Create a new request for sending to a backend.

```zig
var req = try Request.new("POST", "https://api.example.com/data");
try req.headers.set("Content-Type", "application/json");
try req.body.writeAll("{\"key\":\"value\"}");
var resp = try req.send("api_backend");
```

### Instance Methods

#### getMethod

```zig
pub fn getMethod(self: Request, method: []u8) ![]u8
```

Copy the HTTP method to the provided buffer.

```zig
var buf: [16]u8 = undefined;
const method = try request.getMethod(&buf);  // "GET", "POST", etc.
```

#### isGet

```zig
pub fn isGet(self: Request) !bool
```

Check if the request method is GET.

#### isPost

```zig
pub fn isPost(self: Request) !bool
```

Check if the request method is POST.

#### setMethod

```zig
pub fn setMethod(self: Request, method: []const u8) !void
```

Set the request method.

```zig
try request.setMethod("PUT");
```

#### getUriString

```zig
pub fn getUriString(self: Request, uri: []u8) ![]u8
```

Copy the full URI to the provided buffer. The URI includes scheme and host when returned by Fastly's runtime.

```zig
var buf: [4096]u8 = undefined;
const uri = try request.getUriString(&buf);  // "http://example.com/path?query=value"
```

#### getUri

```zig
pub fn getUri(self: Request, uri_buf: []u8) !std.Uri
```

Parse the request URI into a `std.Uri` struct with all components separated.

```zig
var buf: [4096]u8 = undefined;
const uri = try request.getUri(&buf);
// uri.scheme - "http" or "https"
// uri.host   - Host component (optional)
// uri.path   - Path component
// uri.query  - Query string (optional)
// uri.port   - Port number (optional)
```

#### getPath

```zig
pub fn getPath(self: Request, uri_buf: []u8) ![]const u8
```

Extract just the path from the request URI, without query string or fragment. This is the most common operation for routing.

```zig
var buf: [4096]u8 = undefined;
const path = try request.getPath(&buf);  // "/api/users"
```

Example for routing:
```zig
const path = try downstream.request.getPath(&buf);
if (std.mem.startsWith(u8, path, "/api/")) {
    try downstream.proxy("api_backend", null);
}
```

#### getPathAndQuery

```zig
pub fn getPathAndQuery(self: Request, uri_buf: []u8, out_buf: []u8) ![]const u8
```

Extract the path with query string (but without fragment). Useful when you need to forward the full request path including parameters.

```zig
var uri_buf: [4096]u8 = undefined;
var out_buf: [4096]u8 = undefined;
const path_query = try request.getPathAndQuery(&uri_buf, &out_buf);  // "/api/users?id=123"
```

#### setUriString

```zig
pub fn setUriString(self: Request, uri: []const u8) !void
```

Set the request URI.

```zig
try request.setUriString("/new/path");
```

#### parseQueryParams

```zig
pub fn parseQueryParams(self: Request, allocator: Allocator) ![]QueryParam
```

Parse query parameters from the URI.

```zig
const params = try request.parseQueryParams(allocator);
for (params) |param| {
    std.debug.print("{s}={s}\n", .{ param.key, param.value });
}
```

Returns an array of `QueryParam` structs with `key` and `value` fields. Values are URL-decoded.

#### send

```zig
pub fn send(self: *Request, backend: []const u8) !IncomingResponse
```

Send the request to a backend and get the response.

```zig
var response = try request.send("origin");
const status = try response.getStatus();
```

#### setCachingPolicy

```zig
pub fn setCachingPolicy(self: *Request, policy: CachingPolicy) !void
```

Set caching behavior for this request.

```zig
try request.setCachingPolicy(.{
    .no_cache = false,
    .ttl = 300,              // Cache for 5 minutes
    .serve_stale = 3600,     // Serve stale for 1 hour if origin fails
    .surrogate_key = "my-key",
});
```

**CachingPolicy fields:**

| Field | Type | Description |
|-------|------|-------------|
| `no_cache` | `bool` | Bypass cache (default: false) |
| `ttl` | `?u32` | TTL in seconds |
| `serve_stale` | `?u32` | Stale-while-revalidate time in seconds |
| `pci` | `bool` | Enable PCI restrictions |
| `surrogate_key` | `[]const u8` | Surrogate key for purging |

#### setAutoDecompressResponse

```zig
pub fn setAutoDecompressResponse(self: *Request, enable: bool) !void
```

Enable automatic decompression of gzip responses.

```zig
try request.setAutoDecompressResponse(true);
```

#### logApacheCombined

```zig
pub fn logApacheCombined(
    self: Request,
    allocator: Allocator,
    endpoint_name: []const u8,
    status: u16,
    response_size: usize
) !void
```

Log the request in Apache combined log format.

```zig
try request.logApacheCombined(allocator, "access_log", 200, 1234);
```

#### close

```zig
pub fn close(self: *Request) !void
```

Close the request prematurely.

---

## RequestHeaders / ResponseHeaders

Header manipulation for requests and responses.

### Methods

#### get

```zig
pub fn get(self: Headers, allocator: Allocator, name: []const u8) ![]const u8
```

Get a header value. Returns `FastlyError.FastlyNone` if not found.

```zig
const content_type = try headers.get(allocator, "Content-Type");
```

#### getAll

```zig
pub fn getAll(self: Headers, allocator: Allocator, name: []const u8) ![][]const u8
```

Get all values for a header (for headers that appear multiple times).

```zig
const cookies = try headers.getAll(allocator, "Set-Cookie");
```

#### names

```zig
pub fn names(self: Headers, allocator: Allocator) ![][]const u8
```

Get all header names.

```zig
const header_names = try headers.names(allocator);
for (header_names) |name| {
    std.debug.print("{s}\n", .{name});
}
```

#### set

```zig
pub fn set(self: *Headers, name: []const u8, value: []const u8) !void
```

Set a header, replacing any existing value.

```zig
try headers.set("X-Custom", "value");
```

#### append

```zig
pub fn append(self: *Headers, allocator: Allocator, name: []const u8, value: []const u8) !void
```

Append a value to a header (creates multiple headers with the same name).

```zig
try headers.append(allocator, "Set-Cookie", "a=1");
try headers.append(allocator, "Set-Cookie", "b=2");
```

#### remove

```zig
pub fn remove(self: *Headers, name: []const u8) !void
```

Remove a header.

```zig
try headers.remove("X-Forwarded-For");
```

---

## Body

HTTP request or response body.

### Methods

#### read

```zig
pub fn read(self: *Body, buf: []u8) ![]u8
```

Read a chunk from the body. Returns an empty slice when complete.

```zig
var buf: [4096]u8 = undefined;
while (true) {
    const chunk = try body.read(&buf);
    if (chunk.len == 0) break;
    // Process chunk
}
```

#### readAll

```zig
pub fn readAll(self: *Body, allocator: Allocator, max_length: usize) ![]u8
```

Read the entire body. Pass 0 for `max_length` for no limit.

```zig
const data = try body.readAll(allocator, 1024 * 1024);  // Max 1MB
defer allocator.free(data);
```

#### write

```zig
pub fn write(self: *Body, buf: []const u8) !usize
```

Write to the body. Returns number of bytes written.

```zig
const written = try body.write("Hello, ");
```

#### writeAll

```zig
pub fn writeAll(self: *Body, buf: []const u8) !void
```

Write entire buffer to the body.

```zig
try body.writeAll("Hello, World!");
```

#### close

```zig
pub fn close(self: *Body) !void
```

Close the body.

---

## OutgoingResponse

The response sent back to the client.

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `headers` | `ResponseHeaders` | Response headers |
| `body` | `Body` | Response body |

### Methods

#### getStatus

```zig
pub fn getStatus(self: OutgoingResponse) !u16
```

Get the current status code.

#### setStatus

```zig
pub fn setStatus(self: *OutgoingResponse, status: u16) !void
```

Set the HTTP status code.

```zig
try response.setStatus(404);
```

#### flush

```zig
pub fn flush(self: *OutgoingResponse) !void
```

Send buffered data without closing. Use for streaming responses.

```zig
try response.body.writeAll("First chunk");
try response.flush();
try response.body.writeAll("Second chunk");
try response.finish();
```

#### finish

```zig
pub fn finish(self: *OutgoingResponse) !void
```

Send the response and close. **Required** to send any response.

```zig
try response.finish();
```

#### pipe

```zig
pub fn pipe(
    self: *OutgoingResponse,
    incoming: *IncomingResponse,
    copy_status: bool,
    copy_headers: bool
) !void
```

Zero-copy an incoming response to the client.

```zig
var upstream_resp = try request.send("backend");
try downstream.response.pipe(&upstream_resp, true, true);
```

---

## IncomingResponse

Response from a backend.

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `headers` | `ResponseHeaders` | Response headers |
| `body` | `Body` | Response body |

### Methods

#### getStatus

```zig
pub fn getStatus(self: IncomingResponse) !u16
```

Get the HTTP status code.

#### close

```zig
pub fn close(self: *IncomingResponse) !void
```

Close the response.

---

## QueryParam

Represents a URL query parameter.

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `key` | `[]const u8` | Parameter name |
| `value` | `[]const u8` | Parameter value (URL-decoded) |

---

## Related

- [Hello World](../getting-started/hello-world.md) - Basic HTTP handling
- [Proxying Guide](../guides/proxying.md) - Request forwarding patterns
- [Simple Proxy Example](../examples/simple-proxy.md)
- [API Gateway Example](../examples/api-gateway.md)
