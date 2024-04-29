![Zigly](logo.png)
========

The easiest way to write Fastly Compute services in Zig.

- [](#)
  - [What is Fastly Compute?](#what-is-fastly-compute)
  - [What is Zigly?](#what-is-zigly)
  - [Usage](#usage)
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
  - [Deployment to Fastly's platform](#deployment-to-fastlys-platform)

## What is Fastly Compute?

[Fastly Compute](https://www.fastly.com/products/edge-compute/serverless/) is [Fastly](https://fastly.com)'s service to run custom code directly on CDN nodes.

The service runs anything that can be compiled to WebAssembly, and exports a convenient set of functions to interact with the platform.

## What is Zigly?

Zigly is a library that makes it easy to write Fastly Compute modules in [Zig](https://ziglang.org).

Beyond the functions exported by the Fastly platform, Zigly will eventually include additional utility functions (cookie manipulation, JWT tokens, tracing...) to make application development as simple as possible.

Zigly is written for Zig 0.12.x.

## Usage

### Adding Zigly as a dependency

Add the dependency to your project:

```sh
zig fetch --save=zigly https://github.com/jedisct1/zigly/archive/refs/tags/0.1.4.tar.gz
```

And the following to your `build.zig` file:

```zig
    const zigly = b.dependency("zigly", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zigly", zigly.module("zigly"));
    exe.linkLibrary(zigly.artifact("zigly"));
```

The `zigly` structure can be imported in your application with:

```zig
const zigly = @import("zigly");
```

### A minimal WebAssembly program

```zig
const std = @import("std");

pub fn main() !void
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
const target = try std.zig.CrossTarget.parse(.{ .arch_os_abi = "wasm32-wasi" });
```

...and build with `zig build -Doptimize=ReleaseSmall` or `-Doptimize=ReleaseFast` to get optimized modules.

### Testing Fastly Compute modules

The easiest way to test the resulting modules is to use [Viceroy](https://github.com/fastly/Viceroy), a reimplementation of the Fastly API that runs locally.

### Using Zigly

#### Hello world!

```zig
var downstream = try zigly.downstream();
var response = downstream.response;
try response.body.writeAll("Hello world!");
try response.finish();
```

`downstream()` returns a type representing the initial connection, from a client to the proxy.

That type includes `response`, that can be used to send a response, as well as `request`, that can be used to inspect the incoming request.

Every function call may fail with an error from the `FastlyError` set.

Slightly more complicated example:

```zig
var downstream = try zigly.downstream();
var response = downstream.response;

response.setStatus(201);
response.headers.set("X-Example", "Header");

try response.body.writeAll("Partial");
try response.flush();
try response.body.writeAll("Response");
try response.finish();

var logger = Logger.open("logging_endpoint");
logger.write("Operation sucessful!");
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
const request = downstream.request;
const user_agent = try request.headers.get(allocator, "user-agent");
if (request.isPost()) {
    // method is POST, read the body until the end, up to 1000000 bytes
    const body = try request.body.readAll(allocator, 1000000);
}
```

As usual in Zig, memory allocations are never hidden, and applications can choose the allocator they want to use for individual function calls.

#### Making HTTP queries

Making HTTP queries is easy:

```zig
var query = try zigly.Request.new("GET", "https://example.com");
var response = try query.send("backend");
const body = try response.body.readAll(allocator, 0);
```

Arbitrary headers can be added the the outgoing `query`:

```zig
try query.headers.set("X-Custom-Header", "Custom value");
```

Body content can also be pushed, even as chunks:

```zig
try query.body.write("X");
try query.body.write("Y");
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
var query = try zigly.Request.new("GET", "https://google.com");
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
var downstream = try zigly.downstream();
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
const logger = try zigly.Logger.open("endpoint);
try logger.write("Log entry");
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
build = "zig build -Doptimize=ReleaseSmall -Dtarget=wasm32-wasi && mkdir -p bin && fastly compute pack --wasm-binary zig-out/bin/*"
```

3. Package the Fastly Compute module, passing in your compiled WebAssembly module.

```sh
fastly compute pack -w zig-out/bin/main.wasm
```

4. Test locally

```sh
fastly compute serve --skip-build --file zig-out/bin/main.wasm
```

5. Deploy!

```sh
fastly compute deploy
```

In order to deploy new versions, repeat steps 3 and 5.
