const builtin = @import("builtin");
const std = @import("std");
const windows = std.os.windows;

const windows_extra = @import("windows_extra");

pub const x86_64 = @import("x86_64/x86_64.zig");
pub const trampoline = @import("trampoline.zig");

extern "c" fn __clear_cache(begin: ?*anyopaque, end: ?*anyopaque) void;

pub inline fn clearInstructionCache(addr: []u8) void {
    if (builtin.os.tag == .windows) {
        const address_ptr: windows.LPVOID = @ptrCast(addr.ptr);
        _ = windows_extra.FlushInstructionCache(windows.GetCurrentProcess(), address_ptr, addr.len);
    } else {
        const begin: ?*anyopaque = @ptrCast(addr.ptr);
        const end: ?*anyopaque = @ptrFromInt(@intFromPtr(begin) + addr.len);
        __clear_cache(begin, end);
    }
}
