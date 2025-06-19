const std = @import("std");

const apb = @import("asm_patch_buffer");
const Disassembler = @import("disasm").x86;
const cs = @import("disasm").capstone;

const bytes = apb.bytes;
const patternMatchBytes = apb.patternMatchBytes;
const reference = apb.reference;
const useReference = apb.useReference;
const reusableReference = apb.reusableReference;
const reusableReferenceOrCreate = apb.reusableReferenceOrCreate;
const mark = apb.mark;

pub const FixedCode = struct {
    code: []const u8,
    reserved_offset: usize,
};

const Patcher = struct {
    buffer: apb.AsmPatchBuffer,
    const Self = @This();

    fn deinit(self: *Self) void {
        self.buffer.deinit();
    }

    fn replace(self: *Self, ins: *const cs.Insn, with: anytype) !void {
        const offset = ins.address - @intFromPtr(self.buffer.original.ptr);
        try self.buffer.copyUntilOffset(offset);
        return self.buffer.replace(ins.size, with);
    }

    fn finalize(self: *Self, reserve_bytes: usize) !FixedCode {
        @setRuntimeSafety(false);
        var committed = try self.buffer.copyRestAndCommitOwned(reserve_bytes);
        defer {
            committed.refrences.deinit();
            committed.markers.deinit();
        }

        @memset(committed.buffer[committed.reserved_offset .. committed.reserved_offset + reserve_bytes], 0x90);

        for (committed.refrences.items) |ref| {
            if (ref.size == 4) {
                @as(*i32, @ptrFromInt(@intFromPtr(committed.buffer[ref.offset..].ptr))).* = @intCast(ref.value_offset);
            } else if (ref.size == 1) {
                @as(*i8, @ptrFromInt(@intFromPtr(committed.buffer[ref.offset..].ptr))).* = @intCast(ref.value_offset);
            } else {
                unreachable;
            }
        }

        return .{
            .code = committed.buffer,
            .reserved_offset = committed.reserved_offset,
        };
    }
};

fn fixCallJmpIns(ins: *const cs.Insn, comptime call: bool, patcher: *Patcher) !void {
    @setRuntimeSafety(false);
    const detail = ins.detail orelse unreachable;
    const x86 = detail.arch.x86;
    const displacement = Disassembler.findDisplacement(ins) orelse return; // saves us from call [rax]/jmp [rax]

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
        // TODO: Change this to mov rax, imm64 variant....
        try patcher.replace(ins, .{
            bytes(.{
                0x50, // push rax
                0x48, 0x8B, 0x05, // mov rax, [rip + {}]
            }),
            reference(@sizeOf(i32), .{target_address}),
            bytes(.{
                0x48, 0x8B, 0x00, // mov rax, [rax]
                0x48, 0x89, 0x05, // mov [rip+{reuse0}], rax
            }),
            reusableReferenceOrCreate(0, @sizeOf(i32), .{@as(usize, 0)}),
            bytes(.{
                0x58, // pop rax
                0xFF, opcode, // call/jmp [rip+reuse0]
            }),
            reusableReference(0),
        });
    } else {
        try patcher.replace(ins, .{
            // call/jmp [rip+{}]
            bytes(.{ 0xFF, opcode }),
            reference(@sizeOf(i32), .{target_address}),
        });
    }
}

fn fixCondJmpIns(ins: *const cs.Insn, patcher: *Patcher) !Rel32JmpIns {
    @setRuntimeSafety(false);
    const detail = ins.detail orelse unreachable;
    const x86 = detail.arch.x86;
    const displacement = Disassembler.findDisplacement(ins) orelse unreachable;

    const target_address: usize = @intCast(@as(isize, @intCast(ins.address)) + ins.size + displacement.value);

    var jmp_ins: Rel32JmpIns = undefined;
    const opcode = if (x86.opcode[0] & 0x70 != 0x00) 0x80 | (x86.opcode[0] & 0x0F) else x86.opcode[1];

    if (displacement.size >= 4) jmp_ins.orig_opcode = opcode else jmp_ins.orig_opcode = x86.opcode[0];
    jmp_ins.opcode = opcode;
    jmp_ins.ref_id = patcher.buffer.references.items.len;

    try patcher.replace(ins, .{
        mark(.pos, &jmp_ins.mark_id),
        bytes(.{ 0x0F, opcode }),
        reference(@sizeOf(i32), bytes(.{
            0xFF, 0x25, 0x00, 0x00, 0x00, 0x00, // jmp [rip+0]
            target_address, // address 64bit value
        })),
    });
    return jmp_ins;
}

