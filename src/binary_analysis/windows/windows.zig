const windows = @import("std").os.windows;
const windows_extra = @import("windows_extra");

pub const x86_64 = @import("x86_64/x86_64.zig");

pub inline fn clearInstructionCache(addr: []u8) void {
    const address_ptr: windows.LPVOID = @ptrCast(addr.ptr);
    _ = windows_extra.FlushInstructionCache(windows.GetCurrentProcess(), address_ptr, addr.len);
}

pub fn copyToAsExecutable(to: usize, code: []const u8) !void {
    @setRuntimeSafety(false);
    if (code.len == 0) return;

    var old_protect: windows.DWORD = 0;
    const address_ptr: windows.LPVOID = @ptrFromInt(to);
    try windows.VirtualProtect(address_ptr, code.len, windows.PAGE_EXECUTE_READWRITE, &old_protect);

    const bytes: []u8 = @as([*]u8, @ptrCast(address_ptr))[0..code.len];
    @memcpy(bytes, code);

    var dummy: windows.DWORD = 0;
    try windows.VirtualProtect(address_ptr, code.len, old_protect, &dummy);

    clearInstructionCache(bytes);
}
