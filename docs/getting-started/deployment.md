# Deployment

Deploy your Zigly service to Fastly Compute.

## Prerequisites

1. A [Fastly account](https://www.fastly.com/signup/)
2. The [Fastly CLI](https://github.com/fastly/cli) installed
3. An API token with appropriate permissions

### Installing Fastly CLI

```bash
# macOS
brew install fastly/tap/fastly

# Other platforms: download from GitHub releases
# https://github.com/fastly/cli/releases
```

Configure authentication:

```bash
fastly profile create
# Enter your API token when prompted
```

## Project Configuration

Create or update `fastly.toml`:

```toml
manifest_version = 3
name = "my-edge-service"
description = "My Zigly service"
authors = ["you@example.com"]
language = "other"
service_id = ""  # Filled after first deploy

[scripts]
build = "zig build -Doptimize=ReleaseSmall && mkdir -p bin && cp zig-out/bin/service.wasm bin/main.wasm"
```

The build script:
1. Compiles with size optimizations
2. Copies the binary to where Fastly CLI expects it

## Backends

Configure backends in your Fastly service. You can do this via the Fastly web UI or CLI.

### Via CLI

```bash
# Create a backend
fastly backend create --version latest --name origin --address api.example.com --port 443 --use-ssl
```

### Via fastly.toml

For new services, define backends:

```toml
[setup.backends]
  [setup.backends.origin]
  address = "api.example.com"
  port = 443
```

## Building

Build the WebAssembly binary:

```bash
# Using the fastly.toml script
fastly compute build

# Or manually
zig build -Doptimize=ReleaseSmall
mkdir -p bin
cp zig-out/bin/service.wasm bin/main.wasm
```

### Build Optimizations

For production, use `ReleaseSmall`:

```bash
zig build -Doptimize=ReleaseSmall
```

This produces the smallest binary. Use `ReleaseFast` if you need maximum performance and can tolerate a larger binary.

## Deploying

### First Deployment

Create a new Fastly service and deploy:

```bash
fastly compute publish
```

This will:
1. Create a new Compute service (if `service_id` is empty)
2. Upload your WebAssembly binary
3. Activate the new version

The CLI updates `fastly.toml` with your `service_id`.

### Subsequent Deployments

```bash
fastly compute publish
```

### Deploy Without Activating

Deploy but don't activate (useful for staging):

```bash
fastly compute publish --skip-activation
```

Activate later:

```bash
fastly service-version activate --version <version_number>
```

## Domain Configuration

### Custom Domains

Add your domain via the Fastly UI or CLI:

```bash
fastly domain create --name www.example.com --version latest
```

Point your DNS to Fastly:
- CNAME: `www.example.com` → `<service-id>.global.ssl.fastly.net`

### Default Domain

Every service gets a default domain:
```
https://<random>.edgecompute.app
```

This is useful for testing before configuring custom domains.

## Environment-Specific Configuration

### Edge Dictionaries

Store configuration that varies between environments:

```bash
# Create a dictionary
fastly dictionary create --name config --version latest

# Add items
fastly dictionary-item create --dictionary-id <id> --key api_url --value "https://api.example.com"
```

Access in code:

```zig
const zigly = @import("zigly");

fn start() !void {
    const allocator = std.heap.page_allocator;

    var config = try zigly.Dictionary.open("config");
    const api_url = try config.get(allocator, "api_url");

    // Use api_url...
}
```

### KV Stores

For larger or more dynamic data:

```bash
# Create a KV store
fastly kv-store create --name my-store

# Link to your service
fastly resource-link create --version latest --resource-id <store-id>
```

## Logging

Configure log endpoints in the Fastly UI or CLI:

```bash
# Example: S3 logging
fastly logging s3 create \
  --name access-logs \
  --bucket my-bucket \
  --access-key <key> \
  --secret-key <secret> \
  --version latest
```

Use in code:

```zig
var logger = try zigly.Logger.open("access-logs");
try logger.write("Request processed");
```

## Monitoring

### Real-time Stats

```bash
fastly stats --service-id <id>
```

### Logs

```bash
fastly log-tail --service-id <id>
```

### vCPU Usage

Monitor compute costs in code:

```zig
const runtime = zigly.runtime;

fn start() !void {
    // ... handle request ...

    const vcpu_ms = try runtime.getVcpuMs();
    std.debug.print("vCPU time: {}ms\n", .{vcpu_ms});
}
```

## CI/CD

### GitHub Actions Example

```yaml
name: Deploy
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Zig
        uses: goto-bus-stop/setup-zig@v2
        with:
          version: 0.16.0

      - name: Build
        run: zig build -Doptimize=ReleaseSmall

      - name: Setup Fastly CLI
        uses: fastly/compute-actions/setup@v6

      - name: Deploy
        run: fastly compute publish --token ${{ secrets.FASTLY_API_TOKEN }}
```

## Rollback

Revert to a previous version:

```bash
# List versions
fastly service-version list

# Activate a previous version
fastly service-version activate --version <version_number>
```

## Troubleshooting

### Build Failures

Check that your binary is at `bin/main.wasm`:

```bash
ls -la bin/main.wasm
```

### Runtime Errors

Check logs:

```bash
fastly log-tail
```

### Backend Timeouts

Verify backend configuration:

```bash
fastly backend list --version latest
```

## Next Steps

- [Architecture](../concepts/architecture.md) - Understand the runtime
- [Guides](../guides/proxying.md) - Learn common patterns
