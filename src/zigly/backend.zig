const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

const wasm = @import("wasm.zig");
const errors = @import("errors.zig");
const fastly = errors.fastly;
const FastlyError = errors.FastlyError;

pub const TlsVersion = wasm.TlsVersion;
pub const BackendHealth = wasm.BackendHealth;

pub const Backend = struct {
    name: []const u8,

    /// Check if a backend with this name exists.
    pub fn exists(name: []const u8) !bool {
        var result: wasm.BackendExists = undefined;
        try fastly(wasm.FastlyBackend.exists(name.ptr, name.len, &result));
        return result != 0;
    }

    /// Check if this backend is healthy.
    pub fn isHealthy(self: Backend) !BackendHealth {
        var result: wasm.BackendHealth = undefined;
        try fastly(wasm.FastlyBackend.is_healthy(self.name.ptr, self.name.len, &result));
        return result;
    }

    /// Check if this backend was created dynamically.
    pub fn isDynamic(self: Backend) !bool {
        var result: wasm.IsDynamic = undefined;
        try fastly(wasm.FastlyBackend.is_dynamic(self.name.ptr, self.name.len, &result));
        return result != 0;
    }

    /// Check if this backend uses SSL/TLS.
    pub fn isSsl(self: Backend) !bool {
        var result: wasm.IsSsl = undefined;
        try fastly(wasm.FastlyBackend.is_ssl(self.name.ptr, self.name.len, &result));
        return result != 0;
    }

    /// Get the host for this backend.
    pub fn getHost(self: Backend, buf: []u8) ![]const u8 {
        var nwritten: usize = undefined;
        try fastly(wasm.FastlyBackend.get_host(self.name.ptr, self.name.len, buf.ptr, buf.len, &nwritten));
        return buf[0..nwritten];
    }

    /// Get the host override for this backend.
    pub fn getOverrideHost(self: Backend, buf: []u8) ![]const u8 {
        var nwritten: usize = undefined;
        try fastly(wasm.FastlyBackend.get_override_host(self.name.ptr, self.name.len, buf.ptr, buf.len, &nwritten));
        return buf[0..nwritten];
    }

    /// Get the port for this backend.
    pub fn getPort(self: Backend) !u16 {
        var result: wasm.Port = undefined;
        try fastly(wasm.FastlyBackend.get_port(self.name.ptr, self.name.len, &result));
        return result;
    }

    /// Get the connect timeout in milliseconds.
    pub fn getConnectTimeoutMs(self: Backend) !u32 {
        var result: wasm.TimeoutMs = undefined;
        try fastly(wasm.FastlyBackend.get_connect_timeout_ms(self.name.ptr, self.name.len, &result));
        return result;
    }

    /// Get the first byte timeout in milliseconds.
    pub fn getFirstByteTimeoutMs(self: Backend) !u32 {
        var result: wasm.TimeoutMs = undefined;
        try fastly(wasm.FastlyBackend.get_first_byte_timeout_ms(self.name.ptr, self.name.len, &result));
        return result;
    }

    /// Get the between bytes timeout in milliseconds.
    pub fn getBetweenBytesTimeoutMs(self: Backend) !u32 {
        var result: wasm.TimeoutMs = undefined;
        try fastly(wasm.FastlyBackend.get_between_bytes_timeout_ms(self.name.ptr, self.name.len, &result));
        return result;
    }

    /// Get the minimum SSL/TLS version.
    pub fn getSslMinVersion(self: Backend) !TlsVersion {
        var result: wasm.TlsVersion = undefined;
        try fastly(wasm.FastlyBackend.get_ssl_min_version(self.name.ptr, self.name.len, &result));
        return result;
    }

    /// Get the maximum SSL/TLS version.
    pub fn getSslMaxVersion(self: Backend) !TlsVersion {
        var result: wasm.TlsVersion = undefined;
        try fastly(wasm.FastlyBackend.get_ssl_max_version(self.name.ptr, self.name.len, &result));
        return result;
    }
};

