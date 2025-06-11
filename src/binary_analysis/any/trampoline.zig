const builtin = @import("builtin");
const std = @import("std");
const windows = std.os.windows;
const posix = std.posix;

const any = @import("any.zig");

pub inline fn alloc(target_len: usize) ![]u8 {
    const trampoline_len = std.mem.alignForward(usize, target_len, @sizeOf(usize));
    if (builtin.os.tag == .windows) {
        const memory = try windows.VirtualAlloc(
            null,
            trampoline_len,
            windows.MEM_COMMIT | windows.MEM_RESERVE,
            windows.PAGE_EXECUTE_READWRITE,
        );

        return @as([*]u8, @ptrCast(memory))[0..trampoline_len];
    } else {
        return try posix.mmap(
            null,
            trampoline_len,
            posix.PROT.READ | posix.PROT.WRITE | posix.PROT.EXEC,
            posix.MAP{ .ANONYMOUS = true, .TYPE = .PRIVATE },
            0,
            0,
        );
    }
}

pub inline fn restore(target_addr: usize, restore_code: []const u8) !void {
    @setRuntimeSafety(false);
    if (restore_code.len == 0) return;

    if (builtin.os.tag == .windows) {
        var old_protect: windows.DWORD = 0;
        const address_ptr: windows.LPVOID = @ptrFromInt(target_addr);
        try windows.VirtualProtect(address_ptr, restore_code.len, windows.PAGE_EXECUTE_READWRITE, &old_protect);

        const bytes: []u8 = @as([*]u8, @ptrCast(address_ptr))[0..restore_code.len];
        @memcpy(bytes, restore_code);

        var dummy: windows.DWORD = 0;
        try windows.VirtualProtect(address_ptr, restore_code.len, old_protect, &dummy);

        any.clearInstructionCache(bytes);
    } else {
        const address_ptr: [*]u8 = @ptrFromInt(target_addr);
        const page_size = std.heap.pageSize();

        // Calculate page-aligned address and size
        const page_start = std.mem.alignForward(usize, target_addr, page_size);
        const page_end = std.mem.alignForward(usize, target_addr + restore_code.len, page_size);
        const page_len = page_end - page_start;

        const page_slice_ptr: [*]u8 = @ptrFromInt(page_start);
        try posix.mprotect(
            page_slice_ptr[0..page_len],
            posix.PROT.READ | posix.PROT.WRITE | posix.PROT.EXEC,
        );

        const bytes: []u8 = address_ptr[0..restore_code.len];
        @memcpy(bytes, restore_code);

        any.clearInstructionCache(bytes);
    }
}

pub inline fn free(trampoline_region: []u8) void {
    if (trampoline_region.len == 0) return;

    if (builtin.os.tag == .windows) {
        const memory: windows.PVOID = @ptrCast(trampoline_region.ptr);
        windows.VirtualFree(memory, 0, windows.MEM_RELEASE);
    } else {
        posix.munmap(trampoline_region);
    }
}
