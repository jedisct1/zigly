![Zigly](logo.png)
========

The easiest way to write Compute@Edge services.

## What is Compute@Edge?

[Compute@Edge](https://www.fastly.com/products/edge-compute/serverless/) is [Fastly](https://fastly.com)'s service to run custom code directly on CDN nodes.

The service runs anything that can be compiled to WebAssembly, and exports a convenient set of functions to interact with the platform.

## What is Zigly?

Zigly is a library that makes it easy to write Compute@Edge modules in [Zig](https://ziglang.org).

Beyond the functions exported by the Fastly platform, Zigly will eventually include additional utility functions (cookie manipulation, JWT tokens, tracing...) to make application development as simple as possible.

## Usage

### A minimal WebAssembly program

```zig
const std = @import("std");

fn start() !void {
    std.debug.print("Hello from WebAssembly and Zig!\n", .{});
}

pub export fn _start() callconv(.C) void {
    start() catch unreachable;
}
```

The `_start()` function must have that exact type. It replaces the `main()` function.

The program can be compiled with (replace `example.zig` with the source file name):

```sh
zig build-exe -target wasm32-wasi example.zig
```

Happy with the result? Add `-O ReleaseSmall` or `-O ReleaseFast` to get very small or very fast module:

```sh
zig build-exe -target wasm32-wasi -O ReleaseSmall example.zig
```

The example above should not compile to more than 411 bytes.

If you are using a build file instead, define the target as `wasm32-wasi` in the `build.zig` file:

```zig
const target = try std.zig.CrossTarget.parse(.{ .arch_os_abi = "wasm32-wasi" });
```

...and build with `zig build -Drelease-small` or `-Drelease-fast` to get optimized modules.

### Testing Compute@Edge modules

The easiest way to test the resulting modules is currently to use [Fastlike](https://github.com/avidal/fastlike), a partial reimplementation of the Fastly API that runs locally, on any operating system supported by the Go language.

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

#### Inspecting incoming requests

Applications can read the body of an incoming requests as well as other informations such as the headers:

```zig
const request = downstream.request;
const user_agent = try request.headers.get(&allocator, "user-agent");
if (request.isPost()) {
    // method is POST, read the body until the end, up to 1000000 bytes
    const body = try request.body.readAll(&allocator, 1000000);
}
```

As usual in Zig, memory allocations are never hidden, and applications can choose the allocator they want to use for individual function calls.

#### Making HTTP queries

Making HTTP queries is easy:

```zig
var query = try Request.new("GET", "https://example.com");
var response = try query.send("backend");
const body = try response.body.readAll(&allocator, 0);
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
var query = try Request.new("GET", "https://google.com");
var upstream_response = try query.send("google.com");
var downstream = try zigly.downstream()
try downstream.response.pipe(&upstream_response, true, true);
```

#### Dictionaries

```zig
const dict = try Dictionary.open("name");
const value = try dict.get(&allocator, "key");
```

#### Logging

```zig
const logger = try Logger.open("endpoint);
try logger.write("Log entry");
```

## Deployment to Fastly's platform

The `fastly` command-line tool only supports Rust and AssemblyScript at the moment.
However, it can still be used to upload code written in other languages, including Zig.

1. Create a new project:

```sh
fastly compute init
```

In the following steps, we are going to assume that the project name is `zigmodule`.
For the language, select `rust` or `assemblyscript`, either will work.

2. Remove everything except the `fastly.toml` file.

3. Create a directory named `pkg/<your project name>`.

```sh
mkdir -p pkg/zigmodule
```

4. Copy (don't move) `fastly.toml` into this directory:

```sh
cp fastly.toml pkg/zigmodule/
```

5. Copy your WebAssembly module into a new `bin` directory inside the previous directory. The WebAssembly module must be named `main.wasm`.

```sh
mkdir -p pkg/zigmodule/bin
cp /tmp/z/zig-cache/bin/main.wasm pkg/zigmodule/bin/main.wasm
```

6. Archive the directory:

```sh
tar czv -C pkg -f pkg/zigmodule.tar.gz zigmodule
```

7. Deploy!

```sh
fastly compute deploy
```

In order to deploy new versions, bump the version number in `fastly.toml` and just type `fastly compute deploy` again.
