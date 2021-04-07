
//
// This file was automatically generated by witx-codegen - Do not edit manually.
//

pub const WasiHandle = i32;
pub const Char8 = u8;
pub const Char32 = u32;
pub fn WasiPtr(comptime T: type) type {
    return [*c]const T;
}
pub fn WasiMutPtr(comptime T: type) type {
    return [*c]T;
}
pub const WasiStringBytesPtr = WasiPtr(Char8);

pub const WasiString = extern struct {
    ptr: WasiStringBytesPtr,
    len: usize,

    fn from_slice(slice: []const u8) WasiString {
        return WasiString{ .ptr = slice.ptr, .len = slice.len };
    }

    fn as_slice(wasi_string: WasiString) []const u8 {
        return wasi_string.ptr[wasi_string.len];
    }
};

pub fn WasiSlice(comptime T) type {
    return extern struct {
        ptr: WasiPtr(T),
        len: usize,

        fn from_slice(slice: []const u8) WasiSlice {
            return WasiSlice{ .ptr = slice.ptr, .len = slice.len };
        }

        fn as_slice(wasi_slice: WasiSlice) []const u8 {
            return wasi_slice.ptr[wasi_slice.len];
        }
    };
}

pub fn WasiMutSlice(comptime T) type {
    return extern struct {
        ptr: WasiMutPtr(T),
        len: usize,

        fn from_slice(slice: *u8) WasiMutSlice {
            return WasiMutSlice{ .ptr = slice.ptr, .len = slice.len };
        }

        fn as_slice(wasi_slice: WasiMutSlice) []u8 {
            return wasi_slice.ptr[wasi_slice.len];
        }
    };
}

/// ---------------------- Module: [typenames] ----------------------

pub const FastlyStatus = extern enum(u32) {
    OK = 0,
    ERROR = 1,
    INVAL = 2,
    BADF = 3,
    BUFLEN = 4,
    UNSUPPORTED = 5,
    BADALIGN = 6,
    HTTPINVALID = 7,
    HTTPUSER = 8,
    HTTPINCOMPLETE = 9,
    NONE = 10,
};

pub const HttpVersion = extern enum(u32) {
    HTTP_09 = 0,
    HTTP_10 = 1,
    HTTP_11 = 2,
    H_2 = 3,
    H_3 = 4,
};

pub const HttpStatus = u16;

pub const BodyWriteEnd = extern enum(u32) {
    BACK = 0,
    FRONT = 1,
};

pub const BodyHandle = WasiHandle;

pub const RequestHandle = WasiHandle;

pub const ResponseHandle = WasiHandle;

pub const PendingRequestHandle = WasiHandle;

pub const EndpointHandle = WasiHandle;

pub const DictionaryHandle = WasiHandle;

pub const MultiValueCursor = u32;

/// -1 represents "finished", non-negative represents a $multi_value_cursor:
pub const MultiValueCursorResult = i64;

pub const CacheOverrideTag = u32;
pub const CACHE_OVERRIDE_TAG_NONE: CacheOverrideTag = 0x1;
pub const CACHE_OVERRIDE_TAG_PASS: CacheOverrideTag = 0x2;
pub const CACHE_OVERRIDE_TAG_TTL: CacheOverrideTag = 0x4;
pub const CACHE_OVERRIDE_TAG_STALE_WHILE_REVALIDATE: CacheOverrideTag = 0x8;
pub const CACHE_OVERRIDE_TAG_PCI: CacheOverrideTag = 0x10;



pub const NumBytes = usize;

pub const HeaderCount = u32;

pub const IsDone = u32;

pub const DoneIdx = u32;

pub const Typenames = struct {
};

/// ---------------------- Module: [fastly_abi] ----------------------

pub const FastlyAbi = struct {
    pub extern "fastly_abi" fn init(
        abi_version: u64,
    ) callconv(.C) FastlyStatus;

};

/// ---------------------- Module: [fastly_dictionary] ----------------------

pub const FastlyDictionary = struct {
    pub extern "fastly_dictionary" fn open(
        name_ptr: WasiPtr(Char8),
        name_len: usize,
        result_ptr: WasiMutPtr(DictionaryHandle),
    ) callconv(.C) FastlyStatus;

    pub extern "fastly_dictionary" fn get(
        h: DictionaryHandle,
        key_ptr: WasiPtr(Char8),
        key_len: usize,
        value: WasiMutPtr(Char8),
        value_max_len: usize,
        result_ptr: WasiMutPtr(NumBytes),
    ) callconv(.C) FastlyStatus;

};

/// ---------------------- Module: [fastly_http_body] ----------------------

