const std = @import("std");
const windows = std.os.windows;

pub inline fn alloc(target_len: usize) ![]u8 {
    const trampoline_len = target_len + 16; // Extra space for absolute jump emulation instructions
    const memory = try windows.VirtualAlloc(
        null,
        trampoline_len,
        windows.MEM_COMMIT | windows.MEM_RESERVE,
        windows.PAGE_EXECUTE_READWRITE,
    );

    return @as([*]u8, @ptrCast(memory))[0..trampoline_len];
}

pub inline fn free(trampoline_region: []u8) void {
    if (trampoline_region.len == 0) return;

    const memory: windows.PVOID = @ptrCast(trampoline_region.ptr);
    windows.VirtualFree(memory, 0, windows.MEM_RELEASE);
}
