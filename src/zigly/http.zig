const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;

const wasm = @import("wasm.zig");
const errors = @import("errors.zig");
const fastly = errors.fastly;
const FastlyError = errors.FastlyError;
const geo = @import("geo.zig");
const logger = @import("logger.zig");

/// URL decode a string for query parameters, handling both percent-encoding and '+' for spaces.
/// The returned string is owned by the allocator.
/// Note: This handles '+' to space conversion which std.Uri.percentDecode does not,
/// as that's specific to application/x-www-form-urlencoded format.
fn urlDecode(allocator: Allocator, encoded: []const u8) ![]u8 {
    // First pass: replace '+' with spaces
    var buffer = try allocator.alloc(u8, encoded.len);
    for (encoded, 0..) |c, i| {
        buffer[i] = if (c == '+') ' ' else c;
    }

    // Second pass: use std.Uri.percentDecodeInPlace for percent-encoding
    const decoded = std.Uri.percentDecodeInPlace(buffer);

    // Resize to actual decoded length if needed
    if (decoded.len < buffer.len) {
        return allocator.realloc(buffer, decoded.len);
    }
    return decoded;
}

const RequestHeaders = struct {
    handle: wasm.RequestHandle,

    /// Return the full list of header names.
    pub fn names(self: RequestHeaders, allocator: Allocator) ![][]const u8 {
        var names_list = ArrayList([]const u8).empty;
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
        var values_list = ArrayList([]const u8).empty;
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
        @memcpy(value0[0..value.len], value);
        value0[value.len] = 0;
        try fastly(wasm.FastlyHttpReq.header_append(self.handle, name.ptr, name.len, value0.ptr, value0.len));
    }

    /// Remove a header.
    pub fn remove(self: *RequestHeaders, name: []const u8) !void {
        try fastly(wasm.FastlyHttpReq.header_remove(self.handle, name.ptr, name.len));
    }
};

pub const Body = struct {
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

    /// Move the entire content of another body to the end of this one,
    /// without copying it through guest memory. The other body is consumed.
    pub fn append(self: *Body, other: Body) !void {
        try fastly(wasm.FastlyHttpBody.append(self.handle, other.handle));
    }

    /// Close the body.
    pub fn close(self: *Body) !void {
        try fastly(wasm.FastlyHttpBody.close(self.handle));
    }

    /// Return a buffered `std.Io.Writer` backed by this body.
    ///
    /// The caller provides the backing buffer. Small writes accumulate in the
    /// buffer and only reach the Fastly `body_write` hostcall when the buffer
    /// fills up or `flush` is called, turning many tiny writes into a few
    /// large ones. Call `flush` before sending the response.
    pub fn writer(self: *Body, buf: []u8) BufferedWriter {
        return BufferedWriter.init(self, buf);
    }
};

/// Buffered `std.Io.Writer` for a `Body`. Constructed via `Body.writer`.
pub const BufferedWriter = struct {
    body: *Body,
    interface: std.Io.Writer,

    pub fn init(body: *Body, buf: []u8) BufferedWriter {
        return .{
            .body = body,
            .interface = .{
                .buffer = buf,
                .vtable = &.{ .drain = drain },
            },
        };
    }

    /// Flush any buffered bytes through to the Fastly body.
    pub fn flush(self: *BufferedWriter) !void {
        self.interface.flush() catch return FastlyError.FastlyGenericError;
    }

    fn drain(io_w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        const self: *BufferedWriter = @alignCast(@fieldParentPtr("interface", io_w));
        const buffered = io_w.buffered();
        if (buffered.len != 0) {
            self.body.writeAll(buffered) catch return error.WriteFailed;
            io_w.end = 0;
        }
        var written: usize = 0;
        for (data[0 .. data.len - 1]) |slice| {
            if (slice.len == 0) continue;
            self.body.writeAll(slice) catch return error.WriteFailed;
            written += slice.len;
        }
        const pattern = data[data.len - 1];
        if (pattern.len != 0) {
            var i: usize = 0;
            while (i < splat) : (i += 1) {
                self.body.writeAll(pattern) catch return error.WriteFailed;
                written += pattern.len;
            }
        }
        return written;
    }
};

