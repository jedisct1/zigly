const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;

const wasm = @import("wasm.zig");
const errors = @import("errors.zig");
const fastly = errors.fastly;
const FastlyError = errors.FastlyError;
const geo = @import("geo.zig");

const RequestHeaders = struct {
    handle: wasm.RequestHandle,

    /// Return the full list of header names.
    pub fn names(self: RequestHeaders, allocator: Allocator) ![][]const u8 {
        var names_list = ArrayList([]const u8){};
        var cursor: u32 = 0;
        var cursor_next: i64 = 0;
        while (true) {
            var name_len_max: usize = 64;
            var name_buf = try allocator.alloc(u8, name_len_max);
            var name_len: usize = undefined;
            while (true) {
                name_len = ~@as(usize, 0);
                const ret = fastly(wasm.FastlyHttpReq.header_names_get(self.handle, name_buf.ptr, name_len_max, cursor, &cursor_next, &name_len));
                var retry = name_len == ~@as(usize, 0);
                ret catch |err| {
                    if (err != FastlyError.FastlyBufferTooSmall) {
                        return err;
                    }
                    retry = true;
                };
                if (!retry) break;
                name_len_max *= 2;
                name_buf = try allocator.realloc(name_buf, name_len_max);
            }
            if (name_len == 0) {
                break;
            }
            if (name_buf[name_len - 1] != 0) {
                return FastlyError.FastlyGenericError;
            }
            const name = name_buf[0 .. name_len - 1];
            try names_list.append(allocator, name);
            if (cursor_next < 0) {
                break;
            }
            cursor = @as(u32, @intCast(cursor_next));
        }
        return names_list.items;
    }

    /// Return the value for a header.
    pub fn get(self: RequestHeaders, allocator: Allocator, name: []const u8) ![]const u8 {
        var value_len_max: usize = 64;
        var value_buf = try allocator.alloc(u8, value_len_max);
        var value_len: usize = undefined;
        while (true) {
            const ret = fastly(wasm.FastlyHttpReq.header_value_get(
                self.handle,
                name.ptr,
                name.len,
                value_buf.ptr,
                value_len_max,
                &value_len,
            ));
            if (ret) break else |err| {
                if (err != FastlyError.FastlyBufferTooSmall) {
                    return err;
                }
                value_len_max *= 2;
                value_buf = try allocator.realloc(value_buf, value_len_max);
            }
        }
        return value_buf[0..value_len];
    }

    /// Return all the values for a header.
    pub fn getAll(self: RequestHeaders, allocator: Allocator, name: []const u8) ![][]const u8 {
        var values_list = ArrayList([]const u8){};
        var cursor: u32 = 0;
        var cursor_next: i64 = 0;
        while (true) {
            var value_len_max: usize = 64;
            var value_buf = try allocator.alloc(u8, value_len_max);
            var value_len: usize = undefined;
            while (true) {
                value_len = ~@as(usize, 0);
                const ret = fastly(wasm.FastlyHttpReq.header_values_get(self.handle, name.ptr, name.len, value_buf.ptr, value_len_max, cursor, &cursor_next, &value_len));
                var retry = value_len == ~@as(usize, 0);
                ret catch |err| {
                    if (err != FastlyError.FastlyBufferTooSmall) {
                        return err;
                    }
                    retry = true;
                };
                if (!retry) break;
                value_len_max *= 2;
                value_buf = try allocator.realloc(value_buf, value_len_max);
            }
            if (value_len == 0) {
                break;
            }
            if (value_buf[value_len - 1] != 0) {
                return FastlyError.FastlyGenericError;
            }
            const value = value_buf[0 .. value_len - 1];
            try values_list.append(allocator, value);
            if (cursor_next < 0) {
                break;
            }
            cursor = @as(u32, @intCast(cursor_next));
        }
        return values_list.items;
    }

    /// Set the value for a header.
    pub fn set(self: *RequestHeaders, name: []const u8, value: []const u8) !void {
        try fastly(wasm.FastlyHttpReq.header_insert(self.handle, name.ptr, name.len, value.ptr, value.len));
    }

    /// Append a value to a header.
    pub fn append(self: *RequestHeaders, allocator: Allocator, name: []const u8, value: []const u8) !void {
        var value0 = try allocator.alloc(u8, value.len + 1);
        mem.copy(u8, value0[0..value.len], value);
        value0[value.len] = 0;
        try fastly(wasm.FastlyHttpReq.header_append(self.handle, name.ptr, name.len, value0.ptr, value0.len));
    }

    /// Remove a header.
    pub fn remove(self: *RequestHeaders, name: []const u8) !void {
        try fastly(wasm.FastlyHttpReq.header_remove(self.handle, name.ptr, name.len));
    }
};