pub const DynamicBackend = struct {
    name: []const u8,
    target: []const u8,
    host_override: ?[]const u8 = null,
    connect_timeout_ms: ?u32 = null,
    first_byte_timeout_ms: ?u32 = null,
    between_bytes_timeout_ms: ?u32 = null,
    use_ssl: bool = false,
    ssl_min_version: ?TlsVersion = null,
    ssl_max_version: ?TlsVersion = null,
    cert_hostname: ?[]const u8 = null,
    ca_cert: ?[]const u8 = null,
    ciphers: ?[]const u8 = null,
    sni_hostname: ?[]const u8 = null,
    dont_pool: bool = false,
    grpc: bool = false,

    /// Register the dynamic backend and return a Backend handle.
    pub fn register(self: DynamicBackend) !Backend {
        var mask: wasm.BackendConfigOptions = 0;
        var config: wasm.DynamicBackendConfig = undefined;

        @memset(std.mem.asBytes(&config), 0);

        if (self.host_override) |host| {
            mask |= wasm.BACKEND_CONFIG_OPTIONS_HOST_OVERRIDE;
            config.host_override = @constCast(host.ptr);
            config.host_override_len = @intCast(host.len);
        }

        if (self.connect_timeout_ms) |timeout| {
            mask |= wasm.BACKEND_CONFIG_OPTIONS_CONNECT_TIMEOUT;
            config.connect_timeout_ms = timeout;
        }

        if (self.first_byte_timeout_ms) |timeout| {
            mask |= wasm.BACKEND_CONFIG_OPTIONS_FIRST_BYTE_TIMEOUT;
            config.first_byte_timeout_ms = timeout;
        }

        if (self.between_bytes_timeout_ms) |timeout| {
            mask |= wasm.BACKEND_CONFIG_OPTIONS_BETWEEN_BYTES_TIMEOUT;
            config.between_bytes_timeout_ms = timeout;
        }

        if (self.use_ssl) {
            mask |= wasm.BACKEND_CONFIG_OPTIONS_USE_SSL;
        }

        if (self.ssl_min_version) |version| {
            mask |= wasm.BACKEND_CONFIG_OPTIONS_SSL_MIN_VERSION;
            config.ssl_min_version = version;
        }

        if (self.ssl_max_version) |version| {
            mask |= wasm.BACKEND_CONFIG_OPTIONS_SSL_MAX_VERSION;
            config.ssl_max_version = version;
        }

        if (self.cert_hostname) |hostname| {
            mask |= wasm.BACKEND_CONFIG_OPTIONS_CERT_HOSTNAME;
            config.cert_hostname = @constCast(hostname.ptr);
            config.cert_hostname_len = @intCast(hostname.len);
        }

        if (self.ca_cert) |cert| {
            mask |= wasm.BACKEND_CONFIG_OPTIONS_CA_CERT;
            config.ca_cert = @constCast(cert.ptr);
            config.ca_cert_len = @intCast(cert.len);
        }

        if (self.ciphers) |c| {
            mask |= wasm.BACKEND_CONFIG_OPTIONS_CIPHERS;
            config.ciphers = @constCast(c.ptr);
            config.ciphers_len = @intCast(c.len);
        }

        if (self.sni_hostname) |hostname| {
            mask |= wasm.BACKEND_CONFIG_OPTIONS_SNI_HOSTNAME;
            config.sni_hostname = @constCast(hostname.ptr);
            config.sni_hostname_len = @intCast(hostname.len);
        }

        if (self.dont_pool) {
            mask |= wasm.BACKEND_CONFIG_OPTIONS_DONT_POOL;
        }

        if (self.grpc) {
            mask |= wasm.BACKEND_CONFIG_OPTIONS_GRPC;
        }

        try fastly(wasm.FastlyHttpReq.register_dynamic_backend(
            self.name.ptr,
            self.name.len,
            self.target.ptr,
            self.target.len,
            mask,
            &config,
        ));

        return Backend{ .name = self.name };
    }
};
