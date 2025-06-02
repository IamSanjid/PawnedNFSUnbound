test {
    _ = @import("AllRaceAvailable.zig");
    @import("std").testing.refAllDecls(@This());
}