const Body = struct {
    handle: wasm.BodyHandle,

    /// Possibly partial read of the body content.
    /// An empty slice is returned when no data has to be read any more.
    pub fn read(self: *Body, buf: []u8) ![]u8 {
        var buf_len: usize = undefined;
        try fastly(wasm.FastlyHttpBody.read(self.handle, buf.ptr, buf.len, &buf_len));
        return buf[0..buf_len];
    }

    /// Read all the body content. This requires an allocator.
    pub fn readAll(self: *Body, allocator: Allocator, max_length: usize) ![]u8 {
        const chunk_size: usize = std.heap.page_size_max;
        var buf_len = chunk_size;
        var pos: usize = 0;
        var buf = try allocator.alloc(u8, buf_len);
        while (true) {
            const chunk = try self.read(buf[pos..]);
            if (chunk.len == 0) {
                return buf[0..pos];
            }
            pos += chunk.len;
            if (max_length > 0 and pos >= max_length) {
                return buf[0..max_length];
            }
            if (buf_len - pos <= chunk_size) {
                buf_len += chunk_size;
                buf = try allocator.realloc(buf, buf_len);
            }
        }
    }

    /// Add body content. The number of bytes that could be written is returned.
    pub fn write(self: *Body, buf: []const u8) !usize {
        var written: usize = undefined;
        try fastly(wasm.FastlyHttpBody.write(self.handle, buf.ptr, buf.len, wasm.BodyWriteEnd.BACK, &written));
        return written;
    }

    /// Add body content. The entire buffer is written.
    pub fn writeAll(self: *Body, buf: []const u8) !void {
        var pos: usize = 0;
        while (pos < buf.len) {
            const written = try self.write(buf[pos..]);
            pos += written;
        }
    }

    /// Close the body.
    pub fn close(self: *Body) !void {
        try fastly(wasm.FastlyHttpBody.close(self.handle));
    }
};