pub fn fixMovIns(ins: *const cs.Insn, patcher: *Patcher) !void {
    @setRuntimeSafety(false);
    const detail = ins.detail orelse unreachable;
    const x86 = detail.arch.x86;
    const displacement = Disassembler.findDisplacement(ins) orelse unreachable;

    const target_address: usize = @intCast(@as(isize, @intCast(ins.address)) + ins.size + displacement.value);

    if (ins.id == cs.c.X86_INS_LEA) {
        const r7_reg = x86.rex == 0x48;
        const mov_rex: u8 = if (r7_reg) 0x48 else 0x49;
        const mov_opcode = 0xB8 + ((x86.modrm >> 3) & 0x07); // Extract bits 5-3
        try patcher.replace(ins, .{
            bytes(.{
                mov_rex, // rex
                mov_opcode, // mov opcode
                target_address, // imm64 value
            }),
        });
    } else {
        // TODO: Optimize it... Doesn't support avx/simd floating point movs...
        const disp_offset = x86.encoding.disp_offset;
        const disp_size = x86.encoding.disp_size;
        std.debug.assert(disp_offset > 0);
        const start = ins.bytes[0..disp_offset];
        const end = ins.bytes[disp_offset + disp_size .. ins.size];
        // original ===>
        // mov r, [rip+rel32]/mov [rip+rel32], r/sub/dec/imul [rip+rel32], etc...
        // r = any general register

        // Replaced with(approx 56 bytes) ===>
        // push rax ; save rax register
        // mov rax, {target_address} ; calculated from rip, rip+rel32
        // mov rax, [rax]
        // mov [rip+{our_temp_storage}], rax ; basically storing the value after reading it, to our temp storage
        // pop rax ; restore rax register, no side effect
        // mov r, [rip+{our_temp_storage}]/mov [{our_temp_storage}+rip], r/sub/dec/imul [rip+{our_temp_storage}]
        // push rax
        // mov rax, [{our_temp_storage}+rip]
        // push rcx
        // mov rcx, {target_address} ; calculated from rip, rip+rel32
        // mov [rcx], rax ; store value from our temp storage back to the original
        // pop rcx
        // pop rax
        try patcher.replace(ins, .{
            bytes(.{
                0x50, // push rax
                0x48, 0xB8, target_address, // mov rax, ${target_address}
                0x48, 0x8B, 0x00, // mov rax, [rax]
                0x48, 0x89, 0x05, // mov [rip+{reuse0}], rax
            }),
            reusableReferenceOrCreate(0, @sizeOf(i32), .{@as(usize, 0)}),
            // pop rax
            bytes(.{0x58}),
            bytes(start),
            reusableReference(0),
            bytes(end),
            bytes(.{
                0x50, // push rax
                0x48, 0x8B, 0x05, // mov rax, [rip+{reuse0}]
            }),
            reusableReference(0),
            bytes(.{
                0x51, // push rcx
                0x48, 0xB9, target_address, // mov rcx, ${target_address}
                0x48, 0x89, 0x01, // mov [rcx], rax
                0x59, // pop rcx
                0x58, // pop rax
            }),
        });
    }
}

const Rel32JmpIns = struct {
    mark_id: usize,
    ref_id: usize,
    opcode: u8,
    orig_opcode: u8,
};

fn updateRel32JmpIns(patcher: *Patcher, jmps: []Rel32JmpIns, reserve_size: usize) !void {
    for (jmps) |jmp_ins| {
        // TODO: Optimize original cond jump rel32 instructions...
        if (jmp_ins.opcode == jmp_ins.orig_opcode) continue;
        const ref = patcher.buffer.estimateReferenceOffsets(jmp_ins.ref_id, reserve_size);
        const value_offset = ref.value_offset - 1 - (@sizeOf(i32) - @sizeOf(i32)); // -1 for 0x0F
        // It doesn't account for if all the jump instructions were made rel8 version
        if (value_offset >= std.math.minInt(i8) and value_offset <= std.math.maxInt(i8)) {
            const pos = patcher.buffer.getMarkerPos(jmp_ins.mark_id);
            patcher.buffer.updateReference(jmp_ins.ref_id, @sizeOf(i8), 1);

            const block_id = patcher.buffer.markers.get(jmp_ins.mark_id).pos.block_id;
            patcher.buffer.blocks.items[block_id].size = 2;
            //patcher.buffer.getBlockPtrWithin(pos, 6).?.size = 2;

            try patcher.buffer.replaceRange(pos, 6, &bytes(.{ jmp_ins.orig_opcode, 0x00 })); // finalize will update it!
        }
    }
}

