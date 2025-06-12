const cs = @import("disasm").capstone;

pub const max_instruction_size = 16; // Maximum size of a instruction

pub fn find(handle: cs.Handle, target: usize, overwrite_size: usize) ?[]u8 {
    @setRuntimeSafety(false);

    const target_ptr: [*]u8 = @ptrFromInt(target);

    const max_read_size = overwrite_size + max_instruction_size * 2;

    var detail: cs.Detail = undefined;
    var ins: cs.Insn = undefined;
    ins.detail = &detail;
    var iter = cs.disasmIter(handle, target_ptr[0..max_read_size], target, &ins);

    var safe_size: usize = 0;

    while (iter.next()) |instruction| {
        safe_size += instruction.size;
        if (safe_size >= overwrite_size) {
            return target_ptr[0..safe_size];
        }
    }

    return null;
}
