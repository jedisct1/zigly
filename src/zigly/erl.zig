const wasm = @import("wasm.zig");
const fastly = @import("errors.zig").fastly;

pub const RateCounter = struct {
    name: []const u8,

    pub fn open(name: []const u8) RateCounter {
        return RateCounter{ .name = name };
    }

    pub fn increment(self: RateCounter, entry: []const u8, delta: u32) !void {
        try fastly(wasm.FastlyErl.ratecounter_increment(
            self.name.ptr,
            self.name.len,
            entry.ptr,
            entry.len,
            delta,
        ));
    }

    pub fn lookupRate(self: RateCounter, entry: []const u8, window_seconds: u32) !u32 {
        var rate: wasm.Rate = undefined;
        try fastly(wasm.FastlyErl.ratecounter_lookup_rate(
            self.name.ptr,
            self.name.len,
            entry.ptr,
            entry.len,
            window_seconds,
            &rate,
        ));
        return rate;
    }

    pub fn lookupCount(self: RateCounter, entry: []const u8, duration_seconds: u32) !u32 {
        var count: wasm.Count = undefined;
        try fastly(wasm.FastlyErl.ratecounter_lookup_count(
            self.name.ptr,
            self.name.len,
            entry.ptr,
            entry.len,
            duration_seconds,
            &count,
        ));
        return count;
    }
};

pub const PenaltyBox = struct {
    name: []const u8,

    pub fn open(name: []const u8) PenaltyBox {
        return PenaltyBox{ .name = name };
    }

    pub fn add(self: PenaltyBox, entry: []const u8, ttl_seconds: u32) !void {
        try fastly(wasm.FastlyErl.penaltybox_add(
            self.name.ptr,
            self.name.len,
            entry.ptr,
            entry.len,
            ttl_seconds,
        ));
    }

    pub fn has(self: PenaltyBox, entry: []const u8) !bool {
        var result: wasm.Has = undefined;
        try fastly(wasm.FastlyErl.penaltybox_has(
            self.name.ptr,
            self.name.len,
            entry.ptr,
            entry.len,
            &result,
        ));
        return result != 0;
    }
};

pub const CheckRateResult = enum(u32) {
    allowed = 0,
    blocked = 1,
};

pub const RateLimiter = struct {
    rate_counter: []const u8,
    penalty_box: []const u8,
    window_seconds: u32,
    limit: u32,
    ttl_seconds: u32,

    pub fn init(options: struct {
        rate_counter: []const u8,
        penalty_box: []const u8,
        window_seconds: u32,
        limit: u32,
        ttl_seconds: u32,
    }) RateLimiter {
        return RateLimiter{
            .rate_counter = options.rate_counter,
            .penalty_box = options.penalty_box,
            .window_seconds = options.window_seconds,
            .limit = options.limit,
            .ttl_seconds = options.ttl_seconds,
        };
    }

    pub fn checkRate(self: RateLimiter, entry: []const u8, delta: u32) !CheckRateResult {
        var blocked: wasm.Blocked = undefined;
        try fastly(wasm.FastlyErl.check_rate(
            self.rate_counter.ptr,
            self.rate_counter.len,
            entry.ptr,
            entry.len,
            delta,
            self.window_seconds,
            self.limit,
            self.penalty_box.ptr,
            self.penalty_box.len,
            self.ttl_seconds,
            &blocked,
        ));
        return @enumFromInt(blocked);
    }

    pub fn isAllowed(self: RateLimiter, entry: []const u8, delta: u32) !bool {
        return try self.checkRate(entry, delta) == .allowed;
    }

    pub fn isBlocked(self: RateLimiter, entry: []const u8, delta: u32) !bool {
        return try self.checkRate(entry, delta) == .blocked;
    }
};

pub fn checkRate(
    rate_counter: []const u8,
    entry: []const u8,
    delta: u32,
    window_seconds: u32,
    limit: u32,
    penalty_box: []const u8,
    ttl_seconds: u32,
) !CheckRateResult {
    var blocked: wasm.Blocked = undefined;
    try fastly(wasm.FastlyErl.check_rate(
        rate_counter.ptr,
        rate_counter.len,
        entry.ptr,
        entry.len,
        delta,
        window_seconds,
        limit,
        penalty_box.ptr,
        penalty_box.len,
        ttl_seconds,
        &blocked,
    ));
    return @enumFromInt(blocked);
}