/// An HTTP request.
pub const Request = struct {
    /// The request headers.
    headers: RequestHeaders,
    /// The request body.
    body: Body,

    /// Return the initial request made to the proxy.
    pub fn downstream() !Request {
        var req_handle: wasm.RequestHandle = undefined;
        var body_handle: wasm.BodyHandle = undefined;
        try fastly(wasm.FastlyHttpReq.body_downstream_get(&req_handle, &body_handle));
        return Request{
            .headers = RequestHeaders{ .handle = req_handle },
            .body = Body{ .handle = body_handle },
        };
    }

    /// Copy the HTTP method used by this request.
    pub fn getMethod(self: Request, method: []u8) ![]u8 {
        var method_len: usize = undefined;
        try fastly(wasm.FastlyHttpReq.method_get(self.headers.handle, method.ptr, method.len, &method_len));
        return method[0..method_len];
    }

    /// Return `true` if the request uses the `GET` method.
    pub fn isGet(self: Request) !bool {
        var method_buf: [64]u8 = undefined;
        const method = try self.getMethod(&method_buf);
        return mem.eql(u8, method, "GET");
    }

    /// Return `true` if the request uses the `POST` method.
    pub fn isPost(self: Request) !bool {
        var method_buf: [64]u8 = undefined;
        const method = try self.getMethod(&method_buf);
        return mem.eql(u8, method, "POST");
    }

    /// Set the method of a request.
    pub fn setMethod(self: Request, method: []const u8) !void {
        try fastly(wasm.FastlyHttpReq.method_set(self.headers.handle, method.ptr, method.len));
    }

    /// Get the request URI.
    /// `uri` is a buffer that should be large enough to store the URI.
    /// The function returns the slice containing the actual string.
    /// Individual components can be extracted with `Uri.parse()`.
    pub fn getUriString(self: Request, uri: []u8) ![]u8 {
        var uri_len: usize = undefined;
        try fastly(wasm.FastlyHttpReq.uri_get(self.headers.handle, uri.ptr, uri.len, &uri_len));
        return uri[0..uri_len];
    }

    /// Set the request URI.
    pub fn setUriString(self: Request, uri: []const u8) !void {
        try fastly(wasm.FastlyHttpReq.uri_set(self.headers.handle, uri.ptr, uri.len));
    }

    /// Create a new request.
    pub fn new(method: []const u8, uri: []const u8) !Request {
        var req_handle: wasm.RequestHandle = undefined;
        var body_handle: wasm.BodyHandle = undefined;
        try fastly(wasm.FastlyHttpReq.new(&req_handle));
        try fastly(wasm.FastlyHttpBody.new(&body_handle));

        var request = Request{
            .headers = RequestHeaders{ .handle = req_handle },
            .body = Body{ .handle = body_handle },
        };
        try request.setMethod(method);
        try request.setUriString(uri);
        return request;
    }

    /// Send a request.
    pub fn send(self: *Request, backend: []const u8) !IncomingResponse {
        var resp_handle: wasm.ResponseHandle = undefined;
        var resp_body_handle: wasm.BodyHandle = undefined;
        try fastly(wasm.FastlyHttpReq.send(self.headers.handle, self.body.handle, backend.ptr, backend.len, &resp_handle, &resp_body_handle));
        return IncomingResponse{
            .handle = resp_handle,
            .headers = ResponseHeaders{ .handle = resp_handle },
            .body = Body{ .handle = resp_body_handle },
        };
    }

    /// Caching policy
    pub const CachingPolicy = struct {
        /// Bypass the cache
        no_cache: bool = false,
        /// Enforce a sepcific TTL
        ttl: ?u32 = null,
        /// Return stale content up to this TTL if the origin is unreachable
        serve_stale: ?u32 = null,
        /// Activate PCI restrictions
        pci: bool = false,
        /// Cache with a surrogate key
        surrogate_key: []const u8 = "",
    };

    /// Force a caching policy for this request
    pub fn setCachingPolicy(self: *Request, policy: CachingPolicy) !void {
        var wasm_policy: wasm.CacheOverrideTag = 0;
        if (policy.no_cache) {
            wasm_policy |= wasm.CACHE_OVERRIDE_TAG_PASS;
        }
        if (policy.ttl) |_| {
            wasm_policy |= wasm.CACHE_OVERRIDE_TAG_TTL;
        }
        if (policy.serve_stale) |_| {
            wasm_policy |= wasm.CACHE_OVERRIDE_TAG_STALE_WHILE_REVALIDATE;
        }
        if (policy.pci) {
            wasm_policy |= wasm.CACHE_OVERRIDE_TAG_PCI;
        }
        try fastly(wasm.FastlyHttpReq.cache_override_v2_set(self.headers.handle, wasm_policy, policy.ttl orelse 0, policy.serve_stale orelse 0, policy.surrogate_key.ptr, policy.surrogate_key.len));
    }

    /// Automatically decompress the body of the request.
    pub fn setAutoDecompressResponse(self: *Request, enable: bool) !void {
        const encodings = if (enable) wasm.CONTENT_ENCODINGS_GZIP else 0;
        try fastly(wasm.FastlyHttpReq.auto_decompress_response_set(self.headers.handle, encodings));
    }

    /// Close the request prematurely.
    pub fn close(self: *Request) !void {
        try fastly(wasm.FastlyHttpReq.close(self.headers.handle));
    }
};

