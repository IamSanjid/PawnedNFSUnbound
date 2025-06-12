const builtin = @import("builtin");
const std = @import("std");

const Self = @This();

pub const any = @import("any/any.zig");
pub const windows = @import("windows/windows.zig");
pub const posix = @import("posix.zig");
pub const TrampolineAllocator = @import("TrampolineAllocator.zig");
pub const Detour = @import("Detour.zig");
pub const disasm = @import("disasm");

pub fn imports(comptime arch: std.Target.Cpu.Arch) type {
    return struct {
        pub const any = @field(Self.any, @tagName(arch));
        pub const windows = @field(Self.windows, @tagName(arch));
        pub const Dissasembler = @field(Self.disasm, @tagName(arch));
    };
}

test {
    if (builtin.cpu.arch == .x86_64) {
        _ = @import("any/x86_64/relative_rip_instructions.zig");
        _ = @import("any/x86_64/func_end.zig");

        _ = @import("Detour.zig");
    }
    _ = @import("binary_analysis.zig");
    _ = @import("std").testing.refAllDecls(@This());
}
