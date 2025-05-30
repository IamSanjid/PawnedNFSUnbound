pub const x86_64 = @import("x86_64.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