/// An HTTP request.
/// Category of a detected bot, returned by `Request.botCategoryKind`.
/// Non-exhaustive: the platform may add new categories, which arrive as values not listed here.
pub const BotCategoryKind = enum(u32) {
    none = 0,
    suspected = 1,
    accessibility = 2,
    ai_crawler = 3,
    ai_fetcher = 4,
    content_fetcher = 5,
    monitoring_site_tools = 6,
    online_marketing = 7,
    page_preview = 8,
    platform_integrations = 9,
    research = 10,
    search_engine_crawler = 11,
    search_engine_optimization = 12,
    security_tools = 13,
    _,
};

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

    /// Parse the request URI into a std.Uri struct.
    /// Returns a Uri with all components (scheme, host, path, query, etc.).
    /// The Uri's slices point into the provided buffer.
    pub fn getUri(self: Request, uri_buf: []u8) !std.Uri {
        const uri_str = try self.getUriString(uri_buf);
        return std.Uri.parse(uri_str) catch {
            // If parsing fails (e.g., no scheme), treat as path-only
            return std.Uri{
                .scheme = "",
                .path = .{ .percent_encoded = uri_str },
            };
        };
    }

    /// Extract the path from the request URI.
    /// Returns just the path portion without query string or fragment.
    /// Example: "https://example.com/api/users?id=1" returns "/api/users"
    pub fn getPath(self: Request, uri_buf: []u8) ![]const u8 {
        const uri = try self.getUri(uri_buf);
        return switch (uri.path) {
            .raw => |raw| raw,
            .percent_encoded => |encoded| encoded,
        };
    }

    /// Extract the path and query string from the request URI.
    /// Returns path with query string but without fragment.
    /// Example: "https://example.com/api/users?id=1#section" returns "/api/users?id=1"
    pub fn getPathAndQuery(self: Request, uri_buf: []u8, out_buf: []u8) ![]const u8 {
        const uri = try self.getUri(uri_buf);
        const path = switch (uri.path) {
            .raw => |raw| raw,
            .percent_encoded => |encoded| encoded,
        };

        if (uri.query) |query| {
            const query_str = switch (query) {
                .raw => |raw| raw,
                .percent_encoded => |encoded| encoded,
            };
            const total_len = path.len + 1 + query_str.len;
            if (total_len > out_buf.len) return FastlyError.FastlyBufferTooSmall;
            @memcpy(out_buf[0..path.len], path);
            out_buf[path.len] = '?';
            @memcpy(out_buf[path.len + 1 ..][0..query_str.len], query_str);
            return out_buf[0..total_len];
        }
        return path;
    }

    /// Set the request URI.
    pub fn setUriString(self: Request, uri: []const u8) !void {
        try fastly(wasm.FastlyHttpReq.uri_set(self.headers.handle, uri.ptr, uri.len));
    }

    /// Represents a query parameter key-value pair
    pub const QueryParam = struct {
        key: []const u8,
        value: []const u8,
    };

    /// Parse query parameters from the request URI into key-value pairs.
    /// The returned slices point to memory owned by the allocator.
    pub fn parseQueryParams(self: Request, allocator: Allocator) ![]QueryParam {
        var uri_buf: [8192]u8 = undefined;
        const uri = try self.getUriString(&uri_buf);

        // Find the query string part (after '?')
        const query_start_idx = mem.indexOfScalar(u8, uri, '?') orelse return &[_]QueryParam{};
        const query_string = uri[query_start_idx + 1 ..];

        if (query_string.len == 0) {
            return &[_]QueryParam{};
        }

        // Count the number of parameters (separated by '&')
        var param_count: usize = 1;
        for (query_string) |c| {
            if (c == '&') {
                param_count += 1;
            }
        }

        // Allocate array for parameters
        var params = try allocator.alloc(QueryParam, param_count);
        var param_idx: usize = 0;

        // Split by '&' and parse each key-value pair
        var iter = mem.tokenizeScalar(u8, query_string, '&');
        while (iter.next()) |param| {
            if (param.len == 0) continue;

            // Split by '=' to get key and value
            if (mem.indexOfScalar(u8, param, '=')) |eq_idx| {
                const key = param[0..eq_idx];
                const value = param[eq_idx + 1 ..];

                // URL decode the key and value
                const decoded_key = try urlDecode(allocator, key);
                const decoded_value = try urlDecode(allocator, value);

                params[param_idx] = QueryParam{
                    .key = decoded_key,
                    .value = decoded_value,
                };
            } else {
                // No '=' found, treat as key with empty value
                const decoded_key = try urlDecode(allocator, param);
                params[param_idx] = QueryParam{
                    .key = decoded_key,
                    .value = try allocator.dupe(u8, ""),
                };
            }
            param_idx += 1;
        }

        // Return only the filled portion of the array
        return params[0..param_idx];
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
        return IncomingResponse.fromHandles(resp_handle, resp_body_handle);
    }

    /// Send the request without waiting for the response, so that several
    /// requests can be in flight at the same time.
    /// The response is later retrieved with `PendingRequest.wait`,
    /// `PendingRequest.poll` or `PendingRequest.select`.
    pub fn sendAsync(self: *Request, backend: []const u8) !PendingRequest {
        var pending_handle: wasm.PendingRequestHandle = undefined;
        try fastly(wasm.FastlyHttpReq.send_async(self.headers.handle, self.body.handle, backend.ptr, backend.len, &pending_handle));
        return PendingRequest{ .handle = pending_handle };
    }

    /// Send the request headers right away, leaving the body open for
    /// streaming: keep writing to `self.body` and call `self.body.close()`
    /// to complete the request. The response is retrieved from the returned
    /// pending request, just like with `sendAsync`.
    pub fn sendAsyncStreaming(self: *Request, backend: []const u8) !PendingRequest {
        var pending_handle: wasm.PendingRequestHandle = undefined;
        try fastly(wasm.FastlyHttpReq.send_async_streaming(self.headers.handle, self.body.handle, backend.ptr, backend.len, &pending_handle));
        return PendingRequest{ .handle = pending_handle };
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

    /// Log the HTTP request in Apache combined log format.
    /// Format: %h %l %u %t "%r" %>s %b "%{Referer}i" "%{User-Agent}i"
    /// Note: Response status and size must be provided. Use 0 for size if unknown.
    pub fn logApacheCombined(self: Request, allocator: Allocator, endpoint_name: []const u8, status: u16, response_size: usize) !void {
        var log_endpoint = try logger.Logger.open(endpoint_name);

        // Get client IP address
        const client_ip = Downstream.getClientIpAddr() catch blk: {
            break :blk geo.Ip{ .ip4 = .{ 0, 0, 0, 0 } };
        };

        var ip_str: [40]u8 = undefined;
        const ip_formatted = if (client_ip == .ip4)
            try std.fmt.bufPrint(&ip_str, "{}.{}.{}.{}", .{ client_ip.ip4[0], client_ip.ip4[1], client_ip.ip4[2], client_ip.ip4[3] })
        else
            try std.fmt.bufPrint(&ip_str, "{x:0>4}:{x:0>4}:{x:0>4}:{x:0>4}:{x:0>4}:{x:0>4}:{x:0>4}:{x:0>4}", .{
                (@as(u16, client_ip.ip16[0]) << 8) | client_ip.ip16[1],
                (@as(u16, client_ip.ip16[2]) << 8) | client_ip.ip16[3],
                (@as(u16, client_ip.ip16[4]) << 8) | client_ip.ip16[5],
                (@as(u16, client_ip.ip16[6]) << 8) | client_ip.ip16[7],
                (@as(u16, client_ip.ip16[8]) << 8) | client_ip.ip16[9],
                (@as(u16, client_ip.ip16[10]) << 8) | client_ip.ip16[11],
                (@as(u16, client_ip.ip16[12]) << 8) | client_ip.ip16[13],
                (@as(u16, client_ip.ip16[14]) << 8) | client_ip.ip16[15],
            });

        // Get method and URI for request line
        var method_buf: [64]u8 = undefined;
        const method = try self.getMethod(&method_buf);

        var uri_buf: [8192]u8 = undefined;
        const uri = try self.getUriString(&uri_buf);

        // Get headers we need
        const user_agent = self.headers.get(allocator, "User-Agent") catch blk: {
            break :blk try allocator.dupe(u8, "-");
        };
        defer allocator.free(user_agent);

        const referer = self.headers.get(allocator, "Referer") catch blk: {
            break :blk try allocator.dupe(u8, "-");
        };
        defer allocator.free(referer);

        // Format timestamp as [day/month/year:hour:minute:second +0000]
        var timestamp_ns: std.os.wasi.timestamp_t = undefined;
        const rc = std.os.wasi.clock_time_get(.REALTIME, 1, &timestamp_ns);
        if (rc != .SUCCESS) return FastlyError.FastlyGenericError;
        const epoch_seconds: u64 = timestamp_ns / std.time.ns_per_s;
        const epoch = std.time.epoch.EpochSeconds{ .secs = epoch_seconds };
        const day_seconds = epoch.getDaySeconds();
        const year_day = epoch.getEpochDay().calculateYearDay();
        const month_day = year_day.calculateMonthDay();

        const hours = day_seconds.getHoursIntoDay();
        const minutes = day_seconds.getMinutesIntoHour();
        const seconds = day_seconds.getSecondsIntoMinute();

        const month_names = [_][]const u8{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };
        const month_name = month_names[@intFromEnum(month_day.month) - 1];

        var timestamp_buf: [32]u8 = undefined;
        const timestamp = try std.fmt.bufPrint(&timestamp_buf, "[{d:0>2}/{s}/{d:0>4}:{d:0>2}:{d:0>2}:{d:0>2} +0000]", .{
            month_day.day_index + 1,
            month_name,
            year_day.year,
            hours,
            minutes,
            seconds,
        });

        // Format response size (- if zero)
        var size_buf: [32]u8 = undefined;
        const size_str = if (response_size == 0)
            "-"
        else
            try std.fmt.bufPrint(&size_buf, "{d}", .{response_size});

        // Build the Apache combined log format line
        const log_msg = try std.fmt.allocPrint(allocator, "{s} - - {s} \"{s} {s} HTTP/1.1\" {d} {s} \"{s}\" \"{s}\"", .{
            ip_formatted,
            timestamp,
            method,
            uri,
            status,
            size_str,
            referer,
            user_agent,
        });
        defer allocator.free(log_msg);

        try log_endpoint.write(log_msg);
    }

    /// Close the request prematurely.
    pub fn close(self: *Request) !void {
        try fastly(wasm.FastlyHttpReq.close(self.headers.handle));
    }

    fn downstreamFlag(self: Request, comptime hostcall: anytype) !bool {
        var value: u32 = undefined;
        try fastly(hostcall(self.headers.handle, &value));
        return value != 0;
    }

    fn downstreamString(self: Request, comptime hostcall: anytype, buf: []u8) ![]const u8 {
        var len: usize = undefined;
        try fastly(hostcall(self.headers.handle, buf.ptr, buf.len, &len));
        return buf[0..len];
    }

    /// Whether bot analysis was performed on this request.
    pub fn botAnalyzed(self: Request) !bool {
        return self.downstreamFlag(wasm.FastlyHttpDownstream.downstream_bot_analyzed);
    }

    /// Whether the client was detected as a bot.
    pub fn botDetected(self: Request) !bool {
        return self.downstreamFlag(wasm.FastlyHttpDownstream.downstream_bot_detected);
    }

    /// Whether the detected bot was verified (e.g. a known, well-behaved crawler).
    pub fn botVerified(self: Request) !bool {
        return self.downstreamFlag(wasm.FastlyHttpDownstream.downstream_bot_verified);
    }

    /// The category kind of the detected bot.
    pub fn botCategoryKind(self: Request) !BotCategoryKind {
        var value: wasm.BotCategoryKind = undefined;
        try fastly(wasm.FastlyHttpDownstream.downstream_bot_category_kind(self.headers.handle, &value));
        return @enumFromInt(value);
    }

    /// Copy the name of the detected bot into `buf` and return the written slice.
    pub fn botName(self: Request, buf: []u8) ![]const u8 {
        return self.downstreamString(wasm.FastlyHttpDownstream.downstream_bot_name, buf);
    }

    /// Copy the category of the detected bot into `buf` and return the written slice.
    pub fn botCategory(self: Request, buf: []u8) ![]const u8 {
        return self.downstreamString(wasm.FastlyHttpDownstream.downstream_bot_category, buf);
    }

    /// Whether the client is connecting through an anonymizing service.
    pub fn isAnonymous(self: Request) !bool {
        return self.downstreamFlag(wasm.FastlyHttpDownstream.downstream_resvpnproxy_is_anonymous);
    }

    /// Whether the client is connecting through an anonymous VPN.
    pub fn isAnonymousVpn(self: Request) !bool {
        return self.downstreamFlag(wasm.FastlyHttpDownstream.downstream_resvpnproxy_is_anonymous_vpn);
    }

    /// Whether the client address belongs to a hosting provider.
    pub fn isHostingProvider(self: Request) !bool {
        return self.downstreamFlag(wasm.FastlyHttpDownstream.downstream_resvpnproxy_is_hosting_provider);
    }

    /// Whether the client is connecting through a proxy over a VPN.
    pub fn isProxyOverVpn(self: Request) !bool {
        return self.downstreamFlag(wasm.FastlyHttpDownstream.downstream_resvpnproxy_is_proxy_over_vpn);
    }

    /// Whether the client is connecting through a public proxy.
    pub fn isPublicProxy(self: Request) !bool {
        return self.downstreamFlag(wasm.FastlyHttpDownstream.downstream_resvpnproxy_is_public_proxy);
    }

    /// Whether the client is connecting through a relay proxy.
    pub fn isRelayProxy(self: Request) !bool {
        return self.downstreamFlag(wasm.FastlyHttpDownstream.downstream_resvpnproxy_is_relay_proxy);
    }

    /// Whether the client is connecting through a residential proxy.
    pub fn isResidentialProxy(self: Request) !bool {
        return self.downstreamFlag(wasm.FastlyHttpDownstream.downstream_resvpnproxy_is_residential_proxy);
    }

    /// Whether the client is connecting through a smart DNS proxy.
    pub fn isSmartDnsProxy(self: Request) !bool {
        return self.downstreamFlag(wasm.FastlyHttpDownstream.downstream_resvpnproxy_is_smart_dns_proxy);
    }

    /// Whether the client address is a Tor exit node.
    pub fn isTorExitNode(self: Request) !bool {
        return self.downstreamFlag(wasm.FastlyHttpDownstream.downstream_resvpnproxy_is_tor_exit_node);
    }

    /// Whether the client address belongs to a VPN datacenter.
    pub fn isVpnDatacenter(self: Request) !bool {
        return self.downstreamFlag(wasm.FastlyHttpDownstream.downstream_resvpnproxy_is_vpn_datacenter);
    }

    /// Copy the name of the VPN service the client is using into `buf` and return the written slice.
    pub fn vpnServiceName(self: Request, buf: []u8) ![]const u8 {
        return self.downstreamString(wasm.FastlyHttpDownstream.downstream_resvpnproxy_vpn_service_name, buf);
    }
};

