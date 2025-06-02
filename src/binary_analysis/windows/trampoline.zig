const std = @import("std");
const windows = std.os.windows;

const windows_extra = @import("windows_extra");

pub inline fn alloc(target_len: usize) ![]u8 {
    const trampoline_len = target_len;
    const memory = try windows.VirtualAlloc(
        null,
        trampoline_len,
        windows.MEM_COMMIT | windows.MEM_RESERVE,
        windows.PAGE_EXECUTE_READWRITE,
    );

    return @as([*]u8, @ptrCast(memory))[0..trampoline_len];
}

pub inline fn restore(target_addr: usize, restore_code: []const u8) !void {
    @setRuntimeSafety(false);
    if (restore_code.len == 0) return;

    var old_protect: windows.DWORD = 0;
    const address_ptr: windows.LPVOID = @ptrFromInt(target_addr);
    try windows.VirtualProtect(address_ptr, restore_code.len, windows.PAGE_EXECUTE_READWRITE, &old_protect);

    const bytes: []u8 = @as([*]u8, @ptrCast(address_ptr))[0..restore_code.len];
    @memcpy(bytes, restore_code);

    var dummy: windows.DWORD = 0;
    try windows.VirtualProtect(address_ptr, restore_code.len, old_protect, &dummy);

    _ = windows_extra.FlushInstructionCache(windows.GetCurrentProcess(), address_ptr, restore_code.len);
}

pub inline fn free(trampoline_region: []u8) void {
    if (trampoline_region.len == 0) return;

    const memory: windows.PVOID = @ptrCast(trampoline_region.ptr);
    windows.VirtualFree(memory, 0, windows.MEM_RELEASE);
}
