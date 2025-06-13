const builtin = @import("builtin");
const std = @import("std");

const Self = @This();

pub const any = @import("any/any.zig");
pub const windows = @import("windows/windows.zig");
pub const posix = @import("posix.zig");
pub const aob = @import("aob.zig");
pub const TrampolineAllocator = @import("TrampolineAllocator.zig");
pub const TargetDetour = @import("detour.zig").Detour;
/// Builtin target Detour
pub const Detour = TargetDetour(builtin.cpu.arch, builtin.os.tag);
pub const disasm = @import("disasm");

test {
    if (builtin.cpu.arch == .x86_64) {
        _ = @import("any/x86_64/relative_rip_instructions.zig");
        _ = @import("any/x86_64/func_end.zig");
    }
    _ = @import("detour.zig");
    _ = @import("TrampolineAllocator.zig");
    _ = @import("aob.zig");
    _ = @import("binary_analysis.zig");
    _ = @import("std").testing.refAllDecls(@This());
}