const ResponseHeaders = struct {
    handle: wasm.ResponseHandle,

    /// Return the full list of header names.
    pub fn names(self: ResponseHeaders, allocator: Allocator) ![][]const u8 {
        var names_list = ArrayList([]const u8){};
        var cursor: u32 = 0;
        var cursor_next: i64 = 0;
        while (true) {
            var name_len_max: usize = 64;
            var name_buf = try allocator.alloc(u8, name_len_max);
            var name_len: usize = undefined;
            while (true) {
                name_len = ~@as(usize, 0);
                const ret = fastly(wasm.FastlyHttpResp.header_names_get(self.handle, name_buf.ptr, name_len_max, cursor, &cursor_next, &name_len));
                var retry = name_len == ~@as(usize, 0);
                ret catch |err| {
                    if (err != FastlyError.FastlyBufferTooSmall) {
                        return err;
                    }
                    retry = true;
                };
                if (!retry) break;
                name_len_max *= 2;
                name_buf = try allocator.realloc(name_buf, name_len_max);
            }
            if (name_len == 0) {
                break;
            }
            if (name_buf[name_len - 1] != 0) {
                return FastlyError.FastlyGenericError;
            }
            const name = name_buf[0 .. name_len - 1];
            try names_list.append(allocator, name);
            if (cursor_next < 0) {
                break;
            }
            cursor = @as(u32, @intCast(cursor_next));
        }
        return names_list.items;
    }

    /// Return the value for a header.
    pub fn get(self: ResponseHeaders, allocator: Allocator, name: []const u8) ![]const u8 {
        var value_len_max: usize = 64;
        var value_buf = try allocator.alloc(u8, value_len_max);
        var value_len: usize = undefined;
        while (true) {
            const ret = wasm.FastlyHttpResp.header_value_get(self.handle, name.ptr, name.len, value_buf.ptr, value_len_max, &value_len);
            if (ret) break else |err| {
                if (err != FastlyError.FastlyBufferTooSmall) {
                    return err;
                }
                value_len_max *= 2;
                value_buf = try allocator.realloc(value_buf, value_len_max);
            }
        }
        return value_buf[0..value_len];
    }

    /// Return all the values for a header.
    pub fn getAll(self: RequestHeaders, allocator: Allocator, name: []const u8) ![][]const u8 {
        var values_list = ArrayList([]const u8){};
        var cursor: u32 = 0;
        var cursor_next: i64 = 0;
        while (true) {
            var value_len_max: usize = 64;
            var value_buf = try allocator.alloc(u8, value_len_max);
            var value_len: usize = undefined;
            while (true) {
                value_len = ~@as(usize, 0);
                const ret = fastly(wasm.FastlyHttpResp.header_values_get(self.handle, name.ptr, name.len, value_buf.ptr, value_len_max, cursor, &cursor_next, &value_len));
                var retry = value_len == ~@as(usize, 0);
                ret catch |err| {
                    if (err != FastlyError.FastlyBufferTooSmall) {
                        return err;
                    }
                    retry = true;
                };
                if (!retry) break;
                value_len_max *= 2;
                value_buf = try allocator.realloc(value_buf, value_len_max);
            }
            if (value_len == 0) {
                break;
            }
            if (value_buf[value_len - 1] != 0) {
                return FastlyError.FastlyGenericError;
            }
            const value = value_buf[0 .. value_len - 1];
            try values_list.append(allocator, value);
            if (cursor_next < 0) {
                break;
            }
            cursor = @as(u32, @intCast(cursor_next));
        }
        return values_list.items;
    }

    /// Set a header to a value.
    pub fn set(self: *ResponseHeaders, name: []const u8, value: []const u8) !void {
        try fastly(wasm.FastlyHttpResp.header_insert(self.handle, name.ptr, name.len, value.ptr, value.len));
    }

    /// Append a value to a header.
    pub fn append(self: *ResponseHeaders, allocator: Allocator, name: []const u8, value: []const u8) !void {
        var value0 = try allocator.alloc(u8, value.len + 1);
        mem.copy(u8, value0[0..value.len], value);
        value0[value.len] = 0;
        try fastly(wasm.FastlyHttpResp.header_append(self.handle, name.ptr, name.len, value0.ptr, value0.len));
    }

    /// Remove a header.
    pub fn remove(self: *ResponseHeaders, name: []const u8) !void {
        try fastly(wasm.FastlyHttpResp.header_remove(self.handle, name.ptr, name.len));
    }
};

