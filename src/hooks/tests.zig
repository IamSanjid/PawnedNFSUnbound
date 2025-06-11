test {
    _ = @import("AllRaceAvailable.zig");
    _ = @import("RaceConfigCopy.zig");
    @import("std").testing.refAllDecls(@This());
}
