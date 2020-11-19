const wasm = @import("wasm.zig");

pub const FastlyError = error{
    FastlyGenericError,
    FastlyInvalidValue,
    FastlyBadDescriptor,
    FastlyBufferTooSmall,
    FastlyUnsupported,
    FastlyWrongAlignment,
    FastlyHttpParserError,
    FastlyHttpUserError,
    FastlyHttpIncomplete,
    FastlyNone,
};

pub fn fastly(fastly_status: wasm.fastly_status) FastlyError!void {
    switch (fastly_status) {
        wasm.fastly_status.OK => return,
        wasm.fastly_status.ERROR => return FastlyError.FastlyGenericError,
        wasm.fastly_status.INVAL => return FastlyError.FastlyInvalidValue,
        wasm.fastly_status.BADF => return FastlyError.FastlyBadDescriptor,
        wasm.fastly_status.BUFLEN => return FastlyError.FastlyBufferTooSmall,
        wasm.fastly_status.UNSUPPORTED => return FastlyError.FastlyUnsupported,
        wasm.fastly_status.BADALIGN => return FastlyError.FastlyWrongAlignment,
        wasm.fastly_status.HTTPPARSE => return FastlyError.FastlyHttpParserError,
        wasm.fastly_status.HTTPUSER => return FastlyError.FastlyHttpUserError,
        wasm.fastly_status.HTTPINCOMPLETE => return FastlyError.FastlyHttpIncomplete,
        wasm.fastly_status.NONE => return FastlyError.FastlyNone,
    }
}
