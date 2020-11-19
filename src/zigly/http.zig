const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;

const wasm = @import("wasm.zig");
const errors = @import("errors.zig");
const fastly = errors.fastly;
const FastlyError = errors.FastlyError;

const RequestHeaders = struct {
    handle: wasm.handle,

    /// Return the full list of header names.
    pub fn names(self: RequestHeaders, allocator: *Allocator) ![][]const u8 {
        var names_list = ArrayList([]const u8).init(allocator);
        var cursor: u32 = 0;
        var cursor_next: i64 = 0;
        while (true) {
            var name_len_max: usize = 64;
            var name_buf = try allocator.alloc(u8, name_len_max);
            var name_len: usize = undefined;
            while (true) {
                name_len = ~@as(usize, 0);
                const ret = fastly(wasm.mod_fastly_http_req.header_names_get(self.handle, @ptrCast([*]u8, name_buf), name_len_max, cursor, &cursor_next, &name_len));
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
            try names_list.append(name);
            if (cursor_next < 0) {
                break;
            }
            cursor = @intCast(u32, cursor_next);
        }
        return names_list.items;
    }

    /// Return the value for a header.
    pub fn get(self: RequestHeaders, allocator: *Allocator, name: []const u8) ![]const u8 {
        var value_len_max: usize = 64;
        var value_buf = try allocator.alloc(u8, value_len_max);
        var value_len: usize = undefined;
        while (true) {
            const ret = wasm.mod_fastly_http_req.header_value_get(self.handle, @ptrCast([*]const u8, name), name.len, @ptrCast([*]u8, value_buf), value_len_max, &value_len);
            if (ret) break else |err| {
                if (err != FastlyError.FastlyBufferTooSmall) {
                    return err;
                }
                value_len_max *= 2;
                value_buf = try allocator.realloc(name_buf, value_len_max);
            }
        }
        return value_buf[0..value_len];
    }

    /// Return all the values for a header.
    pub fn getAll(self: RequestHeaders, allocator: *Allocator, name: []const u8) ![][]const u8 {
        var values_list = ArrayList([]const u8).init(allocator);
        var cursor: u32 = 0;
        var cursor_next: i64 = 0;
        while (true) {
            var value_len_max: usize = 64;
            var value_buf = try allocator.alloc(u8, value_len_max);
            var value_len: usize = undefined;
            while (true) {
                value_len = ~@as(usize, 0);
                const ret = fastly(wasm.mod_fastly_http_req.header_values_get(self.handle, @ptrCast([*]const u8, name), name.len, @ptrCast([*]u8, value_buf), value_len_max, cursor, &cursor_next, &value_len));
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
            try values_list.append(value);
            if (cursor_next < 0) {
                break;
            }
            cursor = @intCast(u32, cursor_next);
        }
        return values_list.items;
    }

    /// Set the value for a header.
    pub fn set(self: *RequestHeaders, allocator: *Allocator, name: []const u8, value: []const u8) !void {
        var value0 = try allocator.alloc(u8, value.len + 1);
        mem.copy(u8, value0[0..value.len], value);
        value0[value.len] = 0;
        try fastly(wasm.mod_fastly_http_req.header_values_set(self.handle, @ptrCast([*]const u8, name), name.len, @ptrCast([*]const u8, value0), value0.len));
    }

    /// Append a value to a header.
    pub fn append(self: *RequestHeaders, allocator: *Allocator, name: []const u8, value: []const u8) !void {
        var value0 = try allocator.alloc(u8, value.len + 1);
        mem.copy(u8, value0[0..value.len], value);
        value0[value.len] = 0;
        try fastly(wasm.mod_fastly_http_req.header_append(self.handle, @ptrCast([*]const u8, name), name.len, @ptrCast([*]const u8, value0), value0.len));
    }

    /// Remove a header.
    pub fn remove(self: *RequestHeaders, name: []const u8) !void {
        try fastly(wasm.mod_fastly_http_req.header_remove(self.handle, @ptrCast([*]const u8, name), name.len));
    }
};

const IncomingBody = struct {
    handle: wasm.handle,

    /// Possibly partial read of the body content.
    /// An empty slice is returned when no data has to be read any more.
    pub fn read(self: *IncomingBody, buf: []u8) ![]u8 {
        var buf_len: usize = undefined;
        try fastly(wasm.mod_fastly_http_body.read(self.handle, @ptrCast([*]u8, buf), buf.len, &buf_len));
        return buf[0..buf_len];
    }

    /// Read all the body content. This requires an allocator.
    pub fn readAll(self: *IncomingBody, allocator: *Allocator) ![]u8 {
        const chunk_size: usize = 4096;
        var buf_len = chunk_size;
        var pos: usize = 0;
        var buf = try allocator.alloc(u8, buf_len);
        while (true) {
            var chunk = try self.read(buf[pos..]);
            if (chunk.len == 0) {
                return buf[0..pos];
            }
            pos += chunk.len;
            if (buf_len - pos <= chunk_size) {
                buf_len += chunk_size;
                buf = try allocator.realloc(buf, buf_len);
            }
        }
    }

    /// Close the body reader.
    pub fn close(self: *IncomingBody) !void {
        try fastly(wasm.mod_fastly_http_body.close(self.handle));
    }
};

const OutgoingBody = struct {
    handle: wasm.handle,

    /// Add body content. The number of bytes that could be written is returned.
    pub fn write(self: *OutgoingBody, buf: []const u8) !usize {
        var written: usize = undefined;
        try fastly(wasm.mod_fastly_http_body.write(self.handle, @ptrCast([*]const u8, buf), buf.len, wasm.body_write_end.BACK, &written));
        return written;
    }

    /// Add body content. The entire buffer is written.
    pub fn writeAll(self: *OutgoingBody, buf: []const u8) !void {
        var pos: usize = 0;
        while (pos < buf.len) {
            const written = try self.write(buf[pos..]);
            pos += written;
        }
    }

    /// Close the body writer.
    pub fn close(self: *OutgoingBody) !void {
        try fastly(wasm.mod_fastly_http_body.close(self.handle));
    }
};

/// An HTTP request.
pub const Request = struct {
    /// The request headers.
    headers: RequestHeaders,
    /// The request body.
    body: IncomingBody,

    /// Return the initial request made to the proxy.
    pub fn downstream() !Request {
        var req_handle: wasm.handle = undefined;
        var body_handle: wasm.handle = undefined;
        try fastly(wasm.mod_fastly_http_req.body_downstream_get(&req_handle, &body_handle));
        return Request{
            .headers = RequestHeaders{ .handle = req_handle },
            .body = IncomingBody{ .handle = body_handle },
        };
    }

    /// Copy the HTTP method used by this request.
    pub fn getMethod(self: Request, method: []u8) ![]u8 {
        var method_len: usize = undefined;
        try fastly(wasm.mod_fastly_http_req.method_get(self.headers.handle, @ptrCast([*]u8, method), method.len, &method_len));
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
        try fastly(wasm.mod_fastly_http_req.method_set(self.headers.handle, @ptrCast([*]const u8, method), method.len));
    }

    /// Get the request URI.
    pub fn getUri(self: Request, uri: []u8) ![]u8 {
        var uri_len: usize = undefined;
        try fastly(wasm.mod_fastly_http_req.uri_get(self.headers.handle, @ptrCast([*]u8, uri), uri.len, &uri_len));
        return uri[0..uri_len];
    }

    /// Set the request URI.
    pub fn setUri(self: Request, uri: []const u8) !void {
        try fastly(wasm.mod_fastly_http_req.uri_set(self.headers.handle, @ptrCast([*]const u8, uri), uri.len));
    }

    /// Create a new request.
    pub fn new(method: []const u8, uri: []const u8) !Request {
        var req_handle: wasm.handle = undefined;
        var body_handle: wasm.handle = undefined;
        try fastly(wasm.mod_fastly_http_req.new(&req_handle));
        try fastly(wasm.mod_fastly_http_body.new(&body_handle));

        var request = Request{
            .headers = RequestHeaders{ .handle = req_handle },
            .body = IncomingBody{ .handle = body_handle },
        };
        try request.setMethod(method);
        try request.setUri(uri);
        return request;
    }

    /// Send a request.
    pub fn send(self: *Request, backend: []const u8) !IncomingResponse {
        var resp_handle: wasm.handle = undefined;
        var resp_body_handle: wasm.handle = undefined;
        try fastly(wasm.mod_fastly_http_req.send(self.headers.handle, self.body.handle, @ptrCast([*]const u8, backend), backend.len, &resp_handle, &resp_body_handle));
        return IncomingResponse{
            .handle = resp_handle,
            .headers = ResponseHeaders{ .handle = resp_handle },
            .body = IncomingBody{ .handle = resp_body_handle },
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
        var wasm_policy: wasm.cache_override_tag = 0;
        if (policy.no_cache) {
            wasm_policy |= wasm.cache_override_tag_bits.PASS;
        }
        if (policy.ttl) |ttl| {
            wasm_policy |= wasm.cache_override_tag_bits.TTL;
        }
        if (policy.serve_stale) |_| {
            wasm_policy |= wasm.cache_override_tag_bits.STALE_WHILE_REVALIDATE;
        }
        if (policy.pci) {
            wasm_policy |= wasm.cache_override_tag_bits.PCI;
        }
        try fastly(wasm.mod_fastly_http_req.cache_override_v2_set(self.headers.handle, wasm_policy, policy.ttl orelse 0, policy.serve_stale orelse 0, @ptrCast([*]const u8, policy.surrogate_key), policy.surrogate_key.len));
    }
};

const ResponseHeaders = struct {
    handle: wasm.handle,

    /// Return the full list of header names.
    pub fn names(self: ResponseHeaders, allocator: *Allocator) ![][]const u8 {
        var names_list = ArrayList([]const u8).init(allocator);
        var cursor: u32 = 0;
        var cursor_next: i64 = 0;
        while (true) {
            var name_len_max: usize = 64;
            var name_buf = try allocator.alloc(u8, name_len_max);
            var name_len: usize = undefined;
            while (true) {
                name_len = ~@as(usize, 0);
                const ret = fastly(wasm.mod_fastly_http_resp.header_names_get(self.handle, @ptrCast([*]u8, name_buf), name_len_max, cursor, &cursor_next, &name_len));
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
            try names_list.append(name);
            if (cursor_next < 0) {
                break;
            }
            cursor = @intCast(u32, cursor_next);
        }
        return names_list.items;
    }

    /// Return the value for a header.
    pub fn get(self: ResponseHeaders, allocator: *Allocator, name: []const u8) ![]const u8 {
        var value_len_max: usize = 64;
        var value_buf = try allocator.alloc(u8, value_len_max);
        var value_len: usize = undefined;
        while (true) {
            const ret = wasm.mod_fastly_http_resp.header_value_get(self.handle, @ptrCast([*]const u8, name), name.len, @ptrCast([*]u8, value_buf), value_len_max, &value_len);
            if (ret) break else |err| {
                if (err != FastlyError.FastlyBufferTooSmall) {
                    return err;
                }
                value_len_max *= 2;
                value_buf = try allocator.realloc(name_buf, value_len_max);
            }
        }
        return value_buf[0..value_len];
    }

    /// Return all the values for a header.
    pub fn getAll(self: RequestHeaders, allocator: *Allocator, name: []const u8) ![][]const u8 {
        var values_list = ArrayList([]const u8).init(allocator);
        var cursor: u32 = 0;
        var cursor_next: i64 = 0;
        while (true) {
            var value_len_max: usize = 64;
            var value_buf = try allocator.alloc(u8, value_len_max);
            var value_len: usize = undefined;
            while (true) {
                value_len = ~@as(usize, 0);
                const ret = fastly(wasm.mod_fastly_http_resp.header_values_get(self.handle, @ptrCast([*]const u8, name), name.len, @ptrCast([*]u8, value_buf), value_len_max, cursor, &cursor_next, &value_len));
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
            try values_list.append(value);
            if (cursor_next < 0) {
                break;
            }
            cursor = @intCast(u32, cursor_next);
        }
        return values_list.items;
    }

    /// Set a header to a value.
    pub fn set(self: *ResponseHeaders, allocator: *Allocator, name: []const u8, value: []const u8) !void {
        var value0 = try allocator.alloc(u8, value.len + 1);
        mem.copy(u8, value0[0..value.len], value);
        value0[value.len] = 0;
        try fastly(wasm.mod_fastly_http_resp.header_values_set(self.handle, @ptrCast([*]const u8, name), name.len, @ptrCast([*]const u8, value0), value0.len));
    }

    /// Append a value to a header.
    pub fn append(self: *ResponseHeaders, allocator: *Allocator, name: []const u8, value: []const u8) !void {
        var value0 = try allocator.alloc(u8, value.len + 1);
        mem.copy(u8, value0[0..value.len], value);
        value0[value.len] = 0;
        try fastly(wasm.mod_fastly_http_resp.header_append(self.handle, @ptrCast([*]const u8, name), name.len, @ptrCast([*]const u8, value0), value0.len));
    }

    /// Remove a header.
    pub fn remove(self: *ResponseHeaders, name: []const u8) !void {
        try fastly(wasm.mod_fastly_http_resp.header_remove(self.handle, @ptrCast([*]const u8, name), name.len));
    }
};

const OutgoingResponse = struct {
    handle: wasm.handle,
    headers: ResponseHeaders,
    body: OutgoingBody,

    /// The response to the initial query sent to the proxy.
    pub fn downstream() !OutgoingResponse {
        var resp_handle: wasm.handle = undefined;
        var body_handle: wasm.handle = undefined;
        try fastly(wasm.mod_fastly_http_resp.new(&resp_handle));
        try fastly(wasm.mod_fastly_http_body.new(&body_handle));
        return OutgoingResponse{
            .handle = resp_handle,
            .headers = ResponseHeaders{ .handle = resp_handle },
            .body = OutgoingBody{ .handle = body_handle },
        };
    }

    /// Send a buffered response, but doesn't close the stream.
    pub fn flush(self: *OutgoingResponse) !void {
        try fastly(wasm.mod_fastly_http_resp.send_downstream(self.handle, self.body.handle, 1));
    }

    /// Send a buffered response and close the stream.
    pub fn finish(self: *OutgoingResponse) !void {
        try fastly(wasm.mod_fastly_http_resp.send_downstream(self.handle, self.body.handle, 0));
        try self.body.close();
    }

    /// Get a the status code of a response.
    pub fn getStatus(self: OutgoingResponse) !u16 {
        var status: wasm.http_status = undefined;
        try fastly(wasm.mod_fastly_http_resp.status_get(self.handle));
        return @intCast(u16, status);
    }

    /// Change the status code of a response.
    pub fn setStatus(self: *OutgoingResponse, status: u16) !void {
        try fastly(wasm.mod_fastly_http_resp.status_set(self.handle, @intCast(wasm.http_status, status)));
    }
};

const IncomingResponse = struct {
    handle: wasm.handle,
    headers: ResponseHeaders,
    body: IncomingBody,

    /// Get the status code of a response.
    pub fn getStatus(self: IncomingResponse) !u16 {
        var status: wasm.http_status = undefined;
        try fastly(wasm.mod_fastly_http_resp.status_get(self.handle));
        return @intCast(u16, status);
    }
};

const Downstream = struct {
    /// Initial request sent to the proxy.
    request: Request,
    /// Response to the initial request sent to the proxy.
    response: OutgoingResponse,
};

/// The initial connection to the proxy.
pub fn downstream() !Downstream {
    return Downstream{
        .request = try Request.downstream(),
        .response = try OutgoingResponse.downstream(),
    };
}
