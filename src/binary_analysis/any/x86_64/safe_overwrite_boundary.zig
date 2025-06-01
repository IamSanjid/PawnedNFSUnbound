const Disassembler = @import("disasm").x86_64;
const cs = Disassembler.cs;

pub const FindResult = struct {
    disasm_iter_res: Disassembler.DisasmIterResult,
    safe_size: usize,
};

pub fn find(disasm: Disassembler, target: usize, overwrite_size: usize) ?FindResult {
    @setRuntimeSafety(false);

    const target_ptr: [*]u8 = @ptrFromInt(target);

    const max_instruction_size = 15; // Maximum size of a x86_64 instruction
    const max_read_size = overwrite_size + max_instruction_size * 2;

    var iter_res = disasm.disasmIter(target_ptr[0..max_read_size], .{});

    var detail: cs.Detail = undefined;
    var ins: cs.Insn = undefined;
    ins.detail = &detail;
    var iter = iter_res.iter(&ins);

    var safe_size: usize = 0;

    while (iter.next()) |instruction| {
        safe_size += instruction.size;
        if (safe_size >= overwrite_size) {
            iter_res.code = iter_res.code[0..safe_size];
            return .{
                .safe_size = safe_size,
                .disasm_iter_res = iter_res,
            };
        }
    }

    return null;
}
