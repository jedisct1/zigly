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
    FastlyHttpHeaderTooLarge,
    FastlyHttpInvalidStatus,
    FastlyLimitExceeded,
    FastlyAgain,
};

pub fn fastly(fastly_status: wasm.FastlyStatus) FastlyError!void {
    switch (fastly_status) {
        wasm.FastlyStatus.OK => return,
        wasm.FastlyStatus.ERROR => return FastlyError.FastlyGenericError,
        wasm.FastlyStatus.INVAL => return FastlyError.FastlyInvalidValue,
        wasm.FastlyStatus.BADF => return FastlyError.FastlyBadDescriptor,
        wasm.FastlyStatus.BUFLEN => return FastlyError.FastlyBufferTooSmall,
        wasm.FastlyStatus.UNSUPPORTED => return FastlyError.FastlyUnsupported,
        wasm.FastlyStatus.BADALIGN => return FastlyError.FastlyWrongAlignment,
        wasm.FastlyStatus.HTTPINVALID => return FastlyError.FastlyHttpParserError,
        wasm.FastlyStatus.HTTPUSER => return FastlyError.FastlyHttpUserError,
        wasm.FastlyStatus.HTTPINCOMPLETE => return FastlyError.FastlyHttpIncomplete,
        wasm.FastlyStatus.NONE => return FastlyError.FastlyNone,
        wasm.FastlyStatus.HTTPHEADTOOLARGE => return FastlyError.FastlyHttpHeaderTooLarge,
        wasm.FastlyStatus.HTTPINVALIDSTATUS => return FastlyError.FastlyHttpInvalidStatus,
        wasm.FastlyStatus.LIMITEXCEEDED => return FastlyError.FastlyLimitExceeded,
        wasm.FastlyStatus.AGAIN => return FastlyError.FastlyAgain,
    }
}