/// Should return something like:
/// ```
/// <fixed_relative_instructions>
/// <reserved_space>
/// <additional instructions/values>(to fix the relative instructions and behave like the original ones)
/// ```
pub fn fix(allocator: std.mem.Allocator, handle: cs.Handle, code: []const u8, reserve: usize) !FixedCode {
    var tmp_detail: cs.Detail = undefined;
    var tmp_ins: cs.Insn = undefined;
    tmp_ins.detail = &tmp_detail;
    var iter = cs.disasmIter(handle, code, @intFromPtr(code.ptr), &tmp_ins);

    var patcher = Patcher{ .buffer = .init(allocator, code) };
    defer patcher.deinit();

    var cond_jmps = std.ArrayList(Rel32JmpIns).init(allocator);
    defer cond_jmps.deinit();

    while (iter.next()) |ins| {
        const detail = ins.detail orelse unreachable;

        const ins_type = Disassembler.detectInstructionType(ins.id, detail);
        if (!Disassembler.isRipRelativeInstruction(ins, ins_type)) continue;

        if (ins_type == .CALL) {
            try fixCallJmpIns(ins, true, &patcher);
        } else if (ins_type == .JMP) {
            try fixCallJmpIns(ins, false, &patcher);
        } else if (ins_type == .JMP_COND) {
            try cond_jmps.append(try fixCondJmpIns(ins, &patcher));
        } else {
            try fixMovIns(ins, &patcher);
        }
    }
    try updateRel32JmpIns(&patcher, cond_jmps.items, reserve);

    return try patcher.finalize(reserve);
}

test "jmp/call" {
    @setRuntimeSafety(false);
    const code: []const u8 = &.{
        0xe8, 0xfb, 0x00, 0x00, 0x00, // call 0xfb ; call rel32
        0xeb, 0x0e, // jmp 0x0e ; jmp rel8
        0xe9, 0xfb, 0x00, 0x00, 0x00, // jmp 0xfb ; jmp rel32
        0xff, 0x15, 0x10, 0x00, 0x00, 0x00, // call [rip+0x10] ; call [rip+rel32]
        0xff, 0x25, 0x10, 0x00, 0x00, 0x00, // jmp [rip+0x10] ; jmp [rip+rel32]
    };
    const base = @intFromPtr(code.ptr);

    var disasm = try Disassembler.create(.{});
    defer disasm.deinit();

    const res = try fix(std.testing.allocator, disasm.handle, code, 0);
    defer std.testing.allocator.free(res.code);

    var read_offset: usize = 0;
    // var ins_size: usize = 0;
    // var jmp_offset: usize = 0;
    // var jmp_addr: usize = 0;

    // try std.testing.expectEqualSlices(u8, code, res.code);

    // call 0xfb ; call rel32
    {
        var extracted_offset1: i32 = undefined;
        try std.testing.expect(patternMatchBytes(.{
            0xff, 0x15, &extracted_offset1, // call [rip+imm32]
        }, res.code[read_offset..]));
        read_offset += 2 + @sizeOf(i32);
        const offset1: usize = @intCast(@as(isize, @intCast(read_offset)) + extracted_offset1);

        var addr: usize = undefined;
        try std.testing.expect(patternMatchBytes(.{&addr}, res.code[@intCast(offset1)..]));
        try std.testing.expectEqual(base + 5 + 0xfb, addr);
    }
    // jmp 0x0e ; jmp rel8
    {
        var extracted_offset1: i32 = undefined;
        try std.testing.expect(patternMatchBytes(.{
            0xff, 0x25, &extracted_offset1, // jmp [rip+imm32]
        }, res.code[read_offset..]));
        read_offset += 2 + @sizeOf(i32);
        const offset1: usize = @intCast(@as(isize, @intCast(read_offset)) + extracted_offset1);

        var addr: usize = undefined;
        try std.testing.expect(patternMatchBytes(.{&addr}, res.code[@intCast(offset1)..]));
        try std.testing.expectEqual(base + 7 + 0x0e, addr);
    }
    // jmp 0xfb ; jmp rel32
    {
        var extracted_offset1: i32 = undefined;
        try std.testing.expect(patternMatchBytes(.{
            0xff, 0x25, &extracted_offset1, // jmp [rip+imm32]
        }, res.code[read_offset..]));
        read_offset += 2 + @sizeOf(i32);
        const offset1: usize = @intCast(@as(isize, @intCast(read_offset)) + extracted_offset1);

        var addr: usize = undefined;
        try std.testing.expect(patternMatchBytes(.{&addr}, res.code[@intCast(offset1)..]));
        try std.testing.expectEqual(base + 12 + 0xfb, addr);
    }
    var reused_offset: usize = undefined;
    // call [rip+0x10] ; call [rip+rel32]
    {
        var extracted_offset1: i32 = undefined;
        var extracted_offset2: i32 = undefined;
        var extracted_offset3: i32 = undefined;
        try std.testing.expect(patternMatchBytes(.{
            0x50, // push rax
            0x48, 0x8b, 0x05, &extracted_offset1, // mov rax, [rip + {}]
            0x48, 0x8B, 0x00, // mov rax, [rax]
            0x48, 0x89, 0x05, &extracted_offset2, // mov [rip+{}], rax
            0x58, // pop rax
            0xFF, 0x15, &extracted_offset3, // call [rip+{}]
        }, res.code[read_offset..]));
        read_offset += 4 + @sizeOf(i32);
        const offset1: usize = @intCast(@as(isize, @intCast(read_offset)) + extracted_offset1);
        read_offset += 6 + @sizeOf(i32);
        const offset2: usize = @intCast(@as(isize, @intCast(read_offset)) + extracted_offset2);
        read_offset += 3 + @sizeOf(i32);
        const offset3: usize = @intCast(@as(isize, @intCast(read_offset)) + extracted_offset3);

        try std.testing.expectEqual(offset2, offset3);

        reused_offset = offset3;

        var addr: usize = undefined;
        try std.testing.expect(patternMatchBytes(.{&addr}, res.code[@intCast(offset1)..]));
        try std.testing.expectEqual(base + 18 + 0x10, addr);
    }
    // jmp [rip+0x10] ; jmp [rip+rel32]
    {
        var extracted_offset1: i32 = undefined;
        var extracted_offset2: i32 = undefined;
        var extracted_offset3: i32 = undefined;
        try std.testing.expect(patternMatchBytes(.{
            0x50, // push rax
            0x48, 0x8b, 0x05, &extracted_offset1, // mov rax, [rip + {}]
            0x48, 0x8B, 0x00, // mov rax, [rax]
            0x48, 0x89, 0x05, &extracted_offset2, // mov [rip+{}], rax
            0x58, // pop rax
            0xFF, 0x25, &extracted_offset3, // jmp [rip+{}]
        }, res.code[read_offset..]));
        read_offset += 4 + @sizeOf(i32);
        const offset1: usize = @intCast(@as(isize, @intCast(read_offset)) + extracted_offset1);
        read_offset += 6 + @sizeOf(i32);
        const offset2: usize = @intCast(@as(isize, @intCast(read_offset)) + extracted_offset2);
        read_offset += 3 + @sizeOf(i32);
        const offset3: usize = @intCast(@as(isize, @intCast(read_offset)) + extracted_offset3);

        try std.testing.expectEqual(offset2, offset3);
        try std.testing.expectEqual(reused_offset, offset2);

        var addr: usize = undefined;
        try std.testing.expect(patternMatchBytes(.{&addr}, res.code[@intCast(offset1)..]));
        try std.testing.expectEqual(base + 24 + 0x10, addr);
    }
}

