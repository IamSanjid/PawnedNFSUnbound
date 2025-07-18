pub const safe_overwrite_boundary = @import("safe_overwrite_boundary.zig");

pub const x86_64 = @import("x86_64/x86_64.zig");

extern "c" fn __clear_cache(begin: ?*anyopaque, end: ?*anyopaque) void;

pub inline fn clearInstructionCache(addr: []u8) void {
    const begin: ?*anyopaque = @ptrCast(addr.ptr);
    const end: ?*anyopaque = @ptrFromInt(@intFromPtr(begin) + addr.len);
    __clear_cache(begin, end);
}