pub const FastlyHttpBody = struct {
    pub extern "fastly_http_body" fn append(
        dest: BodyHandle,
        src: BodyHandle,
    ) callconv(.C) FastlyStatus;

    pub extern "fastly_http_body" fn new(
        result_ptr: WasiMutPtr(BodyHandle),
    ) callconv(.C) FastlyStatus;

    pub extern "fastly_http_body" fn read(
        h: BodyHandle,
        buf: WasiMutPtr(u8),
        buf_len: usize,
        result_ptr: WasiMutPtr(NumBytes),
    ) callconv(.C) FastlyStatus;

    pub extern "fastly_http_body" fn write(
        h: BodyHandle,
        buf_ptr: WasiPtr(u8),
        buf_len: usize,
        end: BodyWriteEnd,
        result_ptr: WasiMutPtr(NumBytes),
    ) callconv(.C) FastlyStatus;

    pub extern "fastly_http_body" fn close(
        h: BodyHandle,
    ) callconv(.C) FastlyStatus;

};

/// ---------------------- Module: [fastly_http_req] ----------------------

pub const FastlyHttpReq = struct {
    pub extern "fastly_http_req" fn body_downstream_get(
        result_0_ptr: WasiMutPtr(RequestHandle),
        result_1_ptr: WasiMutPtr(BodyHandle),
    ) callconv(.C) FastlyStatus;

    pub extern "fastly_http_req" fn cache_override_set(
        h: RequestHandle,
        tag: CacheOverrideTag,
        ttl: u32,
        stale_while_revalidate: u32,
    ) callconv(.C) FastlyStatus;

    pub extern "fastly_http_req" fn cache_override_v2_set(
        h: RequestHandle,
        tag: CacheOverrideTag,
        ttl: u32,
        stale_while_revalidate: u32,
        sk_ptr: WasiPtr(u8),
        sk_len: usize,
    ) callconv(.C) FastlyStatus;

    pub extern "fastly_http_req" fn downstream_client_ip_addr(
        addr_octets_out: WasiMutPtr(Char8),
        result_ptr: WasiMutPtr(NumBytes),
    ) callconv(.C) FastlyStatus;

    pub extern "fastly_http_req" fn downstream_tls_cipher_openssl_name(
        cipher_out: WasiMutPtr(Char8),
        cipher_max_len: usize,
        nwritten_out: WasiMutPtr(usize),
    ) callconv(.C) FastlyStatus;

    pub extern "fastly_http_req" fn downstream_tls_protocol(
        protocol_out: WasiMutPtr(Char8),
        protocol_max_len: usize,
        nwritten_out: WasiMutPtr(usize),
    ) callconv(.C) FastlyStatus;

    pub extern "fastly_http_req" fn downstream_tls_client_hello(
        chello_out: WasiMutPtr(Char8),
        chello_max_len: usize,
        nwritten_out: WasiMutPtr(usize),
    ) callconv(.C) FastlyStatus;

    pub extern "fastly_http_req" fn new(
        result_ptr: WasiMutPtr(RequestHandle),
    ) callconv(.C) FastlyStatus;

    pub extern "fastly_http_req" fn header_names_get(
        h: RequestHandle,
        buf: WasiMutPtr(Char8),
        buf_len: usize,
        cursor: MultiValueCursor,
        ending_cursor_out: WasiMutPtr(MultiValueCursorResult),
        nwritten_out: WasiMutPtr(usize),
    ) callconv(.C) FastlyStatus;

    pub extern "fastly_http_req" fn original_header_names_get(
        buf: WasiMutPtr(Char8),
        buf_len: usize,
        cursor: MultiValueCursor,
        ending_cursor_out: WasiMutPtr(MultiValueCursorResult),
        nwritten_out: WasiMutPtr(usize),
    ) callconv(.C) FastlyStatus;

    pub extern "fastly_http_req" fn original_header_count(
        result_ptr: WasiMutPtr(HeaderCount),
    ) callconv(.C) FastlyStatus;

    pub extern "fastly_http_req" fn header_value_get(
        h: RequestHandle,
        name_ptr: WasiPtr(u8),
        name_len: usize,
        value: WasiMutPtr(Char8),
        value_max_len: usize,
        nwritten_out: WasiMutPtr(usize),
    ) callconv(.C) FastlyStatus;

    pub extern "fastly_http_req" fn header_values_get(
        h: RequestHandle,
        name_ptr: WasiPtr(u8),
        name_len: usize,
        buf: WasiMutPtr(Char8),
        buf_len: usize,
        cursor: MultiValueCursor,
        ending_cursor_out: WasiMutPtr(MultiValueCursorResult),
        nwritten_out: WasiMutPtr(usize),
    ) callconv(.C) FastlyStatus;

    pub extern "fastly_http_req" fn header_values_set(
        h: RequestHandle,
        name_ptr: WasiPtr(u8),
        name_len: usize,
        values_ptr: WasiPtr(Char8),
        values_len: usize,
    ) callconv(.C) FastlyStatus;

    pub extern "fastly_http_req" fn header_insert(
        h: RequestHandle,
        name_ptr: WasiPtr(u8),
        name_len: usize,
        value_ptr: WasiPtr(u8),
        value_len: usize,
    ) callconv(.C) FastlyStatus;

    pub extern "fastly_http_req" fn header_append(
        h: RequestHandle,
        name_ptr: WasiPtr(u8),
        name_len: usize,
        value_ptr: WasiPtr(u8),
        value_len: usize,
    ) callconv(.C) FastlyStatus;

    pub extern "fastly_http_req" fn header_remove(
        h: RequestHandle,
        name_ptr: WasiPtr(u8),
        name_len: usize,
    ) callconv(.C) FastlyStatus;

    pub extern "fastly_http_req" fn method_get(
        h: RequestHandle,
        buf: WasiMutPtr(Char8),
        buf_len: usize,
        nwritten_out: WasiMutPtr(usize),
    ) callconv(.C) FastlyStatus;

    pub extern "fastly_http_req" fn method_set(
        h: RequestHandle,
        method_ptr: WasiPtr(Char8),
        method_len: usize,
    ) callconv(.C) FastlyStatus;

    pub extern "fastly_http_req" fn uri_get(
        h: RequestHandle,
        buf: WasiMutPtr(Char8),
        buf_len: usize,
        nwritten_out: WasiMutPtr(usize),
    ) callconv(.C) FastlyStatus;

    pub extern "fastly_http_req" fn uri_set(
        h: RequestHandle,
        uri_ptr: WasiPtr(Char8),
        uri_len: usize,
    ) callconv(.C) FastlyStatus;

    pub extern "fastly_http_req" fn version_get(
        h: RequestHandle,
        result_ptr: WasiMutPtr(HttpVersion),
    ) callconv(.C) FastlyStatus;

    pub extern "fastly_http_req" fn version_set(
        h: RequestHandle,
        version: HttpVersion,
    ) callconv(.C) FastlyStatus;

    pub extern "fastly_http_req" fn send(
        h: RequestHandle,
        b: BodyHandle,
        backend_ptr: WasiPtr(Char8),
        backend_len: usize,
        result_0_ptr: WasiMutPtr(ResponseHandle),
        result_1_ptr: WasiMutPtr(BodyHandle),
    ) callconv(.C) FastlyStatus;

    pub extern "fastly_http_req" fn send_async(
        h: RequestHandle,
        b: BodyHandle,
        backend_ptr: WasiPtr(Char8),
        backend_len: usize,
        result_ptr: WasiMutPtr(PendingRequestHandle),
    ) callconv(.C) FastlyStatus;

    pub extern "fastly_http_req" fn send_async_streaming(
        h: RequestHandle,
        b: BodyHandle,
        backend_ptr: WasiPtr(Char8),
        backend_len: usize,
        result_ptr: WasiMutPtr(PendingRequestHandle),
    ) callconv(.C) FastlyStatus;

    pub extern "fastly_http_req" fn pending_req_poll(
        h: PendingRequestHandle,
        result_0_ptr: WasiMutPtr(IsDone),
        result_1_ptr: WasiMutPtr(ResponseHandle),
        result_2_ptr: WasiMutPtr(BodyHandle),
    ) callconv(.C) FastlyStatus;

    pub extern "fastly_http_req" fn pending_req_wait(
        h: PendingRequestHandle,
        result_0_ptr: WasiMutPtr(ResponseHandle),
        result_1_ptr: WasiMutPtr(BodyHandle),
    ) callconv(.C) FastlyStatus;

    pub extern "fastly_http_req" fn pending_req_select(
        hs_ptr: WasiPtr(PendingRequestHandle),
        hs_len: usize,
        result_0_ptr: WasiMutPtr(DoneIdx),
        result_1_ptr: WasiMutPtr(ResponseHandle),
        result_2_ptr: WasiMutPtr(BodyHandle),
    ) callconv(.C) FastlyStatus;

};