test "cond jmp" {
    const code: []const u8 = &.{
        0x0f, 0x84, 0xfb, 0x00, 0x00, 0x00, // je 0xfb ; jmp rel32
        0x0f, 0x85, 0xfb, 0x00, 0x00, 0x00, // jne 0xfb ; jmp rel32
        0x74, 0x05, // je 5 ; jmp rel8
        0x75, 0xfB, // jne -5 ; jmp rel8
    };
    const base = @intFromPtr(code.ptr);

    var disasm = try Disassembler.create(.{});
    defer disasm.deinit();

    const res = try fix(std.testing.allocator, disasm.handle, code, 0);
    defer std.testing.allocator.free(res.code);

    // try std.testing.expectEqualSlices(u8, code, res.code);

    // Helper function to extract jump offset and target address
    const extract_jump_info = struct {
        fn rel32(fixed_code: []const u8, offset: *usize) struct { jmp_offset: usize, jmp_addr: usize } {
            @setRuntimeSafety(false);
            const jmp_offset: usize = @intCast(@as(*u32, @ptrFromInt(@intFromPtr(fixed_code[offset.*..].ptr))).*);
            const actual_jmp_offset = jmp_offset + offset.* + @sizeOf(u32);
            offset.* += @sizeOf(u32);
            const jmp_addr = @as(*usize, @ptrFromInt(@intFromPtr(fixed_code[actual_jmp_offset + 6 ..].ptr))).*;
            return .{ .jmp_offset = actual_jmp_offset, .jmp_addr = jmp_addr };
        }

        fn rel8(fixed_code: []const u8, offset: *usize) struct { jmp_offset: usize, jmp_addr: usize } {
            @setRuntimeSafety(false);
            const jmp_offset: usize = @intCast(@as(*i8, @ptrFromInt(@intFromPtr(fixed_code[offset.*..].ptr))).*);
            const actual_jmp_offset = jmp_offset + offset.* + @sizeOf(i8);
            offset.* += @sizeOf(i8);
            const jmp_addr = @as(*usize, @ptrFromInt(@intFromPtr(fixed_code[actual_jmp_offset + 6 ..].ptr))).*;
            return .{ .jmp_offset = actual_jmp_offset, .jmp_addr = jmp_addr };
        }
    };

    var read_offset: usize = 0;

    // Test je rel32 (0x0f 0x84)
    {
        const original_size = 6;
        try std.testing.expectEqualSlices(u8, &[_]u8{ 0x0f, 0x84 }, res.code[read_offset .. read_offset + 2]);
        read_offset += 2;

        const jump_info = extract_jump_info.rel32(res.code, &read_offset);
        try std.testing.expectEqual(0x0a + read_offset, jump_info.jmp_offset);
        try std.testing.expectEqual(base + original_size + 0xfb, jump_info.jmp_addr);
    }

    // Test jne rel32 (0x0f 0x85)
    {
        const original_size = 6;
        try std.testing.expectEqualSlices(u8, &[_]u8{ 0x0f, 0x85 }, res.code[read_offset .. read_offset + 2]);
        read_offset += 2;

        const jump_info = extract_jump_info.rel32(res.code, &read_offset);
        try std.testing.expectEqual(0x12 + read_offset, jump_info.jmp_offset);
        try std.testing.expectEqual(base + original_size * 2 + 0xfb, jump_info.jmp_addr);
    }

    // Test je rel8 (0x74)
    {
        const original_size = 2;
        try std.testing.expectEqualSlices(u8, &[_]u8{0x74}, res.code[read_offset .. read_offset + 1]);
        read_offset += 1;

        const jump_info = extract_jump_info.rel8(res.code, &read_offset);
        try std.testing.expectEqual(0x1e + read_offset, jump_info.jmp_offset);
        try std.testing.expectEqual(base + 6 * 2 + original_size + 0x05, jump_info.jmp_addr);
    }

    // Test jne rel8 negative offset (0x75)
    {
        const original_size = 2;
        try std.testing.expectEqualSlices(u8, &[_]u8{0x75}, res.code[read_offset .. read_offset + 1]);
        read_offset += 1;

        const jump_info = extract_jump_info.rel8(res.code, &read_offset);
        try std.testing.expectEqual(0x2a + read_offset, jump_info.jmp_offset);
        try std.testing.expectEqual(base + 6 * 2 + original_size * 2 - 0x05, jump_info.jmp_addr);
    }
}

