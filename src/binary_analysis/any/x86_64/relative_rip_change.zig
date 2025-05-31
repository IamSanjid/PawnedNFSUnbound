const std = @import("std");

const Disassembler = @import("disasm").x86_64;
const cs = Disassembler.cs;

const Displacement = Disassembler.Displacement;

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

    if (ins_type == .JMP or ins_type == .JMP_COND or ins_type == .CALL) {
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

const FixedCodeRef = struct {
    write_offset: usize = 0,
    start_offset: usize = 0,
    end_offset: usize = 0,
};

const FixedCodeWriter = struct {
    code: []const u8,
    buf: std.ArrayList(u8),
    new_buf: std.ArrayList(u8),
    refs: std.ArrayList(FixedCodeRef),
    reuse_refs: std.ArrayList(usize),
    current_offset: usize = 0,
    reserved_offset: usize = 0,

    const FCWSelf = @This();

    fn init(allocator: std.mem.Allocator, code: []const u8, reserve: usize) !FCWSelf {
        var new_buf = std.ArrayList(u8).init(allocator);
        try new_buf.appendNTimes(0x90, reserve);
        return .{
            .code = code,
            .buf = std.ArrayList(u8).init(allocator),
            .new_buf = new_buf,
            .refs = std.ArrayList(FixedCodeRef).init(allocator),
            .reuse_refs = std.ArrayList(usize).init(allocator),
            .reserved_offset = 0,
        };
    }

    fn replacing(self: *FCWSelf, ins: cs.Insn) *FCWSelf {
        const offset = ins.address - @intFromPtr(self.code.ptr);
        const before_code = self.code[self.current_offset..offset];
        self.current_offset = offset + ins.size;
        self.buf.appendSlice(before_code) catch @panic("OOM");
        return self;
    }

    fn append(self: *FCWSelf, slice: []const u8) *FCWSelf {
        self.buf.appendSlice(slice) catch @panic("OOM");
        return self;
    }

    fn addValueRef(self: *FCWSelf, value: usize) *FCWSelf {
        const end_offset = self.new_buf.items.len;
        self.new_buf.appendNTimes(0, @sizeOf(usize)) catch @panic("OOM");
        @as(*usize, @ptrFromInt(@intFromPtr(self.new_buf.items[end_offset..].ptr))).* = value;

        const write_offset = self.buf.items.len;
        self.buf.appendNTimes(0, @sizeOf(u32)) catch @panic("OOM");

        self.refs.append(FixedCodeRef{
            .write_offset = write_offset,
            .start_offset = self.buf.items.len,
            .end_offset = end_offset,
        }) catch @panic("OOM");

        return self;
    }

    fn addReuseRef(self: *FCWSelf, reuse_idx: usize) *FCWSelf {
        if (reuse_idx >= self.reuse_refs.items.len) {
            while (reuse_idx >= self.reuse_refs.items.len) {
                const end_offset = self.new_buf.items.len;
                self.new_buf.appendNTimes(0, @sizeOf(usize)) catch @panic("OOM");

                self.reuse_refs.append(end_offset) catch @panic("OOM");
            }
        }

        const write_offset = self.buf.items.len;
        self.buf.appendNTimes(0, @sizeOf(u32)) catch @panic("OOM");

        self.refs.append(FixedCodeRef{
            .write_offset = write_offset,
            .start_offset = self.buf.items.len,
            .end_offset = self.reuse_refs.items[reuse_idx],
        }) catch @panic("OOM");

        return self;
    }

    fn finalize(self: *FCWSelf) !FixedCode {
        @setRuntimeSafety(false);
        defer {
            self.buf.deinit();
            self.new_buf.deinit();
            self.refs.deinit();
            self.reuse_refs.deinit();
        }

        const remaining_code = self.code[self.current_offset..];
        try self.buf.appendSlice(remaining_code);
        const new_code_offset = self.buf.items.len;
        if (self.reserved_offset > 0) self.reserved_offset = new_code_offset;

        try self.buf.appendSlice(self.new_buf.items);

        for (self.refs.items) |ref| {
            const new_offset = (new_code_offset - ref.start_offset) + ref.end_offset;
            @as(*u32, @ptrFromInt(@intFromPtr(self.buf.items[ref.write_offset..].ptr))).* = @intCast(new_offset);
        }

        return .{
            .fixed_code = try self.buf.toOwnedSlice(),
            .reserved_offset = self.reserved_offset,
        };
    }
};

fn fixCallJmpIns(ins: cs.Insn, comptime call: bool, writer: *FixedCodeWriter) void {
    const detail = ins.detail orelse unreachable;
    const x86 = detail.arch.x86;
    const displacement = findDisplacement(ins) orelse unreachable;

    const target_address: usize = @intCast(@as(isize, @intCast(ins.address)) + ins.size + displacement.value);

    const opcode = if (call) 0x15 else 0x25;

    // check if accessing stuff
    var accessing_memory = false;
    for (x86.operands[0..x86.op_count]) |op| {
        if (op.type == .MEM and op.inst.mem.base == .RIP) {
            accessing_memory = true;
            break;
        }
    }

    if (accessing_memory) {
        _ = writer
            .replacing(ins)
            .append(&.{
                0x50, // push rax
                0x48, 0x8b, 0x05, // mov rax, [rip + {}]
            })
            .addValueRef(target_address)
            .append(&.{
                0x48, 0x8b, 0x00, // mov rax, [rax]
                0x48, 0x89, 0x05, // mov [rip+{reuse0}], rax
            })
            .addReuseRef(0)
            .append(&.{
                0x58, // pop rax
                0xff, opcode, // call/jmp [rip+reuse0]
            })
            .addReuseRef(0);
    } else {
        _ = writer
            .replacing(ins)
            .append(&.{
                0xff, opcode, // call/jmp [rip+{}]
            })
            .addValueRef(target_address);
    }
}

pub fn fix(allocator: std.mem.Allocator, disasm: Disassembler, code: []const u8, reserve: usize) !FixedCode {
    @setRuntimeSafety(false);
    var disasm_res = disasm.disasmIter(code, .{});

    var tmp_detail: cs.Detail = undefined;
    var tmp_ins: cs.Insn = undefined;
    tmp_ins.detail = &tmp_detail;
    var iter = disasm_res.csIter(&tmp_ins);

    var writer = try FixedCodeWriter.init(allocator, code, reserve);
    while (iter.next()) |ins| {
        const detail = ins.detail orelse unreachable;

        const ins_type = detectInstructionType(ins.id, detail.*);
        if (!isRipRelativeInstruction(ins.*, ins_type)) continue;

        if (ins_type == .CALL) {
            fixCallJmpIns(ins.*, true, &writer);
        } else if (ins_type == .JMP) {
            fixCallJmpIns(ins.*, false, &writer);
        }
    }

    return writer.finalize();
}

test "jmp/call" {
    @setRuntimeSafety(false);
    const code: []const u8 = &.{
        0xe8, 0xfb, 0x00, 0x00, 0x00, // call 0x100 ; call rel32
        0xeb, 0x0e, // jmp 0x10 ; jmp rel8
        0xe9, 0xfb, 0x00, 0x00, 0x00, // jmp 0x100 ; jmp rel32
        0xff, 0x15, 0x10, 0x00, 0x00, 0x00, // call [rip+0x10] ; call [rip+rel32]
        0xff, 0x25, 0x10, 0x00, 0x00, 0x00, // jmp [rip+0x10] ; jmp [rip+rel32]
    };
    const base = @intFromPtr(code.ptr);

    var disasm = try Disassembler.create(.{});
    defer disasm.deinit();

    const res = try fix(std.testing.allocator, disasm, code, 0);
    defer std.testing.allocator.free(res.fixed_code);

    try std.testing.expectEqualSlices(u8, &[_]u8{ 0xff, 0x15 }, res.fixed_code[0..2]);
    const jmp_offset = @as(*u32, @ptrFromInt(@intFromPtr(res.fixed_code[2..].ptr))).*;
    const jmp_addr = @as(*usize, @ptrFromInt(@intFromPtr(res.fixed_code[jmp_offset..].ptr))).*;
    try std.testing.expectEqual(base + 0x100, jmp_addr);
}
