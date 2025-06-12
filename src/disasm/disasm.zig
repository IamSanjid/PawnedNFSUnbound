pub const x86 = @import("x86.zig");
pub const capstone = @import("capstone_z");

const Arch = @import("std").Target.Cpu.Arch;

pub fn createManagedCapstone(comptime arch: Arch, options: capstone.ManagedHandle.Options) !capstone.ManagedHandle {
    return switch (arch) {
        .x86 => capstone.ManagedHandle.init(.X86, capstone.Mode.from(.@"32"), options),
        .x86_64 => capstone.ManagedHandle.init(.X86, capstone.Mode.from(.@"64"), options),
        .aarch64 => capstone.ManagedHandle.init(.ARM64, capstone.Mode.from(.LITTLE_ENDIAN), options),
        .aarch64_be => capstone.ManagedHandle.init(.ARM64, capstone.Mode.from(.BIG_ENDIAN), options),
        .arm => capstone.ManagedHandle.init(.ARM, capstone.Mode.from(.LITTLE_ENDIAN), options),
        .armeb => capstone.ManagedHandle.init(.ARM, capstone.Mode.from(.BIG_ENDIAN), options),
        .thumb => capstone.ManagedHandle.init(.ARM, capstone.Mode.from(.THUMB), options),
        .thumbeb => capstone.ManagedHandle.init(.ARM, capstone.Mode.extendComptime(.THUMB, .LITTLE_ENDIAN), options),
        else => @compileError("TODO: Add more arch"),
    };
}

test {
    @import("std").testing.refAllDecls(@This());
}