test "lea" {
    @setRuntimeSafety(false);
    const code: []const u8 = &.{
        0x48, 0x8d, 0x05, 0xfb, 0x00, 0x00, 0x00, // lea rax, [rip+0xfb] ; lea rel32
        0x4c, 0x8d, 0x1d, 0xfb, 0x00, 0x00, 0x00, // lea r11, [rip+0xfb] ; lea rel32
    };
    const base = @intFromPtr(code.ptr);

    var disasm = try Disassembler.create(.{});
    defer disasm.deinit();

    const res = try fix(std.testing.allocator, disasm.handle, code, 0);
    defer std.testing.allocator.free(res.code);

    var read_offset: usize = 0;

    // Test lea rax, [rip+rel32]
    {
        try std.testing.expectEqualSlices(u8, &[_]u8{ 0x48, 0xb8 }, res.code[read_offset .. read_offset + 2]);
        read_offset += 2;

        const full_addr = @as(*usize, @ptrFromInt(@intFromPtr(res.code[read_offset..].ptr))).*;
        read_offset += @sizeOf(usize);
        try std.testing.expectEqual(base + 7 + 0xfb, full_addr);
    }

    // Test lea rdx, [rip+rel32]
    {
        try std.testing.expectEqualSlices(u8, &[_]u8{ 0x49, 0xbb }, res.code[read_offset .. read_offset + 2]);
        read_offset += 2;

        const full_addr = @as(*usize, @ptrFromInt(@intFromPtr(res.code[read_offset..].ptr))).*;
        read_offset += @sizeOf(usize);
        try std.testing.expectEqual(base + 14 + 0xfb, full_addr);
    }
}

test "mov rax,[rip+rel32]" {
    @setRuntimeSafety(false);
    const code: []const u8 = &.{
        0x48, 0x8b, 0x05, 0xfb, 0x00, 0x00, 0x00, // mov rax, [rip+0xfb] ; mov rax, [rip+rel32]
    };
    const base = @intFromPtr(code.ptr);

    var disasm = try Disassembler.create(.{});
    defer disasm.deinit();

    const res = try fix(std.testing.allocator, disasm.handle, code, 0);
    defer std.testing.allocator.free(res.code);

    //try std.testing.expectEqualSlices(u8, code, res.fixed_code);

    var read_offset: usize = 0;

    // Test mov rax, [rip+rel32]
    try std.testing.expectEqualSlices(u8, &[_]u8{0x50}, res.code[read_offset .. read_offset + 1]);
    read_offset += 1;

    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x48, 0xb8 }, res.code[read_offset .. read_offset + 2]);
    read_offset += 2;

    const full_addr = @as(*usize, @ptrFromInt(@intFromPtr(res.code[read_offset..].ptr))).*;
    read_offset += @sizeOf(usize);
    try std.testing.expectEqual(base + 7 + 0xfb, full_addr);

    var expected_bytes: std.ArrayList(u8) = std.ArrayList(u8).init(std.testing.allocator);
    defer expected_bytes.deinit();

    try expected_bytes.appendSlice(&.{
        0x50, // push rax
        0x48, 0xB8, // mov rax, {}
    });
    var addr_offset = expected_bytes.items.len;
    try expected_bytes.appendNTimes(0, @sizeOf(usize));
    @as(*usize, @ptrFromInt(@intFromPtr(expected_bytes.items[addr_offset..].ptr))).* = base + 7 + 0xfb;
    try expected_bytes.appendSlice(&.{
        0x48, 0x8B, 0x00, // mov rax, [rax]
        0x48, 0x89, 0x05, 0x20, 0x00, 0x00, 0x00, // mov [rip+0x20], rax
        0x58, // pop rax
        0x48, 0x8B, 0x05, 0x18, 0x00, 0x00, 0x00, // mov rax, [rip+0x18]
        0x50, // push rax
        0x48, 0x8B, 0x05, 0x10, 0x00, 0x00, 0x00, // mov rax, [rip+0x10]
        0x51, // push rcx
        0x48, 0xB9, // mov rcx, {}
    });
    addr_offset = expected_bytes.items.len;
    try expected_bytes.appendNTimes(0, @sizeOf(usize));
    @as(*usize, @ptrFromInt(@intFromPtr(expected_bytes.items[addr_offset..].ptr))).* = base + 7 + 0xfb;
    try expected_bytes.appendSlice(&.{
        0x48, 0x89, 0x01, // mov [rcx], rax
        0x59, // pop rcx
        0x58, // pop rax
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // data storage (8 bytes)
    });
    try std.testing.expectEqualSlices(u8, expected_bytes.items, res.code);
}

