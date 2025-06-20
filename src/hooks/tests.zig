test {
    _ = @import("AllRaceAvailable.zig");
    _ = @import("CopyRaceVehicleConfig.zig");
    @import("std").testing.refAllDecls(@This());
}
