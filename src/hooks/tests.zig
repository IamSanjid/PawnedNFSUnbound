test {
    _ = @import("nfs_unbound_sdk.zig");
    _ = @import("AllRaceAvailable.zig");
    _ = @import("CopyRaceVehicleConfig.zig");
    @import("std").testing.refAllDecls(@This());
}