test "mov [rip+rel32],rax" {
    @setRuntimeSafety(false);
    const code: []const u8 = &.{
        0x48, 0x89, 0x05, 0xfb, 0x00, 0x00, 0x00, // mov [rip+0xfb], rax ; mov [rip+rel32], rax
    };
    const base = @intFromPtr(code.ptr);

    var disasm = try Disassembler.create(.{});
    defer disasm.deinit();

    const res = try fix(std.testing.allocator, disasm.handle, code, 0);
    defer std.testing.allocator.free(res.code);

    // try std.testing.expectEqualSlices(u8, code, res.fixed_code);

    var read_offset: usize = 0;

    // Test mov [rip+rel32], rax
    try std.testing.expectEqualSlices(u8, &[_]u8{0x50}, res.code[read_offset .. read_offset + 1]);
    read_offset += 1;

    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x48, 0xb8 }, res.code[read_offset .. read_offset + 2]);
    read_offset += 2;

    const full_addr = @as(*usize, @ptrFromInt(@intFromPtr(res.code[read_offset..].ptr))).*;
    read_offset += @sizeOf(usize);
    try std.testing.expectEqual(base + 7 + 0xfb, full_addr);

    var expected_bytes: std.ArrayList(u8) = std.ArrayList(u8).init(std.testing.allocator);
    defer expected_bytes.deinit();

    try expected_bytes.appendSlice(&.{
        0x50, // push rax
        0x48, 0xB8, // mov rax, {}
    });
    var addr_offset = expected_bytes.items.len;
    try expected_bytes.appendNTimes(0, @sizeOf(usize));
    @as(*usize, @ptrFromInt(@intFromPtr(expected_bytes.items[addr_offset..].ptr))).* = base + 7 + 0xfb;
    try expected_bytes.appendSlice(&.{
        0x48, 0x8B, 0x00, // mov rax, [rax]
        0x48, 0x89, 0x05, 0x20, 0x00, 0x00, 0x00, // mov [rip+0x20], rax
        0x58, // pop rax
        0x48, 0x89, 0x05, 0x18, 0x00, 0x00, 0x00, // mov [rip+0x18], rax
        0x50, // push rax
        0x48, 0x8B, 0x05, 0x10, 0x00, 0x00, 0x00, // mov rax, [rip+0x10]
        0x51, // push rcx
        0x48, 0xB9, // mov rcx, {}
    });
    addr_offset = expected_bytes.items.len;
    try expected_bytes.appendNTimes(0, @sizeOf(usize));
    @as(*usize, @ptrFromInt(@intFromPtr(expected_bytes.items[addr_offset..].ptr))).* = base + 7 + 0xfb;
    try expected_bytes.appendSlice(&.{
        0x48, 0x89, 0x01, // mov [rcx], rax
        0x59, // pop rcx
        0x58, // pop rax
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // data storage (8 bytes)
    });
    try std.testing.expectEqualSlices(u8, expected_bytes.items, res.code);
}

