const x86 = @import("disasm").x86;
const cs = @import("disasm").capstone;

pub fn detect(handle: cs.Handle, code: []const u8) ?usize {
    @setRuntimeSafety(false);
    const target_address = @intFromPtr(code.ptr);

    var detail: cs.Detail = undefined;
    var ins: cs.Insn = undefined;
    ins.detail = &detail;
    var iter = cs.disasmIter(handle, code, target_address, &ins);

    var last_ins_offset: ?usize = null;
    while (iter.next()) |instruction| {
        const ins_detail = instruction.detail orelse continue;
        const ins_type = x86.detectInstructionType(instruction.id, ins_detail);
        if (ins_type == .JMP or ins_type == .RET) {
            last_ins_offset = instruction.address - target_address;
        }
    }

    return last_ins_offset;
}

test "detect" {
    const std = @import("std");

    var disasm = try x86.create(.{});
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
    const result = detect(disasm.handle, code);
    try std.testing.expectEqual(@as(?usize, code.len - 1), result);
}
