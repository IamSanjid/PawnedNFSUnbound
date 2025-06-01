pub const Disassembler = @import("disasm").x86_64;
const cs = Disassembler.cs;

pub fn detect(disasm_iter_res: Disassembler.DisasmIterResult) ?usize {
    @setRuntimeSafety(false);

    var detail: cs.Detail = undefined;
    var ins: cs.Insn = undefined;
    ins.detail = &detail;
    var iter = disasm_iter_res.retJmpInstructionsIter(&ins);

    var last_ins_offset: ?usize = null;
    while (iter.next()) |instruction| {
        last_ins_offset = instruction.address - @intFromPtr(disasm_iter_res.code.ptr);
    }

    return last_ins_offset;
}

test "detect" {
    const std = @import("std");

    var disasm = try Disassembler.create(.{});
    defer disasm.deinit();

    const code: []const u8 = &.{
        0x55, // push rbp
        0x48, 0x89, 0xe5, // mov rbp, rsp
        0x89, 0x7d, 0xfc, // mov [rbp-4], edi
        0x89, 0x75, 0xf8, // mov [rbp-8], esi
        0x8b, 0x45, 0xfc, // mov eax, [rbp-4]
        0x03, 0x45, 0xf8, // add eax, [rbp-8]
        0x5d, // pop rbp
        0xc3, // ret
    };
    const disasm_iter_res = disasm.disasmIter(code, .{});
    const result = detect(disasm_iter_res);
    try std.testing.expectEqual(@as(?usize, code.len - 1), result);
}