const OutgoingResponse = struct {
    handle: wasm.ResponseHandle,
    headers: ResponseHeaders,
    body: Body,

    /// The response to the initial query sent to the proxy.
    pub fn downstream() !OutgoingResponse {
        var resp_handle: wasm.ResponseHandle = undefined;
        var body_handle: wasm.BodyHandle = undefined;
        try fastly(wasm.FastlyHttpResp.new(&resp_handle));
        try fastly(wasm.FastlyHttpBody.new(&body_handle));
        return OutgoingResponse{
            .handle = resp_handle,
            .headers = ResponseHeaders{ .handle = resp_handle },
            .body = Body{ .handle = body_handle },
        };
    }

    /// Send a buffered response, but don't close the stream.
    /// Either call `finish` or `body.close` at the end of the response.
    pub fn flush(self: *OutgoingResponse) !void {
        try fastly(wasm.FastlyHttpResp.send_downstream(self.handle, self.body.handle, 1));
    }

    /// Send an unbuffered response and close the stream.
    pub fn finish(self: *OutgoingResponse) !void {
        try fastly(wasm.FastlyHttpResp.send_downstream(self.handle, self.body.handle, 0));
    }

    /// Get a the status code of a response.
    pub fn getStatus(self: OutgoingResponse) !u16 {
        var status: wasm.HttpStatus = undefined;
        try fastly(wasm.FastlyHttpResp.status_get(self.handle, &status));
        return @as(u16, @intCast(status));
    }

    /// Change the status code of a response.
    pub fn setStatus(self: *OutgoingResponse, status: u16) !void {
        try fastly(wasm.FastlyHttpResp.status_set(self.handle, @as(wasm.HttpStatus, @intCast(status))));
    }

    /// Zero-copy the content of an incoming response.
    /// The status from the incoming response is copied if `copy_status` is set to `true`,
    /// and the headers are copied if `copy_headers` is set to `true`.
    pub fn pipe(self: *OutgoingResponse, incoming: *IncomingResponse, copy_status: bool, copy_headers: bool) !void {
        if (copy_status) {
            try self.setStatus(try incoming.getStatus());
        }
        try fastly(wasm.FastlyHttpResp.send_downstream(if (copy_headers) incoming.handle else self.handle, incoming.body.handle, 0));
    }

    /// Prematurely close the response without sending potentially buffered data.
    pub fn cancel(self: *Request) !void {
        try fastly(wasm.FastlyHttpResp.close(self.handle));
    }
};

pub const IncomingResponse = struct {
    handle: wasm.ResponseHandle,
    headers: ResponseHeaders,
    body: Body,

    /// Get the status code of a response.
    pub fn getStatus(self: IncomingResponse) !u16 {
        var status: wasm.HttpStatus = undefined;
        try fastly(wasm.FastlyHttpResp.status_get(self.handle, &status));
        return @as(u16, @intCast(status));
    }

    /// Close the response after use.
    pub fn close(self: *IncomingResponse) !void {
        try fastly(wasm.FastlyHttpResp.close(self.handle));
    }
};

pub const Downstream = struct {
    /// Initial request sent to the proxy.
    request: Request,
    /// Response to the initial request sent to the proxy.
    response: OutgoingResponse,

    /// Redirect to a different URI, with the given status code (usually 301 or 302)
    pub fn redirect(self: *Downstream, status: u16, uri: []const u8) !void {
        var response = self.response;
        try response.setStatus(status);
        try response.headers.set("Location", uri);
        try response.finish();
    }

    /// Proxy the request and its response to the origin, optionally changing the Host header field
    pub fn proxy(self: *Downstream, backend: []const u8, host_header: ?[]const u8) !void {
        if (host_header) |host| {
            try self.request.headers.set("Host", host);
        }
        try fastly(wasm.FastlyHttpReq.send(self.request.headers.handle, self.request.body.handle, backend.ptr, backend.len, &self.response.handle, &self.response.body.handle));
        try self.response.finish();
    }

    /// Get the downstream client IP address
    pub fn getClientIpAddr() !geo.Ip {
        var ip = [_]u8{0} ** 16;
        var count: usize = 0;

        try fastly(wasm.FastlyHttpReq.downstream_client_ip_addr(&ip, &count));

        if (count == 16) {
            return geo.Ip{ .ip16 = ip };
        }

        var ipv4 = [_]u8{0} ** 4;
        std.mem.copyForwards(u8, ipv4[0..], ip[0..4]);

        return geo.Ip{ .ip4 = ipv4 };
    }
};

/// The initial connection to the proxy.
pub fn downstream() !Downstream {
    return Downstream{
        .request = try Request.downstream(),
        .response = try OutgoingResponse.downstream(),
    };
}
