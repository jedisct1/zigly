const std = @import("std");
const zigly = @import("zigly");

const Source = struct {
    backend: []const u8,
    host: []const u8,
    path: []const u8,
    title: []const u8,
};

const sources = [_]Source{
    .{ .backend = "source_a", .host = "example.com", .path = "/", .title = "Example Domain" },
    .{ .backend = "source_b", .host = "www.iana.org", .path = "/help/example-domains", .title = "IANA Example Domains" },
};

const max_body_bytes: usize = 256 * 1024;

pub fn main() !void {
    const allocator = std.heap.wasm_allocator;

    var downstream = try zigly.downstream();

    var fetched: [sources.len]struct {
        status: u16,
        body: []u8,
    } = undefined;

    for (sources, 0..) |source, i| {
        var url_buf: [512]u8 = undefined;
        const url = try std.fmt.bufPrint(&url_buf, "https://{s}{s}", .{ source.host, source.path });

        var req = try zigly.http.Request.new("GET", url);
        try req.headers.set("Host", source.host);
        try req.headers.set("User-Agent", "zigly-aggregator/0.1");
        try req.headers.set("Accept", "text/html,application/xhtml+xml");
        try req.setAutoDecompressResponse(true);

        var resp = req.send(source.backend) catch |err| {
            fetched[i] = .{
                .status = 0,
                .body = try std.fmt.allocPrint(allocator, "backend error: {s}", .{@errorName(err)}),
            };
            continue;
        };

        const status = try resp.getStatus();
        const body = try resp.body.readAll(allocator, max_body_bytes);
        fetched[i] = .{ .status = status, .body = body };
    }
    defer for (fetched) |f| allocator.free(f.body);

    try downstream.response.setStatus(200);
    try downstream.response.headers.set("Content-Type", "text/html; charset=utf-8");
    try downstream.response.headers.set("Cache-Control", "no-store");

    var out = &downstream.response.body;
    try out.writeAll(
        \\<!doctype html>
        \\<html lang="en">
        \\<head>
        \\<meta charset="utf-8">
        \\<title>Aggregated sources</title>
        \\<style>
        \\  body { font: 14px/1.5 system-ui, sans-serif; max-width: 60rem; margin: 2rem auto; padding: 0 1rem; color: #222; }
        \\  h1 { font-size: 1.4rem; }
        \\  section { border: 1px solid #ddd; border-radius: 6px; margin: 1.5rem 0; padding: 1rem 1.25rem; background: #fafafa; }
        \\  section header { display: flex; justify-content: space-between; align-items: baseline; gap: 1rem; margin-bottom: .75rem; }
        \\  section h2 { font-size: 1.1rem; margin: 0; }
        \\  .meta { color: #777; font-size: .85rem; }
        \\  .status-ok { color: #2a7a2a; }
        \\  .status-bad { color: #b04040; }
        \\  pre { white-space: pre-wrap; word-break: break-word; max-height: 24rem; overflow: auto; background: #fff; border: 1px solid #eee; padding: .75rem; border-radius: 4px; }
        \\</style>
        \\</head>
        \\<body>
        \\<h1>Aggregated sources</h1>
        \\<p>This page was assembled at the edge from the following upstreams:</p>
        \\
    );

    for (sources, fetched) |source, f| {
        const status_class = if (f.status >= 200 and f.status < 400) "status-ok" else "status-bad";
        var head_buf: [1024]u8 = undefined;
        const head = try std.fmt.bufPrint(&head_buf,
            \\<section>
            \\  <header>
            \\    <h2>{s}</h2>
            \\    <span class="meta">
            \\      <span class="{s}">HTTP {d}</span>
            \\      &middot; https://{s}{s}
            \\      &middot; {d} bytes
            \\    </span>
            \\  </header>
            \\  <pre>
        , .{ source.title, status_class, f.status, source.host, source.path, f.body.len });
        try out.writeAll(head);
        try writeHtmlEscaped(out, f.body);
        try out.writeAll("</pre>\n</section>\n");
    }

    try out.writeAll("</body></html>\n");
    try downstream.response.finish();
}

fn writeHtmlEscaped(body: *zigly.http.Body, input: []const u8) !void {
    var start: usize = 0;
    var i: usize = 0;
    while (i < input.len) : (i += 1) {
        const replacement: ?[]const u8 = switch (input[i]) {
            '<' => "&lt;",
            '>' => "&gt;",
            '&' => "&amp;",
            '"' => "&quot;",
            '\'' => "&#39;",
            else => null,
        };
        if (replacement) |r| {
            if (i > start) try body.writeAll(input[start..i]);
            try body.writeAll(r);
            start = i + 1;
        }
    }
    if (start < input.len) try body.writeAll(input[start..]);
}
