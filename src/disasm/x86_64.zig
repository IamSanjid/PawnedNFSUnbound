const std = @import("std");
pub const cs = @import("capstone_z");
const capstone_iter = @import("capstone_iter.zig");

pub const CreateOptions = struct {};

pub const DisasmOptions = struct {
    use_dummy_address: bool = false,
};

pub const InstructionType = enum {
    JMP,
    JMP_COND,
    CALL,
    RET,
    OTHERS,
};

pub const Displacement = struct {
    offset: usize,
    size: usize,
    value: isize,
};

// only copy the interested fields from cs.Insn
pub const Instruction = struct {
    index: usize,
    address: usize,
    size: usize,
    target_address: usize,
    opcode: u8,
    displacement: ?Displacement,
    instruction_type: InstructionType,
};

fn detectInstructionType(id: c_uint, detail: *const cs.Detail) InstructionType {
    for (0..detail.groups_count) |i| {
        const group = detail.groups[i];
        switch (group) {
            cs.c.CS_GRP_JUMP => {
                return if (id == cs.c.X86_INS_JMP or id == cs.c.X86_INS_LJMP)
                    InstructionType.JMP
                else
                    InstructionType.JMP_COND;
            },
            cs.c.CS_GRP_CALL => return InstructionType.CALL,
            cs.c.CS_GRP_RET => return InstructionType.RET,
            else => {},
        }
    }

    return InstructionType.OTHERS;
}