test "dec [rip+rel32]" {
    @setRuntimeSafety(false);
    const code: []const u8 = &.{
        0x48, 0xFF, 0x0D, 0x00, 0x01, 0x00, 0x00, // dec [rip+0x100] ; dec [rip+rel32]
    };
    const base = @intFromPtr(code.ptr);

    var disasm = try Disassembler.create(.{});
    defer disasm.deinit();

    const res = try fix(std.testing.allocator, disasm.handle, code, 0);
    defer std.testing.allocator.free(res.code);

    //try std.testing.expectEqualSlices(u8, code, res.fixed_code);

    var read_offset: usize = 0;

    // Test sub [rip+rel32], rax
    try std.testing.expectEqualSlices(u8, &[_]u8{0x50}, res.code[read_offset .. read_offset + 1]);
    read_offset += 1;

    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x48, 0xb8 }, res.code[read_offset .. read_offset + 2]);
    read_offset += 2;

    const full_addr = @as(*usize, @ptrFromInt(@intFromPtr(res.code[read_offset..].ptr))).*;
    read_offset += @sizeOf(usize);
    try std.testing.expectEqual(base + 7 + 0x100, full_addr);

    var expected_bytes: std.ArrayList(u8) = std.ArrayList(u8).init(std.testing.allocator);
    defer expected_bytes.deinit();

    try expected_bytes.appendSlice(&.{
        0x50, // push rax
        0x48, 0xB8, // mov rax, {}
    });
    var addr_offset = expected_bytes.items.len;
    try expected_bytes.appendNTimes(0, @sizeOf(usize));
    @as(*usize, @ptrFromInt(@intFromPtr(expected_bytes.items[addr_offset..].ptr))).* = base + 7 + 0x100;
    try expected_bytes.appendSlice(&.{
        0x48, 0x8B, 0x00, // mov rax, [rax]
        0x48, 0x89, 0x05, 0x20, 0x00, 0x00, 0x00, // mov [rip+0x20], rax
        0x58, // pop rax
        0x48, 0xFF, 0x0D, 0x18, 0x00, 0x00, 0x00, // dec qword [rip+0x18]
        0x50, // push rax
        0x48, 0x8B, 0x05, 0x10, 0x00, 0x00, 0x00, // mov rax, [rip+0x10]
        0x51, // push rcx
        0x48, 0xB9, // mov rcx, {}
    });
    addr_offset = expected_bytes.items.len;
    try expected_bytes.appendNTimes(0, @sizeOf(usize));
    @as(*usize, @ptrFromInt(@intFromPtr(expected_bytes.items[addr_offset..].ptr))).* = base + 7 + 0x100;
    try expected_bytes.appendSlice(&.{
        0x48, 0x89, 0x01, // mov [rcx], rax
        0x59, // pop rcx
        0x58, // pop rax
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // data storage (8 bytes)
    });
    try std.testing.expectEqualSlices(u8, expected_bytes.items, res.code);
}

