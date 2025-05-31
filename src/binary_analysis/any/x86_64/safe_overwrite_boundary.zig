pub const Disassembler = @import("disasm").x86_64;

pub fn find(disasm: Disassembler, target: usize, overwrite_size: usize) !usize {
    @setRuntimeSafety(false);

    const target_ptr: [*]u8 = @ptrCast(target);

    const max_instruction_size = 15; // Maximum size of a x86_64 instruction
    const max_read_size = overwrite_size + max_instruction_size * 2;

    var iter_res = disasm.disasmIter(target_ptr[0..max_read_size], .{});

    var detail: Disassembler.Detail = undefined;
    var ins: Disassembler.Insn = undefined;
    ins.detail = &detail;
    var iter = iter_res.iter(&ins);

    var safe_size: usize = 0;

    while (iter.next()) |instruction| {
        safe_size += instruction.size;
        if (safe_size >= overwrite_size) {
            return safe_size;
        }
    }

    return error.SafeOverwriteBoundaryNotFound;
}
