const std = @import("std");

const Disassembler = @import("disasm").x86_64;
const cs = Disassembler.cs;

pub const Displacement = struct {
    offset: usize,
    size: usize,
    value: isize,
};

fn detectInstructionType(id: c_uint, detail: cs.Detail) Disassembler.InstructionType {
    for (0..detail.groups_count) |i| {
        const group = detail.groups[i];
        switch (group) {
            cs.c.CS_GRP_JUMP => {
                return if (id == cs.c.X86_INS_JMP or id == cs.c.X86_INS_LJMP)
                    .JMP
                else
                    .JMP_COND;
            },
            cs.c.CS_GRP_CALL => return .CALL,
            cs.c.CS_GRP_RET => return .RET,
            else => {},
        }
    }

    return .OTHERS;
}

fn readIntFromInsAt(insn: cs.Insn, offset: usize, size: usize) isize {
    @setRuntimeSafety(false);
    const bytes = insn.bytes;
    if (offset + size > bytes.len) {
        return 0;
    }
    if (size >= 4) {
        const candidate: i32 = @as(*i32, @ptrFromInt(@intFromPtr(bytes[offset .. offset + 4].ptr))).*;
        return @intCast(candidate);
    }

    if (size >= 2) {
        const candidate: i16 = @as(*i16, @ptrFromInt(@intFromPtr(bytes[offset .. offset + 2].ptr))).*;
        return @intCast(candidate);
    }

    if (size >= 1) {
        const candidate: i8 = @as(*i8, @ptrFromInt(@intFromPtr(bytes[offset .. offset + 1].ptr))).*;
        return @intCast(candidate);
    }
    return 0;
}

fn findDisplacement(insn: cs.Insn) ?Displacement {
    @setRuntimeSafety(false);

    const detail = insn.detail orelse return null;
    const x86 = detail.arch.x86;
    if (x86.encoding.disp_offset > 0) {
        return Displacement{
            .offset = x86.encoding.disp_offset,
            .size = x86.encoding.disp_size,
            .value = x86.disp,
        };
    }

    if (x86.encoding.imm_offset > 0) {
        return Displacement{
            .offset = x86.encoding.imm_offset,
            .size = x86.encoding.imm_size,
            .value = readIntFromInsAt(insn, x86.encoding.imm_offset, x86.encoding.imm_size),
        };
    }

    return null;
}

fn isRipRelativeInstruction(insn: cs.Insn, ins_type: Disassembler.InstructionType) bool {
    if (ins_type == .RET) {
        return false;
    }

    if (ins_type != .OTHERS) {
        return true;
    }

    const detail = insn.detail orelse return false;
    const x86 = detail.arch.x86;

    for (0..x86.op_count) |i| {
        const op = x86.operands[i];
        if (op.type == .MEM and op.inst.mem.base == .RIP) {
            return true;
        }
    }

    return false;
}

pub const FixedCode = struct {
    fixed_code: []const u8,
    reserved_offset: usize,
};

fn fix(allocator: std.mem.Allocator, disasm: Disassembler, code: []const u8, reserve: usize) !FixedCode {
    @setRuntimeSafety(false);
    var disasm_res = disasm.disasmIter(code, .{});

    var tmp_detail: Disassembler.Detail = undefined;
    var tmp_ins: Disassembler.Insn = undefined;
    tmp_ins.detail = &tmp_detail;
    var iter = disasm_res.csIter(&tmp_ins);

    var fixed_code = std.ArrayList(u8).init(allocator);
    defer fixed_code.deinit();

    var new_code = std.ArrayList(u8).init(allocator);
    defer new_code.deinit();

    try new_code.appendNTimes(0x90, reserve);

    var current_offset: usize = 0;
    while (iter.next()) |ins| {
        const detail = ins.detail orelse unreachable;
        const x86 = detail.arch.x86;

        const ins_type = detectInstructionType(ins.id, detail);
        if (!isRipRelativeInstruction(ins, ins_type)) continue;
        const displacement = findDisplacement(ins) orelse continue;

        const target_address: usize = @intCast(@as(isize, @intCast(ins.address)) + ins.size + displacement.value);

        const offset = ins.address - @intFromPtr(code.ptr);
        const before_code = code[current_offset..offset];
        current_offset += offset + ins.size;
        try fixed_code.appendSlice(before_code);
    }

    const end_of_replaced_code = fixed_code.items.len;
    fixed_code.appendSlice(new_code.items);

    return .{
        .fixed_code = try fixed_code.toOwnedSlice(),
        .reserved_offset = end_of_replaced_code,
    };
}