fn readIntFromInsAt(insn: *const cs.Insn, offset: usize, size: usize) isize {
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

fn findDisplacement(insn: *const cs.Insn) ?Displacement {
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

fn isRipRelativeInstruction(insn: *const cs.Insn, ins_type: InstructionType) bool {
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

handle: cs.Handle,

const Self = @This();

pub fn create(options: CreateOptions) !Self {
    _ = options;
    var handle = try cs.open(cs.Arch.X86, cs.Mode.@"64");
    errdefer cs.close(&handle) catch {};

    try cs.option(handle, .DETAIL, cs.c.CS_OPT_ON);

    return .{
        .handle = handle,
    };
}

pub fn diasm(self: Self, code: []const u8, options: DisasmOptions) !DisasmResult {
    const address: usize = if (options.use_dummy_address) 0x1000 else @intFromPtr(code.ptr);
    const insns = try cs.disasm(self.handle, code, address, 0);
    return .{ .insns = insns };
}

/// Creates an iterator for disassembling instructions from the given code slice.
/// The iterator result ownes the resources and should be deinitialized after use.
pub fn disasmIter(self: Self, code: []const u8, options: DisasmOptions) DisasmIterResult {
    const address: usize = if (options.use_dummy_address) 0x1000 else @intFromPtr(code.ptr);
    return .{
        .handle = self.handle,
        .code = code,
        .address = address,
    };
}

pub const DisasmResult = struct {
    insns: []cs.Insn,

    const ResSelf = @This();

    pub fn findAllRipRelativeInstructions(self: ResSelf, allocator: std.mem.Allocator) ![]Instruction {
        const disass = self.insns;

        var instructions = std.ArrayList(Instruction).init(allocator);
        defer instructions.deinit();

        for (disass, 0..) |insn, index| {
            const detail = insn.detail orelse continue;
            const ins_type = detectInstructionType(insn.id, detail);
            if (!isRipRelativeInstruction(&insn, ins_type)) {
                continue;
            }
            const displacement = findDisplacement(&insn) orelse continue;
            const x86 = detail.arch.x86;

            const target_address: usize = @intCast(@as(isize, @intCast(insn.address)) + insn.size + displacement.value);
            try instructions.append(Instruction{
                .index = index,
                .address = insn.address,
                .size = insn.size,
                .target_address = target_address,
                .opcode = x86.opcode[0],
                .displacement = displacement,
                .instruction_type = ins_type,
            });
        }

        return instructions.toOwnedSlice();
    }

    pub fn findAllRetJmpInstructions(self: ResSelf, allocator: std.mem.Allocator) ![]Instruction {
        const disass = self.insns;

        var instructions = std.ArrayList(Instruction).init(allocator);
        defer instructions.deinit();

        for (disass, 0..) |insn, index| {
            const detail = insn.detail orelse continue;
            const ins_type = detectInstructionType(insn.id, detail);
            if (ins_type != InstructionType.JMP and ins_type != InstructionType.RET) {
                continue;
            }
            const displacement = findDisplacement(&insn);
            const x86 = detail.arch.x86;

            const target_address: usize = if (displacement) |d|
                @intCast(@as(isize, @intCast(insn.address)) + insn.size + d.value)
            else
                0;

            try instructions.append(Instruction{
                .index = index,
                .address = insn.address,
                .size = insn.size,
                .target_address = target_address,
                .opcode = x86.opcode[0],
                .displacement = displacement,
                .instruction_type = ins_type,
            });
        }

        return instructions.toOwnedSlice();
    }

    pub fn deinit(self: ResSelf) void {
        cs.free(self.insns);
    }
};

pub const DisasmIterResult = struct {
    handle: cs.Handle,
    code: []const u8,
    address: usize,
    const ResSelf = @This();

    const RipRelativeInsFilterMapIter = capstone_iter.FilteredMapIterator(Instruction, void, ripRelativeInstruction);
    const RipRelativeInsFilterMapIterManaged = capstone_iter.FilteredMapIteratorManaged(Instruction, void, ripRelativeInstruction);
    fn ripRelativeInstruction(index: usize, insn: *const cs.Insn, _: void) ?Instruction {
        const detail = insn.detail orelse return null;
        const ins_type = detectInstructionType(insn.id, detail);
        if (!isRipRelativeInstruction(insn, ins_type)) {
            return null;
        }
        const displacement = findDisplacement(insn) orelse return null;
        const x86 = detail.arch.x86;

        const target_address: usize = @intCast(@as(isize, @intCast(insn.address)) + insn.size + displacement.value);
        return Instruction{
            .index = index,
            .address = insn.address,
            .size = insn.size,
            .target_address = target_address,
            .opcode = x86.opcode[0],
            .displacement = displacement,
            .instruction_type = ins_type,
        };
    }

    pub fn ripRelativeInstructionsIter(self: ResSelf, ins: *cs.Insn) RipRelativeInsFilterMapIter {
        return RipRelativeInsFilterMapIter.init(self.handle, self.code, self.address, ins, {});
    }
    pub fn ripRelativeInstructionsIterManaged(self: ResSelf) RipRelativeInsFilterMapIterManaged {
        return RipRelativeInsFilterMapIterManaged.init(self.handle, self.code, self.address, {});
    }

    const ReturnJmpInsFilterMapIter = capstone_iter.FilteredMapIterator(Instruction, void, retJmpInstruction);
    const ReturnJmpInsFilterMapIterManaged = capstone_iter.FilteredMapIteratorManaged(Instruction, void, retJmpInstruction);
    fn retJmpInstruction(index: usize, insn: *const cs.Insn, _: void) ?Instruction {
        const detail = insn.detail orelse return null;
        const ins_type = detectInstructionType(insn.id, detail);
        if (ins_type != InstructionType.JMP and ins_type != InstructionType.RET) {
            return null;
        }
        const displacement = findDisplacement(insn);
        const x86 = detail.arch.x86;

        const target_address: usize = if (displacement) |d|
            @intCast(@as(isize, @intCast(insn.address)) + insn.size + d.value)
        else
            0;

        return Instruction{
            .index = index,
            .address = insn.address,
            .size = insn.size,
            .target_address = target_address,
            .opcode = x86.opcode[0],
            .displacement = displacement,
            .instruction_type = ins_type,
        };
    }

    pub fn retJmpInstructionsIter(self: ResSelf, ins: *cs.Insn) ReturnJmpInsFilterMapIter {
        return ReturnJmpInsFilterMapIter.init(self.handle, self.code, self.address, ins, {});
    }
    pub fn retJmpInstructionsIterManaged(self: ResSelf) !ReturnJmpInsFilterMapIterManaged {
        return ReturnJmpInsFilterMapIterManaged.init(self.handle, self.code, self.address, {});
    }

    const AllInsFilterMapIter = capstone_iter.FilteredMapIterator(Instruction, void, anyInstruction);
    const AllInsFilterMapIterManaged = capstone_iter.FilteredMapIteratorManaged(Instruction, void, anyInstruction);
    fn anyInstruction(index: usize, insn: *const cs.Insn, _: void) ?Instruction {
        const detail = insn.detail orelse return null;
        const displacement = findDisplacement(insn);
        const x86 = detail.arch.x86;

        const target_address: usize = if (displacement) |d|
            @intCast(@as(isize, @intCast(insn.address)) + insn.size + d.value)
        else
            0;
        return Instruction{
            .index = index,
            .address = insn.address,
            .size = insn.size,
            .target_address = target_address,
            .opcode = x86.opcode[0],
            .displacement = findDisplacement(insn),
            .instruction_type = detectInstructionType(insn.id, detail),
        };
    }

    pub fn iter(self: ResSelf, ins: *cs.Insn) AllInsFilterMapIter {
        return AllInsFilterMapIter.init(self.handle, self.code, self.address, ins, {});
    }
    pub fn iterManaged(self: ResSelf) AllInsFilterMapIterManaged {
        return AllInsFilterMapIterManaged.init(self.handle, self.code, self.address, {});
    }

    pub fn csIter(self: ResSelf, ins: *cs.Insn) cs.Iter {
        return cs.disasmIter(self.handle, self.code, self.address, @ptrCast(ins));
    }
    pub fn csIterManaged(self: ResSelf) cs.IterManaged {
        return cs.disasmIterManaged(self.handle, self.code, self.address);
    }
};

pub fn deinit(self: *Self) void {
    cs.close(&self.handle) catch {};
}

test "mixed non-relative and relative instructions" {
    const allocator = std.testing.allocator;
    const code: []const u8 = &.{
        0x55, // push rbp
        0x48, 0x8b, 0x41, 0x05, // mov rax, [rcx + 5]
        0x48, 0x89, 0xc8, // mov rax, rcx
        0x48, 0xc7, 0xc0, 0xff, 0x00, 0x00, 0x00, // mov rax, 0xff
        0x48, 0x8b, 0x05, 0xb8, 0x13, 0x00, 0x00, // mov rax, [rip + 0x13b8]
        0xe9, 0xab, 0xff, 0xff, 0xff, // jmp -0x55
        0xff, 0x25, 0xf3, 0x00, 0x00, 0x00, // jmp [rip + 0xf3]
        0xe8, 0xff, 0xff, 0xff, 0x7f, // call rip + 0x7fffffff
        0x74, 0xf, // je rip + 0xf
        0x0f, 0x84, 0x02, 0x00, 0x00, 0x00, // je rip + 0x2
        0xc3, // ret
    };

    var x86_disasm = try create(.{});
    defer x86_disasm.deinit();

    const disasm_result = try x86_disasm.diasm(code, .{});

    const instructions = try disasm_result.findAllRipRelativeInstructions(allocator);
    defer allocator.free(instructions);

    try std.testing.expectEqual(6, instructions.len);

    const base = @intFromPtr(code.ptr) + 15;
    // mov rax, [rip + 0x13b8]
    try std.testing.expectEqual(base + 7 + 0x13b8, instructions[0].target_address);
    // jmp -0x55
    try std.testing.expectEqual(base + 7 + 5 - 0x55, instructions[1].target_address);
    // jmp [rip + 0xf3]
    try std.testing.expectEqual(base + 7 + 5 + 6 + 0xf3, instructions[2].target_address);
    // call rip + 0x7fffffff
    try std.testing.expectEqual(0x7fffffff, instructions[3].displacement.?.value);
    try std.testing.expectEqual(base + 23 + 0x7fffffff, instructions[3].target_address);
    // je rip + 0xf
    try std.testing.expectEqual(base + 23 + 2 + 0xf, instructions[4].target_address);
    // je rip + 0x2
    try std.testing.expectEqual(base + 23 + 2 + 6 + 2, instructions[5].target_address);
}

test "mixed ret and jmp instructions" {
    const allocator = std.testing.allocator;
    const code: []const u8 = &.{
        0x55, // push rbp
        0x48, 0x8b, 0x41, 0x05, // mov rax, [rcx + 5]
        0x48, 0x89, 0xc8, // mov rax, rcx
        0x48, 0xc7, 0xc0, 0xff, 0x00, 0x00, 0x00, // mov rax, 0xff
        0x48, 0x8b, 0x05, 0xb8, 0x13, 0x00, 0x00, // mov rax, [rip + 0x13b8]
        0xe9, 0xab, 0xff, 0xff, 0xff, // jmp -0x55
        0xff, 0x25, 0xf3, 0x00, 0x00, 0x00, // jmp [rip + 0xf3]
        0xe8, 0xff, 0xff, 0xff, 0x7f, // call rip + 0x7fffffff
        0x74, 0xf, // je rip + 0xf
        0x0f, 0x84, 0x02, 0x00, 0x00, 0x00, // je rip + 0x2
        0xc3, // ret
    };

    var x86_disasm = try create(.{});
    defer x86_disasm.deinit();

    const disasm_result = try x86_disasm.diasm(code, .{});

    const instructions = try disasm_result.findAllRetJmpInstructions(allocator);
    defer allocator.free(instructions);

    try std.testing.expectEqual(3, instructions.len);

    const base = @intFromPtr(code.ptr) + 15;
    // jmp -0x55
    try std.testing.expectEqual(base + 7 + 5 - 0x55, instructions[0].target_address);
    // jmp [rip + 0xf3]
    try std.testing.expectEqual(base + 7 + 5 + 6 + 0xf3, instructions[1].target_address);
    // ret
    try std.testing.expectEqual(code.len - 1, instructions[2].address - (base - 15));
}

test "mixed non-relative, relative and ret, jump instructions iter" {
    const code: []const u8 = &.{
        0x55, // push rbp
        0x48, 0x8b, 0x41, 0x05, // mov rax, [rcx + 5]
        0x48, 0x89, 0xc8, // mov rax, rcx
        0x48, 0xc7, 0xc0, 0xff, 0x00, 0x00, 0x00, // mov rax, 0xff
        0x48, 0x8b, 0x05, 0xb8, 0x13, 0x00, 0x00, // mov rax, [rip + 0x13b8]
        0xe9, 0xab, 0xff, 0xff, 0xff, // jmp -0x55
        0xff, 0x25, 0xf3, 0x00, 0x00, 0x00, // jmp [rip + 0xf3]
        0xe8, 0xff, 0xff, 0xff, 0x7f, // call rip + 0x7fffffff
        0x74, 0xf, // je rip + 0xf
        0x0f, 0x84, 0x02, 0x00, 0x00, 0x00, // je rip + 0x2
        0xc3, // ret
    };
    const base = @intFromPtr(code.ptr) + 15;

    var x86_disasm = try create(.{});
    defer x86_disasm.deinit();

    var disasm_result = x86_disasm.disasmIter(code, .{});

    var tmp_detail: cs.Detail = undefined;
    var tmp_ins: cs.Insn = undefined;
    tmp_ins.detail = &tmp_detail;

    var instructions = disasm_result.ripRelativeInstructionsIter(&tmp_ins);
    // mov rax, [rip + 0x13b8]
    try std.testing.expectEqual(base + 7 + 0x13b8, instructions.next().?.target_address);
    // jmp -0x55
    try std.testing.expectEqual(base + 7 + 5 - 0x55, instructions.next().?.target_address);
    // jmp [rip + 0xf3]
    try std.testing.expectEqual(base + 7 + 5 + 6 + 0xf3, instructions.next().?.target_address);
    // call rip + 0x7fffffff
    const ins = instructions.next().?;
    try std.testing.expectEqual(0x7fffffff, ins.displacement.?.value);
    try std.testing.expectEqual(base + 23 + 0x7fffffff, ins.target_address);
    // je rip + 0xf
    try std.testing.expectEqual(base + 23 + 2 + 0xf, instructions.next().?.target_address);
    // je rip + 0x2
    try std.testing.expectEqual(base + 23 + 2 + 6 + 2, instructions.next().?.target_address);

    var instructions2 = try disasm_result.retJmpInstructionsIterManaged();
    // jmp -0x55
    try std.testing.expectEqual(base + 7 + 5 - 0x55, instructions2.next().?.target_address);
    // jmp [rip + 0xf3]
    try std.testing.expectEqual(base + 7 + 5 + 6 + 0xf3, instructions2.next().?.target_address);
    // ret
    try std.testing.expectEqual(code.len - 1, instructions2.next().?.address - (base - 15));

    var all_instructions = disasm_result.iter(&tmp_ins);
    // push rbp
    try std.testing.expectEqual(0x55, all_instructions.next().?.opcode);
    // mov rax, [rcx + 5]
    try std.testing.expectEqual(0x8b, all_instructions.next().?.opcode);
    // mov rax, rcx
    try std.testing.expectEqual(0x89, all_instructions.next().?.opcode);
    // mov rax, 0xff
    try std.testing.expectEqual(0xc7, all_instructions.next().?.opcode);
    // mov rax, [rip + 0x13b8]
    try std.testing.expectEqual(0x8b, all_instructions.next().?.opcode);
    // jmp -0x55
    try std.testing.expectEqual(0xe9, all_instructions.next().?.opcode);
    // jmp [rip + 0xf3]
    try std.testing.expectEqual(0xff, all_instructions.next().?.opcode);
    // call rip + 0x7fffffff
    try std.testing.expectEqual(0xe8, all_instructions.next().?.opcode);
    // je rip + 0xf
    try std.testing.expectEqual(0x74, all_instructions.next().?.opcode);
    // je rip + 0x2
    try std.testing.expectEqual(0x0f, all_instructions.next().?.opcode);
    // ret
    try std.testing.expectEqual(0xc3, all_instructions.next().?.opcode);
}

test "re-disasm while iterating" {
    const code: []const u8 = &.{
        0x55, // push rbp
        0x48, 0x8b, 0x41, 0x05, // mov rax, [rcx + 5]
        0x48, 0x89, 0xc8, // mov rax, rcx
        0x48, 0xc7, 0xc0, 0xff, 0x00, 0x00, 0x00, // mov rax, 0xff
        0x48, 0x8b, 0x05, 0xb8, 0x13, 0x00, 0x00, // mov rax, [rip + 0x13b8]
        0xe9, 0xab, 0xff, 0xff, 0xff, // jmp -0x55
        0xff, 0x25, 0xf3, 0x00, 0x00, 0x00, // jmp [rip + 0xf3]
        0xe8, 0xff, 0xff, 0xff, 0x7f, // call rip + 0x7fffffff
        0x74, 0xf, // je rip + 0xf
        0x0f, 0x84, 0x02, 0x00, 0x00, 0x00, // je rip + 0x2
        0xc3, // ret
    };
    const base = @intFromPtr(code.ptr) + 15;

    var x86_disasm = try create(.{});
    defer x86_disasm.deinit();

    var disasm_result1 = x86_disasm.disasmIter(code, .{});
    var disasm_result2 = x86_disasm.disasmIter(code, .{});

    var tmp_detail: cs.Detail = undefined;
    var tmp_ins: cs.Insn = undefined;
    tmp_ins.detail = &tmp_detail;

    // We're not concurrently accessing the iterator, so using the same tmp_ins is fine.
    var instructions = disasm_result1.ripRelativeInstructionsIter(&tmp_ins);
    var instructions2 = disasm_result2.retJmpInstructionsIter(&tmp_ins);

    // mov rax, [rip + 0x13b8]
    try std.testing.expectEqual(base + 7 + 0x13b8, instructions.next().?.target_address);
    // jmp -0x55
    try std.testing.expectEqual(base + 7 + 5 - 0x55, instructions2.next().?.target_address);

    // jmp -0x55
    try std.testing.expectEqual(base + 7 + 5 - 0x55, instructions.next().?.target_address);
    // jmp [rip + 0xf3]
    try std.testing.expectEqual(base + 7 + 5 + 6 + 0xf3, instructions2.next().?.target_address);

    // jmp [rip + 0xf3]
    try std.testing.expectEqual(base + 7 + 5 + 6 + 0xf3, instructions.next().?.target_address);
    // call rip + 0x7fffffff
    const ins = instructions.next().?;
    try std.testing.expectEqual(0x7fffffff, ins.displacement.?.value);
    try std.testing.expectEqual(base + 23 + 0x7fffffff, ins.target_address);
    // je rip + 0xf
    try std.testing.expectEqual(base + 23 + 2 + 0xf, instructions.next().?.target_address);
    // je rip + 0x2
    try std.testing.expectEqual(base + 23 + 2 + 6 + 2, instructions.next().?.target_address);

    // ret
    try std.testing.expectEqual(code.len - 1, instructions2.next().?.address - (base - 15));
}