test "mixed" {
    @setRuntimeSafety(false);
    // zig fmt: off
    const code: []const u8 = &.{
        0x51, // push rcx
        0xFF, 0x15, 0x00, 0x01, 0x00, 0x00, // call [rip+0x100]
        0x48, 0x8d, 0x05, 0xfb, 0x00, 0x00, 0x00, // lea rax, [rip+0xfb]
        0x48, 0x8B, 0x0D, 0xFF, 0x00, 0x00, 0x00, // mov rcx, [rip+0xff]
        0xE8, 0xF5, 0x01, 0x00, 0x00, // call 0x200 (relative)
        0x48, 0xFF, 0x05, 0xFF, 0x00, 0x00, 0x00, // inc qword [rip+0xff]
        0x59, // pop rcx
        0x74, 0xFD, // je 0xff (relative, assuming backwards jump)
        0xFF, 0x25, 0xFF, 0x00, 0x00, 0x00, // jmp [rip+0xff]
    };
    // zig fmt: on
    const base = @intFromPtr(code.ptr);

    var disasm = try Disassembler.create(.{});
    defer disasm.deinit();

    const res = try fix(std.testing.allocator, disasm.handle, code, 14);
    defer std.testing.allocator.free(res.code);

    //try std.testing.expectEqualSlices(u8, code, res.fixed_code);
    //try std.testing.expectEqualSlices(u8, code, res.fixed_code[0..res.reserved_offset]);
    //try std.testing.expectEqualSlices(u8, code, res.fixed_code[res.reserved_offset..]);

    var exptected_bytes: std.ArrayList(u8) = std.ArrayList(u8).init(std.testing.allocator);
    defer exptected_bytes.deinit();

    try exptected_bytes.appendSlice(&.{
        0x51, // push rcx
        0x50, // push rax
        0x48, 0x8B, 0x05, 0xB5, 0x00, 0x00, 0x00, // mov rax, qword ptr [rip+0xB5]
        0x48, 0x8B, 0x00, // mov rax, qword ptr [rax]
        0x48, 0x89, 0x05, 0xB3, 0x00, 0x00, 0x00, // mov qword ptr [rip+0xB3], rax
        0x58, // pop rax
        0xFF, 0x15, 0xAC, 0x00, 0x00, 0x00, // call qword ptr [rip+0xAC]
        0x48, 0xB8, // mov rax, {}
    });
    try exptected_bytes.appendNTimes(0, @sizeOf(usize));
    @as(*usize, @ptrFromInt(@intFromPtr(exptected_bytes.items[exptected_bytes.items.len - @sizeOf(usize) ..].ptr))).* = base + 14 + 0xFB;

    try exptected_bytes.appendSlice(&.{
        0x50, // push rax
        0x48, 0xB8, // mov rax, {}
    });
    try exptected_bytes.appendNTimes(0, @sizeOf(usize));
    @as(*usize, @ptrFromInt(@intFromPtr(exptected_bytes.items[exptected_bytes.items.len - @sizeOf(usize) ..].ptr))).* = base + 21 + 0xFF;

    try exptected_bytes.appendSlice(&.{
        0x48, 0x8B, 0x00, // mov rax, qword ptr [rax]
        0x48, 0x89, 0x05, 0x8D, 0x00, 0x00, 0x00, // mov qword ptr [rip+0x8D], rax
        0x58, // pop rax
        0x48, 0x8B, 0x0D, 0x85, 0x00, 0x00, 0x00, // mov rcx, qword ptr [rip+0x85]
        0x50, // push rax
        0x48, 0x8B, 0x05, 0x7D, 0x00, 0x00, 0x00, // mov rax, qword ptr [rip+0x7D]
        0x51, // push rcx
        0x48, 0xB9, // mov rcx, {}
    });
    try exptected_bytes.appendNTimes(0, @sizeOf(usize));
    @as(*usize, @ptrFromInt(@intFromPtr(exptected_bytes.items[exptected_bytes.items.len - @sizeOf(usize) ..].ptr))).* = base + 21 + 0xFF;

    try exptected_bytes.appendSlice(&.{
        0x48, 0x89, 0x01, // mov qword ptr [rcx], rax
        0x59, // pop rcx
        0x58, // pop rax
        0xFF, 0x15, 0x6F, 0x00, 0x00, 0x00, // call qword ptr [rip+0x6F]
        0x50, // push rax
        0x48, 0xB8, // mov rax, {}
    });
    try exptected_bytes.appendNTimes(0, @sizeOf(usize));
    @as(*usize, @ptrFromInt(@intFromPtr(exptected_bytes.items[exptected_bytes.items.len - @sizeOf(usize) ..].ptr))).* = base + 33 + 0xFF;

    try exptected_bytes.appendSlice(&.{
        0x48, 0x8B, 0x00, // mov rax, qword ptr [rax]
        0x48, 0x89, 0x05, 0x52, 0x00, 0x00, 0x00, // mov qword ptr [rip+0x52], rax
        0x58, // pop rax
        0x48, 0xFF, 0x05, 0x4A, 0x00, 0x00, 0x00, // inc qword ptr [rip+0x4A]
        0x50, // push rax
        0x48, 0x8B, 0x05, 0x42, 0x00, 0x00, 0x00, // mov rax, qword ptr [rip+0x42]
        0x51, // push rcx
        0x48, 0xB9, // mov rcx, {}
    });
    try exptected_bytes.appendNTimes(0, @sizeOf(usize));
    @as(*usize, @ptrFromInt(@intFromPtr(exptected_bytes.items[exptected_bytes.items.len - @sizeOf(usize) ..].ptr))).* = base + 33 + 0xFF;

    try exptected_bytes.appendSlice(&.{
        0x48, 0x89, 0x01, // mov qword ptr [rcx], rax
        0x59, // pop rcx
        0x58, // pop rax
        0x59, // pop rcx
        0x74, 0x3F, // jz +0x3F
        0x50, // push rax
        0x48, 0x8B, 0x05, 0x45, 0x00, 0x00, 0x00, // mov rax, qword ptr [rip+0x45]
        0x48, 0x8B, 0x00, // mov rax, qword ptr [rax]
        0x48, 0x89, 0x05, 0x1D, 0x00, 0x00, 0x00, // mov qword ptr [rip+0x1D], rax
        0x58, // pop rax
        0xFF, 0x25, 0x16, 0x00, 0x00, 0x00, // jmp qword ptr [rip+0x16]
        0x90, 0x90, 0x90, 0x90, 0x90, 0x90,
        0x90, 0x90, 0x90, 0x90, 0x90, 0x90,
        0x90,
    });

    try std.testing.expectEqualSlices(u8, exptected_bytes.items, res.code[0..exptected_bytes.items.len]);
}

test "call [rdx]" {
    const code: []const u8 = &.{
        0x48, 0x8B, 0x16, 0x48, 0x8B, 0xCE, 0x48, 0x8B, 0xF8, 0xFF, 0x12, 0x48, 0x3B, 0xF8,
    };
    //const base = @intFromPtr(code.ptr);

    var disasm = try Disassembler.create(.{});
    defer disasm.deinit();

    const res = try fix(std.testing.allocator, disasm.handle, code, 14);
    defer std.testing.allocator.free(res.code);

    try std.testing.expectEqualSlices(u8, &[_]u8{
        0x48, 0x8B, 0x16, 0x48, 0x8B, 0xCE, 0x48, 0x8B, 0xF8, 0xFF, 0x12, 0x48, 0x3B, 0xF8,
        0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90,
    }, res.code);
}
