const std = @import("std");
const windows = std.os.windows;

const windows_extra = @import("windows_extra");

/// Emits simulating absolute jump instructions to the specified address.
/// `jmp [rip + 0x0000]`
/// `absolute address`
pub fn emitAbsoluteJmp(address: usize, jump_target: usize, overwrite_len: ?usize) !usize {
    @setRuntimeSafety(false);
    const total_bytes_to_write = 14; // 6 bytes for the jump instruction and 8 bytes for the absolute address
    const overwrite_bytes = overwrite_len orelse total_bytes_to_write;
    if (overwrite_bytes < total_bytes_to_write) {
        return error.InsufficientOverwriteLength;
    }

    var old_protect: windows.DWORD = 0;
    const address_ptr: windows.LPVOID = @ptrFromInt(address);
    try windows.VirtualProtect(address_ptr, overwrite_bytes, windows.PAGE_EXECUTE_READWRITE, &old_protect);

    const bytes: [*]u8 = @ptrCast(address_ptr);
    const jmp_instruction: [6]u8 = [_]u8{ 0xFF, 0x25, 0, 0, 0, 0 }; // jmp instruction
    inline for (0..6) |i| {
        bytes[i] = jmp_instruction[i];
    }

    const space_for_jump_address: *usize = @ptrFromInt(address + jmp_instruction.len);
    space_for_jump_address.* = jump_target;

    const extra_space = overwrite_bytes - total_bytes_to_write;
    for (0..extra_space) |i| {
        bytes[total_bytes_to_write + i] = 0x90; // nop
    }

    var dummy: windows.DWORD = 0;
    try windows.VirtualProtect(address_ptr, overwrite_bytes, old_protect, &dummy);

    _ = windows_extra.FlushInstructionCache(windows.GetCurrentProcess(), address_ptr, overwrite_bytes);

    return address + overwrite_bytes;
}