/// ---------------------- Module: [fastly_http_resp] ----------------------

pub const FastlyHttpResp = struct {
    pub extern "fastly_http_resp" fn new(
        result_ptr: WasiMutPtr(ResponseHandle),
    ) callconv(.C) FastlyStatus;

    pub extern "fastly_http_resp" fn header_names_get(
        h: ResponseHandle,
        buf: WasiMutPtr(Char8),
        buf_len: usize,
        cursor: MultiValueCursor,
        ending_cursor_out: WasiMutPtr(MultiValueCursorResult),
        nwritten_out: WasiMutPtr(usize),
    ) callconv(.C) FastlyStatus;

    pub extern "fastly_http_resp" fn header_value_get(
        h: ResponseHandle,
        name_ptr: WasiPtr(u8),
        name_len: usize,
        value: WasiMutPtr(Char8),
        value_max_len: usize,
        nwritten_out: WasiMutPtr(usize),
    ) callconv(.C) FastlyStatus;

    pub extern "fastly_http_resp" fn header_values_get(
        h: ResponseHandle,
        name_ptr: WasiPtr(u8),
        name_len: usize,
        buf: WasiMutPtr(Char8),
        buf_len: usize,
        cursor: MultiValueCursor,
        ending_cursor_out: WasiMutPtr(MultiValueCursorResult),
        nwritten_out: WasiMutPtr(usize),
    ) callconv(.C) FastlyStatus;

    pub extern "fastly_http_resp" fn header_values_set(
        h: ResponseHandle,
        name_ptr: WasiPtr(u8),
        name_len: usize,
        values_ptr: WasiPtr(Char8),
        values_len: usize,
    ) callconv(.C) FastlyStatus;

    pub extern "fastly_http_resp" fn header_insert(
        h: ResponseHandle,
        name_ptr: WasiPtr(u8),
        name_len: usize,
        value_ptr: WasiPtr(u8),
        value_len: usize,
    ) callconv(.C) FastlyStatus;

    pub extern "fastly_http_resp" fn header_append(
        h: ResponseHandle,
        name_ptr: WasiPtr(u8),
        name_len: usize,
        value_ptr: WasiPtr(u8),
        value_len: usize,
    ) callconv(.C) FastlyStatus;

    pub extern "fastly_http_resp" fn header_remove(
        h: ResponseHandle,
        name_ptr: WasiPtr(u8),
        name_len: usize,
    ) callconv(.C) FastlyStatus;

    pub extern "fastly_http_resp" fn version_get(
        h: ResponseHandle,
        result_ptr: WasiMutPtr(HttpVersion),
    ) callconv(.C) FastlyStatus;

    pub extern "fastly_http_resp" fn version_set(
        h: ResponseHandle,
        version: HttpVersion,
    ) callconv(.C) FastlyStatus;

    pub extern "fastly_http_resp" fn send_downstream(
        h: ResponseHandle,
        b: BodyHandle,
        streaming: u32,
    ) callconv(.C) FastlyStatus;

    pub extern "fastly_http_resp" fn status_get(
        h: ResponseHandle,
        result_ptr: WasiMutPtr(HttpStatus),
    ) callconv(.C) FastlyStatus;

    pub extern "fastly_http_resp" fn status_set(
        h: ResponseHandle,
        status: HttpStatus,
    ) callconv(.C) FastlyStatus;

};