/// A backend request sent with `Request.sendAsync` or
/// `Request.sendAsyncStreaming`, whose response may not have arrived yet.
/// This is an extern struct so that a slice of pending requests can be
/// passed directly to the `select` hostcall as an array of handles.
pub const PendingRequest = extern struct {
    handle: wasm.PendingRequestHandle,

    /// Block until the response arrives, then return it.
    /// The pending request is consumed and must not be used afterwards.
    pub fn wait(self: PendingRequest) !IncomingResponse {
        var detail = std.mem.zeroes(wasm.SendErrorDetail);
        var resp_handle: wasm.ResponseHandle = undefined;
        var resp_body_handle: wasm.BodyHandle = undefined;
        try fastly(wasm.FastlyHttpReq.pending_req_wait_v2(self.handle, &detail, &resp_handle, &resp_body_handle));
        return IncomingResponse.fromHandles(resp_handle, resp_body_handle);
    }

    /// Return the response if it has arrived, or `null` if it is still pending.
    /// Once a response has been returned, the pending request is consumed
    /// and must not be used afterwards.
    pub fn poll(self: PendingRequest) !?IncomingResponse {
        var detail = std.mem.zeroes(wasm.SendErrorDetail);
        var is_done: wasm.IsDone = undefined;
        var resp_handle: wasm.ResponseHandle = undefined;
        var resp_body_handle: wasm.BodyHandle = undefined;
        try fastly(wasm.FastlyHttpReq.pending_req_poll_v2(self.handle, &detail, &is_done, &resp_handle, &resp_body_handle));
        if (is_done == 0) {
            return null;
        }
        return IncomingResponse.fromHandles(resp_handle, resp_body_handle);
    }

    /// Return `true` if the response has arrived, i.e. if `wait` would return
    /// without blocking. Unlike `poll`, this does not consume the pending
    /// request.
    pub fn isReady(self: PendingRequest) !bool {
        var ready: wasm.IsDone = undefined;
        try fastly(wasm.FastlyAsyncIo.is_ready(self.handle, &ready));
        return ready != 0;
    }

    /// The response of the first pending request that completed during a
    /// `select` call, along with its position in the slice that was passed in.
    pub const Selected = struct {
        index: usize,
        response: IncomingResponse,
    };

    /// Block until one of the pending requests completes, and return its
    /// response along with its index. The winning entry is consumed; the
    /// others remain pending and can be waited on or selected again.
    pub fn select(pending: []const PendingRequest) !Selected {
        comptime std.debug.assert(@sizeOf(PendingRequest) == @sizeOf(wasm.PendingRequestHandle));
        if (pending.len == 0) {
            return FastlyError.FastlyInvalidValue;
        }
        var detail = std.mem.zeroes(wasm.SendErrorDetail);
        var done_idx: wasm.DoneIdx = undefined;
        var resp_handle: wasm.ResponseHandle = undefined;
        var resp_body_handle: wasm.BodyHandle = undefined;
        try fastly(wasm.FastlyHttpReq.pending_req_select_v2(@ptrCast(pending.ptr), pending.len, &detail, &done_idx, &resp_handle, &resp_body_handle));
        return Selected{
            .index = done_idx,
            .response = IncomingResponse.fromHandles(resp_handle, resp_body_handle),
        };
    }

    /// Iterator over a set of pending requests that returns each response as
    /// it arrives, in completion order. Constructed with `iterator`.
    pub const Iterator = struct {
        live: []PendingRequest,

        /// Return the next response to complete, or `null` once all pending
        /// requests have been consumed.
        pub fn next(self: *Iterator) !?IncomingResponse {
            if (self.live.len == 0) {
                return null;
            }
            const selected = try select(self.live);
            self.live[selected.index] = self.live[self.live.len - 1];
            self.live = self.live[0 .. self.live.len - 1];
            return selected.response;
        }
    };

    /// Return an iterator that yields the response of each pending request as
    /// it arrives, in completion order rather than in the order the requests
    /// were sent. The slice is reordered in place as entries are consumed.
    pub fn iterator(pending: []PendingRequest) Iterator {
        return Iterator{ .live = pending };
    }
};

