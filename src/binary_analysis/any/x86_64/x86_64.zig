pub const func_end = @import("func_end.zig");
pub const relative_rip_instructions = @import("relative_rip_instructions.zig");

pub const rip_00_jmp_instruction = [_]u8{ 0xFF, 0x25, 0x00, 0x00, 0x00, 0x00 }; // jmp [rip+0x00]
pub const absolute_jmp_size = 14; // 6 bytes for the jump instruction and 8 bytes for the absolute address

pub inline fn writeJmpInstruction(bytes: []u8, jump_target: usize) void {
    @setRuntimeSafety(false);

    @import("std").debug.assert(bytes.len >= absolute_jmp_size);

    inline for (0..6) |i| {
        bytes[i] = rip_00_jmp_instruction[i];
    }

    const space_for_jump_address: *usize = @ptrFromInt(@intFromPtr(bytes.ptr) + rip_00_jmp_instruction.len);
    space_for_jump_address.* = jump_target;
}
