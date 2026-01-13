![Zigly](logo.png)
========

The easiest way to write Fastly Compute services in Zig.

- [What is Fastly Compute?](#what-is-fastly-compute)
- [What is Zigly?](#what-is-zigly)
- [Usage](#usage)
  - [Example application](#example-application)
  - [Adding Zigly as a dependency](#adding-zigly-as-a-dependency)
  - [A minimal WebAssembly program](#a-minimal-webassembly-program)
  - [Testing Fastly Compute modules](#testing-fastly-compute-modules)
  - [Using Zigly](#using-zigly)
    - [Hello world!](#hello-world)
    - [Inspecting incoming requests](#inspecting-incoming-requests)
    - [Making HTTP queries](#making-http-queries)
    - [Cache override](#cache-override)
    - [Pipes](#pipes)
  - [Proxying](#proxying)
  - [Redirects](#redirects)
  - [Response decompression](#response-decompression)
    - [Dictionaries](#dictionaries)
    - [Logging](#logging)
    - [KV Store](#kv-store)
    - [Geolocation](#geolocation)
    - [User Agent Parsing](#user-agent-parsing)
    - [Dynamic Backends](#dynamic-backends)
    - [ACL (Access Control Lists)](#acl-access-control-lists)
    - [Device Detection](#device-detection)
    - [Cache Purging](#cache-purging)
    - [Runtime Metrics](#runtime-metrics)
    - [Cache Transactions](#cache-transactions)
    - [Rate Limiting](#rate-limiting)
- [Deployment to Fastly's platform](#deployment-to-fastlys-platform)

## What is Fastly Compute?

[Fastly Compute](https://www.fastly.com/products/compute) is [Fastly](https://fastly.com)'s service to run custom code directly on CDN nodes.

The service runs anything that can be compiled to WebAssembly, and exports a convenient set of functions to interact with the platform.

## What is Zigly?

Zigly is a library that makes it easy to write Fastly Compute modules in [Zig](https://ziglang.org).

Beyond the functions exported by the Fastly platform, Zigly will eventually include additional utility functions (cookie manipulation, JWT tokens, tracing...) to make application development as simple as possible.

Zigly is written for Zig 0.16.x and later versions.

## Usage

### Example application

Check out the `example` directory.

This contains an example Fastly application that relays all incoming traffic to a backend server, with transparent caching.

If you just want to use Fastly as a CDN, this is all you need!

### Adding Zigly as a dependency

Add the dependency to your project:

```sh
zig fetch --save=zigly https://github.com/jedisct1/zigly/archive/refs/tags/0.1.11.tar.gz
```

And the following to your `build.zig` file:

```zig
    const zigly = b.dependency("zigly", .{
        .target = target,
        .optimize = optimize,
    });

    const exe_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_module.addImport("zigly", zigly.module("zigly"));
    exe_module.linkLibrary(zigly.artifact("zigly"));

    const exe = b.addExecutable(.{
        .name = "my_app",
        .root_module = exe_module,
    });

    b.installArtifact(exe);
```

The `zigly` structure can be imported in your application with:

```zig
const zigly = @import("zigly");
```

### A minimal WebAssembly program

```zig
const std = @import("std");

pub fn main() !void {
    std.debug.print("Hello from WebAssembly and Zig!\n", .{});
}
```

The program can be compiled with (replace `example.zig` with the source file name):

```sh
zig build-exe -target wasm32-wasi example.zig
```

Happy with the result? Add `-Doptimize=ReleaseSmall` or `-Doptimize=ReleaseFast` to get very small or very fast module:

```sh
zig build-exe -target wasm32-wasi -Doptimize=ReleaseSmall example.zig
```

The example above should not compile to more than 411 bytes.

If you are using a build file instead, define the target as `wasm32-wasi` in the `build.zig` file:

```zig
const target = b.standardTargetOptions(.{ .default_target = .{ .cpu_arch = .wasm32, .os_tag = .wasi } });
```

...and build with `zig build -Doptimize=ReleaseSmall` or `-Doptimize=ReleaseFast` to get optimized modules.

### Testing Fastly Compute modules

The easiest way to test the resulting modules is to use [Viceroy](https://github.com/fastly/Viceroy), a reimplementation of the Fastly API that runs locally.

### Using Zigly

#### Hello world!

```zig
const downstream = try zigly.downstream();
var response = downstream.response;
try response.body.writeAll("Hello world!");
try response.finish();
```

`downstream()` returns a type representing the initial connection, from a client to the proxy.

That type includes `response`, that can be used to send a response, as well as `request`, that can be used to inspect the incoming request.

Every function call may fail with an error from the `FastlyError` set.

Slightly more complicated example:

```zig
const downstream = try zigly.downstream();
var response = downstream.response;

try response.setStatus(201);
try response.headers.set("X-Example", "Header");

try response.body.writeAll("Partial");
try response.flush();
try response.body.writeAll("Response");
try response.finish();

var logger = try zigly.Logger.open("logging_endpoint");
try logger.write("Operation successful!");
```

Note that calling `finish()` is always required in order to actually send a response to the client.

But realistically, most responses will either be simple redirects:

```zig
var downstream = try zigly.downstream();
try downstream.redirect(302, "https://www.perdu.com");
```

or responding directly from the cache, proxying to the origin if the cached entry is nonexistent or expired:

```zig
var downstream = try zigly.downstream();
try downstream.proxy("google", "www.google.com");
```

#### Inspecting incoming requests

Applications can read the body of an incoming requests as well as other informations such as the headers:

```zig
var request = downstream.request;
const user_agent = try request.headers.get(allocator, "user-agent");
if (try request.isPost()) {
    // method is POST, read the body until the end, up to 1000000 bytes
    const body = try request.body.readAll(allocator, 1000000);
}
```

As usual in Zig, memory allocations are never hidden, and applications can choose the allocator they want to use for individual function calls.

#### Making HTTP queries

Making HTTP queries is easy:

```zig
var query = try zigly.http.Request.new("GET", "https://example.com");
var response = try query.send("backend");
const body = try response.body.readAll(allocator, 0);
```

Arbitrary headers can be added the the outgoing `query`:

```zig
try query.headers.set("X-Custom-Header", "Custom value");
```

Body content can also be pushed, even as chunks:

```zig
_ = try query.body.write("X");
_ = try query.body.write("Y");
try query.body.close();
```

And the resulting `response` contains `headers` and `body` properties, that can be inspected the same way as a downstream query.

#### Cache override

Caching can be disabled or configured on a per-query basis with `setCachingPolicy()`:

```zig
try query.setCachingPolicy(.{ .serve_stale = 600, .pci = true });
```

Attributes include:

- `no_cache`
- `ttl`
- `serve_stale`
- `pci`
- `surrogate_key`

#### Pipes

With `pipe()`, the response sent to a client can be a direct copy of another response. The application will then act as a proxy, optionally also copying the original status and headers.

```zig
var query = try zigly.http.Request.new("GET", "https://google.com");
var upstream_response = try query.send("google");
var downstream = try zigly.downstream();
try downstream.response.pipe(&upstream_response, true, true);
```

### Proxying

Proxying is even easier to use than pipes when a query should be sent unmodified (with the exception of the `Host` header) to the origin:

```zig
var downstream = try zigly.downstream();
try downstream.proxy("google", "www.google.com");
```

The second parameter is optional. If `null`, the original `Host` header will not be modified.

### Redirects

Redirecting the client to another address can be done with a single function call on the downstream object:

```zig
const downstream = try zigly.downstream();
try downstream.redirect(302, "https://www.perdu.com");
```

### Response decompression

By default, responses are left as-is. Which means that if compression (`Content-Encoding`) was accepted by the client, the response can be compressed.

Calling `setAutoDecompressResponse(true)` on a `Request` object configures the Fastly Compute runtime to decompress gzip-encoded responses before streaming them to the application.

#### Dictionaries

```zig
const dict = try zigly.Dictionary.open("name");
const value = try dict.get(allocator, "key");
```

#### Logging

```zig
var logger = try zigly.Logger.open("endpoint");
try logger.write("Log entry");
```

#### KV Store

Store and retrieve key-value pairs using Fastly's object store:

```zig
var store = try zigly.kv.Store.open("my_store");
const value = try store.getAll("key", allocator, 0);

// Insert or replace a value
try store.replace("key", "new_value");
```

#### Geolocation

Get location information about IP addresses:

```zig
const ip = zigly.geo.Ip{ .ip4 = .{ 8, 8, 8, 8 } };
var buf: [4096]u8 = undefined;
const location = try zigly.geo.lookup(allocator, ip, &buf);
// Access location.value fields: city, country_code, latitude, longitude, etc.
```

#### User Agent Parsing

Parse user agent strings:

```zig
var family: [64]u8 = undefined;
var major: [16]u8 = undefined;
var minor: [16]u8 = undefined;
var patch: [16]u8 = undefined;
const ua = try zigly.UserAgent.parse(user_agent_string, &family, &major, &minor, &patch);
// Access ua.family, ua.major, ua.minor, ua.patch
```

#### Dynamic Backends

Register backends dynamically at runtime:

```zig
const backend_config = zigly.DynamicBackend{
    .name = "my_backend",
    .target = "example.com:443",
    .use_ssl = true,
    .host_override = "example.com",
    .sni_hostname = "example.com",
    .cert_hostname = "example.com",
    .connect_timeout_ms = 5000,
    .first_byte_timeout_ms = 15000,
    .between_bytes_timeout_ms = 10000,
};
const backend = try backend_config.register();

// Check backend properties
const exists = try zigly.Backend.exists("my_backend");
const is_ssl = try backend.isSsl();
const port = try backend.getPort();
```

#### ACL (Access Control Lists)

Check IP addresses against access control lists:

```zig
const acl = try zigly.Acl.open("my_acl");

const client_ip = zigly.geo.Ip{ .ip4 = .{ 192, 168, 1, 100 } };
if (try acl.match(allocator, client_ip)) |result| {
    defer result.deinit();
    if (result.value.isBlock()) {
        // IP is blocked
    }
    // result.value.action is "BLOCK" or "ALLOW"
    // result.value.prefix is the matching rule (e.g., "192.168.0.0/16")
} else {
    // No matching rule found
}
```

#### Device Detection

Detect device type from User-Agent strings:

```zig
const user_agent = "Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X)";
var buf: [4096]u8 = undefined;

const result = try zigly.device.lookup(allocator, user_agent, &buf);
defer result.deinit();

// Access device properties
const device = result.value.device;
// device.name, device.brand, device.model, device.hwtype
// device.is_mobile, device.is_tablet, device.is_desktop, etc.

// Or use convenience functions
const is_mobile = try zigly.device.isMobile(allocator, user_agent);
const is_desktop = try zigly.device.isDesktop(allocator, user_agent);
```

#### Cache Purging

Purge cached content by surrogate key:

```zig
// Hard purge (immediate removal)
try zigly.purge.purge("my-surrogate-key");

// Soft purge (mark as stale)
try zigly.purge.softPurge("my-surrogate-key");
```

#### Runtime Metrics

Monitor compute resource usage:

```zig
const vcpu_ms = try zigly.runtime.getVcpuMs();
// Returns the amount of vCPU time used in milliseconds
```

#### Cache Transactions

The cache API provides both simple caching and request-collapsing transactions:

```zig
const cache = zigly.cache;

// Simple cache insert
var body = try cache.insert("my-cache-key", .{
    .max_age_ns = cache.secondsToNs(3600),  // 1 hour TTL
});
_ = try body.write("Cached content");
try body.close();

// Simple cache lookup
var entry = try cache.lookup("my-cache-key", .{});
const state = try entry.getState();
if (state.isFound() and state.isUsable()) {
    var cached_body = try entry.getBody(null);
    const content = try cached_body.readAll(allocator, 0);
    // Use cached content
}
try entry.close();
```

For request-collapsing (preventing thundering herd), use transactional lookups:

```zig
// Transactional lookup - only one request will fetch/generate content
var tx = try cache.transactionLookup("my-key", .{});
const tx_state = try tx.getState();

if (tx_state.mustInsertOrUpdate()) {
    // We won the race - insert new content
    var result = try tx.insert(.{
        .max_age_ns = cache.secondsToNs(60),
    });
    _ = try result.body.write("Fresh content");
    try result.body.close();
} else if (tx_state.isUsable()) {
    // Content is available
    var cached_body = try tx.getBody(null);
    const content = try cached_body.readAll(allocator, 0);
}

try tx.close();
```

#### Rate Limiting

Edge Rate Limiting provides rate counters and penalty boxes for traffic control:

```zig
const erl = zigly.erl;

// Rate counter - track request rates
const rc = erl.RateCounter.open("my_rate_counter");
try rc.increment("client-ip-192.168.1.1", 1);

const rate = try rc.lookupRate("client-ip-192.168.1.1", 10);  // 10-second window
const count = try rc.lookupCount("client-ip-192.168.1.1", 60); // 60-second window

// Penalty box - block bad actors
const pb = erl.PenaltyBox.open("my_penalty_box");
if (try pb.has("bad-actor")) {
    // Client is in penalty box, reject request
}
try pb.add("bad-actor", 300);  // Block for 5 minutes

// Combined rate limiter
const limiter = erl.RateLimiter.init(.{
    .rate_counter = "my_rate_counter",
    .penalty_box = "my_penalty_box",
    .window_seconds = 10,
    .limit = 100,           // 100 requests per 10 seconds
    .ttl_seconds = 300,     // 5 minute penalty
});

if (!try limiter.isAllowed("client-id", 1)) {
    // Rate limited - reject request
}
```

## Deployment to Fastly's platform

The `fastly` command-line tool only supports compilation of Rust and AssemblyScript at the moment.
However, it can still be used to upload pre-compiled code written in other languages, including Zig.

1. Create a new project:

```sh
fastly compute init
```

For the language, select `Other (pre-compiled WASM binary)`.

2. Add a build script:

Add the following lines to the fastly.toml file:

```toml
[scripts]
build = "zig build -Doptimize=ReleaseSmall -Dtarget=wasm32-wasi && mkdir -p bin && cp zig-out/bin/*.wasm bin/main.wasm"
```

3. Compile and package the Fastly Compute module:

```sh
fastly compute build
```

4. Test locally

```sh
fastly compute serve
```

5. Deploy!

```sh
fastly compute deploy
```

In order to deploy new versions, repeat steps 3 and 5.
