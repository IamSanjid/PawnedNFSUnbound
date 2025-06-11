const builtin = @import("builtin");
const std = @import("std");
const posix = std.posix;
const windows = std.os.windows;

const any = @import("../any.zig");

pub const rip_00_jmp_instruction = [_]u8{ 0xFF, 0x25, 0x00, 0x00, 0x00, 0x00 }; // jmp [rip+0x00]
const absolute_jmp_size = 14; // 6 bytes for the jump instruction and 8 bytes for the absolute address

inline fn writeJmpInstruction(bytes: [*]u8, jump_target: usize, overwrite_bytes: usize) void {
    @setRuntimeSafety(false);
    inline for (0..6) |i| {
        bytes[i] = rip_00_jmp_instruction[i];
    }

    const space_for_jump_address: *usize = @ptrFromInt(@intFromPtr(bytes) + rip_00_jmp_instruction.len);
    space_for_jump_address.* = jump_target;

    const extra_space = overwrite_bytes - absolute_jmp_size;
    for (0..extra_space) |i| {
        bytes[absolute_jmp_size + i] = 0x90; // nop
    }
}

/// Emits simulating absolute jump instructions to the specified address.
/// `jmp [rip + 0x0000]`
/// `absolute address`
pub fn emitAbsoluteJmp(address: usize, jump_target: usize, overwrite_len: ?usize) !usize {
    @setRuntimeSafety(false);

    const overwrite_bytes = overwrite_len orelse absolute_jmp_size;
    if (overwrite_bytes < absolute_jmp_size) {
        return error.InsufficientOverwriteLength;
    }

    if (builtin.os.tag == .windows) {
        var old_protect: windows.DWORD = 0;
        const address_ptr: windows.LPVOID = @ptrFromInt(address);
        try windows.VirtualProtect(address_ptr, overwrite_bytes, windows.PAGE_EXECUTE_READWRITE, &old_protect);

        const bytes: [*]u8 = @ptrCast(address_ptr);
        writeJmpInstruction(bytes, jump_target, overwrite_bytes);

        var dummy: windows.DWORD = 0;
        try windows.VirtualProtect(address_ptr, overwrite_bytes, old_protect, &dummy);

        any.clearInstructionCache(bytes[0..overwrite_bytes]);
    } else {
        const page_size = std.heap.pageSize();

        // Calculate page-aligned address and size
        const page_start = std.mem.alignForward(usize, address, page_size);
        const page_end = std.mem.alignForward(usize, address + overwrite_len, page_size);
        const page_len = page_end - page_start;

        const page_slice_ptr: [*]u8 = @ptrFromInt(page_start);
        try posix.mprotect(
            page_slice_ptr[0..page_len],
            posix.PROT.READ | posix.PROT.WRITE | posix.PROT.EXEC,
        );

        const bytes: [*]u8 = @ptrFromInt(address);
        writeJmpInstruction(bytes, jump_target, overwrite_bytes);

        any.clearInstructionCache(bytes[0..overwrite_bytes]);
    }

    return address + overwrite_bytes;
}
