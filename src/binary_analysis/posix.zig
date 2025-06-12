const std = @import("std");
const any = @import("any/any.zig");

pub const clearInstructionCache = any.clearInstructionCache;

pub fn copyToAsExecutable(to: usize, code: []const u8) !void {
    @setRuntimeSafety(false);
    const address_ptr: [*]u8 = @ptrFromInt(to);
    const page_size = std.heap.pageSize();

    // Calculate page-aligned address and size
    const page_start = std.mem.alignForward(usize, to, page_size);
    const page_end = std.mem.alignForward(usize, to + code.len, page_size);
    const page_len = page_end - page_start;

    const page_slice_ptr: [*]u8 = @ptrFromInt(page_start);
    try std.posix.mprotect(
        page_slice_ptr[0..page_len],
        std.posix.PROT.READ | std.posix.PROT.WRITE | std.posix.PROT.EXEC,
    );

    const bytes: []u8 = address_ptr[0..code.len];
    @memcpy(bytes, code);

    clearInstructionCache(bytes);
}
