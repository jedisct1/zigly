# Backend Reference

The backend module provides static backend queries and dynamic backend creation.

## Backend

Query information about configured backends.

### Static Methods

#### exists

```zig
pub fn exists(name: []const u8) !bool
```

Check if a backend with this name exists.

```zig
const Backend = zigly.Backend;

if (try Backend.exists("origin")) {
    // Backend is configured
}
```

### Instance Methods

Create a `Backend` from a name:

```zig
const backend = Backend{ .name = "origin" };
```

#### isHealthy

```zig
pub fn isHealthy(self: Backend) !BackendHealth
```

Check the backend's health status.

```zig
const health = try backend.isHealthy();
// Returns BackendHealth enum
```

#### isDynamic

```zig
pub fn isDynamic(self: Backend) !bool
```

Check if this backend was created dynamically at runtime.

#### isSsl

```zig
pub fn isSsl(self: Backend) !bool
```

Check if this backend uses SSL/TLS.

#### getHost

```zig
pub fn getHost(self: Backend, buf: []u8) ![]const u8
```

Get the configured host.

```zig
var buf: [256]u8 = undefined;
const host = try backend.getHost(&buf);
```

#### getOverrideHost

```zig
pub fn getOverrideHost(self: Backend, buf: []u8) ![]const u8
```

Get the host override value.

#### getPort

```zig
pub fn getPort(self: Backend) !u16
```

Get the configured port.

#### getConnectTimeoutMs

```zig
pub fn getConnectTimeoutMs(self: Backend) !u32
```

Get the connection timeout in milliseconds.

#### getFirstByteTimeoutMs

```zig
pub fn getFirstByteTimeoutMs(self: Backend) !u32
```

Get the first byte timeout in milliseconds.

#### getBetweenBytesTimeoutMs

```zig
pub fn getBetweenBytesTimeoutMs(self: Backend) !u32
```

Get the between-bytes timeout in milliseconds.

#### getSslMinVersion

```zig
pub fn getSslMinVersion(self: Backend) !TlsVersion
```

Get the minimum TLS version.

#### getSslMaxVersion

```zig
pub fn getSslMaxVersion(self: Backend) !TlsVersion
```

Get the maximum TLS version.

---

## DynamicBackend

Create backends at runtime.

### Fields

```zig
pub const DynamicBackend = struct {
    name: []const u8,                      // Required: backend name
    target: []const u8,                    // Required: host:port
    host_override: ?[]const u8 = null,     // Override Host header
    connect_timeout_ms: ?u32 = null,       // Connection timeout
    first_byte_timeout_ms: ?u32 = null,    // First byte timeout
    between_bytes_timeout_ms: ?u32 = null, // Between bytes timeout
    use_ssl: bool = false,                 // Enable TLS
    ssl_min_version: ?TlsVersion = null,   // Min TLS version
    ssl_max_version: ?TlsVersion = null,   // Max TLS version
    cert_hostname: ?[]const u8 = null,     // Certificate hostname
    ca_cert: ?[]const u8 = null,           // CA certificate
    ciphers: ?[]const u8 = null,           // Cipher list
    sni_hostname: ?[]const u8 = null,      // SNI hostname
    dont_pool: bool = false,               // Disable connection pooling
    grpc: bool = false,                    // Enable gRPC mode
};
```

### Methods

#### register

```zig
pub fn register(self: DynamicBackend) !Backend
```

Register the dynamic backend and return a `Backend` handle.

### Example

```zig
const DynamicBackend = zigly.DynamicBackend;

const backend = try (DynamicBackend{
    .name = "api_backend",
    .target = "api.example.com:443",
    .use_ssl = true,
    .host_override = "api.example.com",
    .sni_hostname = "api.example.com",
    .cert_hostname = "api.example.com",
    .connect_timeout_ms = 5000,
    .first_byte_timeout_ms = 15000,
    .between_bytes_timeout_ms = 10000,
}).register();

// Use the backend
try downstream.proxy(backend.name, null);
```

### HTTPS Backend

```zig
const https_backend = try (DynamicBackend{
    .name = "secure_api",
    .target = "secure.example.com:443",
    .use_ssl = true,
    .sni_hostname = "secure.example.com",
    .cert_hostname = "secure.example.com",
}).register();
```

### Custom Timeouts

```zig
const slow_backend = try (DynamicBackend{
    .name = "slow_service",
    .target = "slow.example.com:80",
    .connect_timeout_ms = 10000,       // 10s connect timeout
    .first_byte_timeout_ms = 60000,    // 60s first byte
    .between_bytes_timeout_ms = 30000, // 30s between bytes
}).register();
```

### gRPC Backend

```zig
const grpc_backend = try (DynamicBackend{
    .name = "grpc_service",
    .target = "grpc.example.com:443",
    .use_ssl = true,
    .grpc = true,
    .sni_hostname = "grpc.example.com",
}).register();
```

---

## TlsVersion

TLS version enum. Values are imported from `wasm.TlsVersion`.

---

## BackendHealth

Backend health status enum. Values are imported from `wasm.BackendHealth`.
