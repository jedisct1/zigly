const wasm = @import("wasm.zig");
const fastly = @import("errors.zig").fastly;

/// Get the amount of vCPU time used by this request in milliseconds.
/// This is useful for monitoring and optimizing compute costs.
pub fn getVcpuMs() !u64 {
    var vcpu_ms: wasm.VcpuMs = undefined;
    try fastly(wasm.FastlyComputeRuntime.get_vcpu_ms(&vcpu_ms));
    return vcpu_ms;
}