const ResponseHeaders = struct {
    handle: wasm.ResponseHandle,

    /// Return the full list of header names.
    pub fn names(self: ResponseHeaders, allocator: Allocator) ![][]const u8 {
        var names_list = ArrayList([]const u8).empty;
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
            const ret = fastly(wasm.FastlyHttpResp.header_value_get(self.handle, name.ptr, name.len, value_buf.ptr, value_len_max, &value_len));
            if (ret) {
                break;
            } else |err| {
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
    pub fn getAll(self: ResponseHeaders, allocator: Allocator, name: []const u8) ![][]const u8 {
        var values_list = ArrayList([]const u8).empty;
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
        @memcpy(value0[0..value.len], value);
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

    /// Choose whether response framing headers are inferred or taken from response headers.
    pub fn setManualFramingMode(self: *OutgoingResponse, manual: bool) !void {
        const mode = if (manual) wasm.FramingHeadersMode.MANUALLY_FROM_HEADERS else wasm.FramingHeadersMode.AUTOMATIC;
        try fastly(wasm.FastlyHttpResp.framing_headers_mode_set(self.handle, mode));
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

    fn fromHandles(resp_handle: wasm.ResponseHandle, body_handle: wasm.BodyHandle) IncomingResponse {
        return IncomingResponse{
            .handle = resp_handle,
            .headers = ResponseHeaders{ .handle = resp_handle },
            .body = Body{ .handle = body_handle },
        };
    }

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
        var ip: [16]u8 = @splat(0);
        var count: usize = 0;

        try fastly(wasm.FastlyHttpReq.downstream_client_ip_addr(&ip, &count));

        if (count == 16) {
            return geo.Ip{ .ip16 = ip };
        }

        var ipv4: [4]u8 = @splat(0);
        std.mem.copyForwards(u8, ipv4[0..], ip[0..4]);

        return geo.Ip{ .ip4 = ipv4 };
    }
};

/// Forward the eventual response of a pending (asynchronous) backend request straight to
/// the client. Compute waits in the background for the pending request to resolve into its
/// response headers and body, then streams them downstream. If the request fails before a
/// response materializes, a 5xx response is generated and sent in its place.
pub fn sendDownstreamPending(pending: PendingRequest) !void {
    try fastly(wasm.FastlyHttpResp.send_downstream_pending(pending.handle));
}

/// The initial connection to the proxy.
pub fn downstream() !Downstream {
    return Downstream{
        .request = try Request.downstream(),
        .response = try OutgoingResponse.downstream(),
    };
}
