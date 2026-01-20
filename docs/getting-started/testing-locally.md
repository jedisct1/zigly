# Testing Locally

Before deploying to Fastly, test your service locally using a Compute runtime emulator. Two options are available:

- [Viceroy](https://github.com/fastly/Viceroy) - Fastly's official local testing tool (Rust)
- [Fastlike](https://github.com/avidal/fastlike) - Community alternative (Go)

Both run your WebAssembly binary locally and emulate the Compute runtime APIs.

## Viceroy

### Installing Viceroy

**From Releases:**

```bash
# macOS (Apple Silicon)
curl -L https://github.com/fastly/Viceroy/releases/latest/download/viceroy_darwin-arm64.tar.gz | tar xz

# macOS (Intel)
curl -L https://github.com/fastly/Viceroy/releases/latest/download/viceroy_darwin-amd64.tar.gz | tar xz

# Linux
curl -L https://github.com/fastly/Viceroy/releases/latest/download/viceroy_linux-amd64.tar.gz | tar xz

sudo mv viceroy /usr/local/bin/
```

**Via Homebrew:**

```bash
brew install fastly/tap/viceroy
```

**From Source:**

```bash
cargo install viceroy
```

### Running Viceroy

```bash
# Build your service
zig build -Doptimize=ReleaseSmall

# Run with config file
viceroy --config fastly.toml zig-out/bin/service.wasm

# Or without config (limited features)
viceroy zig-out/bin/service.wasm

# Custom port
viceroy --addr 127.0.0.1:8080 zig-out/bin/service.wasm
```

Viceroy starts at `http://127.0.0.1:7878` by default.

## Fastlike

### Installing Fastlike

**From Releases:**

Download from [GitHub releases](https://github.com/avidal/fastlike/releases).

**From Source:**

```bash
go install github.com/avidal/fastlike@latest
```

### Running Fastlike

```bash
# Build your service
zig build -Doptimize=ReleaseSmall

# Run with config
fastlike -config fastly.toml zig-out/bin/service.wasm

# Custom port
fastlike -addr 127.0.0.1:8080 zig-out/bin/service.wasm
```

## Configuration

Both tools use `fastly.toml` for configuration. Create this file in your project root:

```toml
manifest_version = 3
name = "my-edge-service"
description = "My Fastly Compute service"
language = "other"

[scripts]
build = "zig build -Doptimize=ReleaseSmall && mkdir -p bin && cp zig-out/bin/service.wasm bin/main.wasm"

[local_server]
  [local_server.backends]
    [local_server.backends.origin]
    url = "https://httpbin.org"

    [local_server.backends.api]
    url = "https://api.example.com"
```

### Backend Configuration

Define backends your service will proxy to:

```toml
[local_server.backends]
  [local_server.backends.origin]
  url = "https://httpbin.org"
  override_host = "httpbin.org"

  [local_server.backends.api]
  url = "https://api.example.com"
  override_host = "api.example.com"
```

### Geolocation

Configure mock geolocation data for testing:

```toml
[local_server.geolocation]
  [local_server.geolocation.addresses]
    [local_server.geolocation.addresses."127.0.0.1"]
    as_name = "Test ISP"
    city = "San Francisco"
    country_code = "US"
    latitude = 37.7749
    longitude = -122.4194
```

### Dictionaries

Set up edge dictionaries:

```toml
[local_server.dictionaries]
  [local_server.dictionaries.config]
  file = "config.json"
  format = "json"
```

Create `config.json`:

```json
{
  "api_key": "test-key-123",
  "feature_flag": "enabled"
}
```

### KV Stores

Configure key-value stores:

```toml
[local_server.object_stores]
  [local_server.object_stores.my_store]
    [local_server.object_stores.my_store.key1]
    data = "value1"

    [local_server.object_stores.my_store.key2]
    file = "data/key2.txt"
```

### ACLs

Set up access control lists:

```toml
[local_server.acls]
  [local_server.acls.blocklist]
  file = "acl.json"
```

Create `acl.json`:

```json
{
  "entries": [
    {"prefix": "192.168.1.0/24", "action": "BLOCK"},
    {"prefix": "10.0.0.0/8", "action": "ALLOW"}
  ]
}
```

### Logging Endpoints

```toml
[local_server.log_endpoints]
  [local_server.log_endpoints.access_log]
  file = "access.log"
```

## Making Requests

Test with curl:

```bash
# Simple GET
curl http://127.0.0.1:7878/

# With headers
curl -H "X-Custom: value" http://127.0.0.1:7878/path

# POST with body
curl -X POST -d '{"key":"value"}' http://127.0.0.1:7878/api

# See response headers
curl -i http://127.0.0.1:7878/
```

## Debugging

### Print Output

Use `std.debug.print` to log to the console:

```zig
const std = @import("std");

fn start() !void {
    std.debug.print("Request received\n", .{});
    // ...
}
```

### Verbose Mode

Run with verbose output for more debugging info:

```bash
viceroy -v zig-out/bin/service.wasm
```

## Development Workflow

A typical development loop:

```bash
# Terminal 1: Watch and rebuild
watchexec -e zig "zig build -Doptimize=ReleaseSmall"

# Terminal 2: Run the emulator
viceroy --config fastly.toml zig-out/bin/service.wasm

# Terminal 3: Test
curl http://127.0.0.1:7878/
```

## Limitations

Local emulators approximate the Fastly Compute environment but have differences:

- **Performance**: Local execution doesn't reflect edge latency or throughput
- **Geolocation**: Returns mock data unless configured
- **Caching**: Simulated; doesn't persist across restarts
- **Rate limiting**: Uses local state only

Test on Fastly's actual platform before production deployment.

## Next Steps

- [Deployment](deployment.md) - Deploy to Fastly Compute
- [Error Handling](../concepts/error-handling.md) - Debug errors
