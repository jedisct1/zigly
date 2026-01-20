# ACL Reference

The ACL module provides IP-based access control list lookups.

## Acl

### Opening an ACL

```zig
pub fn open(name: []const u8) !Acl
```

Open an ACL by name.

```zig
const Acl = zigly.Acl;

var blocklist = try Acl.open("ip_blocklist");
```

### Methods

#### lookup

```zig
pub fn lookup(self: Acl, ip: Ip) !LookupResult
```

Look up an IP address in the ACL. Returns a body with JSON result and an error code.

```zig
const result = try acl.lookup(client_ip);
defer result.body.close() catch {};

if (result.acl_error == .no_content) {
    // No match found
}
```

#### match

```zig
pub fn match(self: Acl, allocator: Allocator, ip: Ip) !?std.json.Parsed(MatchResult)
```

Look up an IP and get parsed result. Returns `null` if no match.

```zig
if (try acl.match(allocator, client_ip)) |result| {
    defer result.deinit();

    if (result.value.isBlock()) {
        // IP should be blocked
    } else if (result.value.isAllow()) {
        // IP is explicitly allowed
    }
} else {
    // No ACL match, apply default policy
}
```

---

## LookupResult

Raw lookup result.

```zig
pub const LookupResult = struct {
    body: Body,
    acl_error: AclError,
};
```

---

## AclError

ACL-specific error codes.

```zig
pub const AclError = enum(u32) {
    ok = 1,               // Successful lookup with match
    no_content = 2,       // No match found
    too_many_requests = 3, // Rate limited
};
```

---

## MatchResult

Parsed ACL match.

```zig
pub const MatchResult = struct {
    action: []const u8,   // "ALLOW" or "BLOCK"
    prefix: []const u8,   // Matched prefix ("192.168.0.0/16")

    pub fn isBlock(self: MatchResult) bool;
    pub fn isAllow(self: MatchResult) bool;
};
```

---

## Example Usage

### IP Blocking

```zig
const std = @import("std");
const zigly = @import("zigly");
const Acl = zigly.Acl;

fn start() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var downstream = try zigly.downstream();
    const client_ip = try zigly.http.Downstream.getClientIpAddr();

    var blocklist = try Acl.open("blocklist");

    if (try blocklist.match(allocator, client_ip)) |result| {
        defer result.deinit();

        if (result.value.isBlock()) {
            try downstream.response.setStatus(403);
            try downstream.response.body.writeAll("Access denied");
            try downstream.response.finish();
            return;
        }
    }

    try downstream.proxy("origin", null);
}
```

### Allow List

```zig
fn start() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var downstream = try zigly.downstream();
    const client_ip = try zigly.http.Downstream.getClientIpAddr();

    var allowlist = try Acl.open("admin_ips");

    var uri_buf: [4096]u8 = undefined;
    const uri = try downstream.request.getUriString(&uri_buf);

    // Protect admin paths
    if (std.mem.startsWith(u8, uri, "/admin/")) {
        const allowed = if (try allowlist.match(allocator, client_ip)) |result| blk: {
            defer result.deinit();
            break :blk result.value.isAllow();
        } else false;

        if (!allowed) {
            try downstream.response.setStatus(403);
            try downstream.response.finish();
            return;
        }
    }

    try downstream.proxy("origin", null);
}
```

### Geo + ACL

```zig
fn start() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var downstream = try zigly.downstream();
    const client_ip = try zigly.http.Downstream.getClientIpAddr();

    // Check ACL first
    var blocklist = try Acl.open("blocklist");
    if (try blocklist.match(allocator, client_ip)) |result| {
        defer result.deinit();
        if (result.value.isBlock()) {
            try downstream.response.setStatus(403);
            try downstream.response.finish();
            return;
        }
    }

    // Then check geo
    var geo_buf: [4096]u8 = undefined;
    const geo_result = try zigly.geo.lookup(allocator, client_ip, &geo_buf);
    const country = geo_result.value.country_code;

    // Block specific countries (in addition to ACL)
    const blocked_countries = [_][]const u8{ "XX", "YY" };
    for (blocked_countries) |blocked| {
        if (std.mem.eql(u8, country, blocked)) {
            try downstream.response.setStatus(403);
            try downstream.response.finish();
            return;
        }
    }

    try downstream.proxy("origin", null);
}
```

---

## Local Testing Configuration

Configure ACLs in `fastly.toml`:

```toml
[local_server.acls]
  [local_server.acls.blocklist]
  file = "acls/blocklist.json"

  [local_server.acls.admin_ips]
  file = "acls/admin.json"
```

Create `acls/blocklist.json`:

```json
{
  "entries": [
    {"prefix": "192.168.1.0/24", "action": "BLOCK"},
    {"prefix": "10.0.0.0/8", "action": "BLOCK"},
    {"prefix": "203.0.113.0/24", "action": "ALLOW"}
  ]
}
```

Create `acls/admin.json`:

```json
{
  "entries": [
    {"prefix": "192.168.1.100/32", "action": "ALLOW"},
    {"prefix": "10.0.0.0/8", "action": "ALLOW"}
  ]
}
```

Test with different IPs:

```bash
curl -H "Fastly-Client-IP: 192.168.1.50" http://localhost:7878/
curl -H "Fastly-Client-IP: 8.8.8.8" http://localhost:7878/
```
