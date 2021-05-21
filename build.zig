const std = @import("std");
const Builder = std.build.Builder;

pub fn build(b: *Builder) !void {
    const target = try std.zig.CrossTarget.parse(.{ .arch_os_abi = "wasm32-wasi" });

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("zig-tests", "src/tests.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}