/// ---------------------- Module: [fastly_log] ----------------------

pub const FastlyLog = struct {
    pub extern "fastly_log" fn endpoint_get(
        name_ptr: WasiPtr(u8),
        name_len: usize,
        result_ptr: WasiMutPtr(EndpointHandle),
    ) callconv(.C) FastlyStatus;

    pub extern "fastly_log" fn write(
        h: EndpointHandle,
        msg_ptr: WasiPtr(u8),
        msg_len: usize,
        result_ptr: WasiMutPtr(NumBytes),
    ) callconv(.C) FastlyStatus;

};

/// ---------------------- Module: [fastly_uap] ----------------------

pub const FastlyUap = struct {
    pub extern "fastly_uap" fn parse(
        user_agent_ptr: WasiPtr(Char8),
        user_agent_len: usize,
        family: WasiMutPtr(Char8),
        family_len: usize,
        family_nwritten_out: WasiMutPtr(usize),
        major: WasiMutPtr(Char8),
        major_len: usize,
        major_nwritten_out: WasiMutPtr(usize),
        minor: WasiMutPtr(Char8),
        minor_len: usize,
        minor_nwritten_out: WasiMutPtr(usize),
        patch: WasiMutPtr(Char8),
        patch_len: usize,
        patch_nwritten_out: WasiMutPtr(usize),
    ) callconv(.C) FastlyStatus;

};

