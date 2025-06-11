const builtin = @import("builtin");
const std = @import("std");

const Self = @This();

pub const any = @import("any/any.zig");
pub const windows = @import("windows/windows.zig");
pub const disasm = @import("disasm");

pub fn imports(comptime arch: std.Target.Cpu.Arch) type {
    return struct {
        pub const any = @field(Self.any, @tagName(arch));
        pub const windows = @field(Self.windows, @tagName(arch));
        pub const Dissasembler = @field(Self.disasm, @tagName(arch));
    };
}

test "any trampoline" {
    const trampoline = any.trampoline;
    const target_len = 10;
    const trampoline_region = try trampoline.alloc(target_len);
    defer trampoline.free(trampoline_region);

    try std.testing.expect(trampoline_region.len >= target_len);
}

test {
    if (builtin.cpu.arch == .x86_64) {
        _ = @import("any/x86_64/relative_rip_instructions.zig");
        _ = @import("any/x86_64/func_end.zig");
        _ = @import("any/x86_64/safe_overwrite_boundary.zig");

        _ = @import("any/x86_64/Detour.zig");
    }
    _ = @import("binary_analysis.zig");
    _ = @import("std").testing.refAllDecls(@This());
}
