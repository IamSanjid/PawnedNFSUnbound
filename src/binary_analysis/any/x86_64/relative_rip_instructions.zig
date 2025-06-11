const std = @import("std");

const Disassembler = @import("disasm").x86_64;
const cs = Disassembler.cs;

pub const FixedCode = struct {
    code: []const u8,
    reserved_offset: usize,
};

const FixedCodeRef = struct {
    write_offset: usize,
    write_size: usize,
    start_offset: usize,
    end_offset: usize,
};

const FixedCodeWriter = struct {
    code: []const u8,
    buf: std.ArrayList(u8),
    new_buf: std.ArrayList(u8),
    refs: std.ArrayList(FixedCodeRef),
    reuse_refs: std.ArrayList(usize),
    current_offset: usize = 0,

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
        };
    }

    fn remainingSize(self: FCWSelf) usize {
        return self.code[self.current_offset..].len;
    }

    fn size(self: FCWSelf) usize {
        return self.buf.items.len + self.new_buf.items.len;
    }

    fn replacing(self: *FCWSelf, ins: *const cs.Insn) *FCWSelf {
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

    fn addValueRef(self: *FCWSelf, comptime OffsetType: type, value: usize) *FCWSelf {
        @setRuntimeSafety(false);
        const end_offset = self.new_buf.items.len;
        self.new_buf.appendNTimes(0, @sizeOf(usize)) catch @panic("OOM");
        @as(*usize, @ptrFromInt(@intFromPtr(self.new_buf.items[end_offset..].ptr))).* = value;

        const write_offset = self.buf.items.len;
        self.buf.appendNTimes(0, @sizeOf(OffsetType)) catch @panic("OOM");

        self.refs.append(FixedCodeRef{
            .write_size = @sizeOf(OffsetType),
            .write_offset = write_offset,
            .start_offset = self.buf.items.len,
            .end_offset = end_offset,
        }) catch @panic("OOM");

        return self;
    }

    fn addSliceRef(self: *FCWSelf, comptime OffsetType: type, slice: []const u8) *FCWSelf {
        const end_offset = self.new_buf.items.len;
        self.new_buf.appendSlice(slice) catch @panic("OOM");

        const write_offset = self.buf.items.len;
        self.buf.appendNTimes(0, @sizeOf(OffsetType)) catch @panic("OOM");

        self.refs.append(FixedCodeRef{
            .write_size = @sizeOf(OffsetType),
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
        self.buf.appendNTimes(0, @sizeOf(i32)) catch @panic("OOM");

        self.refs.append(FixedCodeRef{
            .write_size = @sizeOf(i32),
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
        try self.buf.appendSlice(self.new_buf.items);

        for (self.refs.items) |ref| {
            const added_bytes_len = new_code_offset - ref.start_offset;
            const new_offset = added_bytes_len + ref.end_offset;
            if (ref.write_size == 4) {
                @as(*i32, @ptrFromInt(@intFromPtr(self.buf.items[ref.write_offset..].ptr))).* = @intCast(new_offset);
            } else if (ref.write_size == 1) {
                @as(*i8, @ptrFromInt(@intFromPtr(self.buf.items[ref.write_offset..].ptr))).* = @intCast(new_offset);
            } else {
                unreachable;
            }
        }

        return .{
            .code = try self.buf.toOwnedSlice(),
            .reserved_offset = new_code_offset,
        };
    }
};

fn fixCallJmpIns(ins: *const cs.Insn, comptime call: bool, writer: *FixedCodeWriter) void {
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
        _ = writer
            .replacing(ins)
            .append(&.{
                0x50, // push rax
                0x48, 0x8B, 0x05, // mov rax, [rip + {}]
            })
            .addValueRef(i32, target_address)
            .append(&.{
                0x48, 0x8B, 0x00, // mov rax, [rax]
                0x48, 0x89, 0x05, // mov [rip+{reuse0}], rax
            })
            .addReuseRef(0)
            .append(&.{
                0x58, // pop rax
                0xFF, opcode, // call/jmp [rip+reuse0]
            })
            .addReuseRef(0);
    } else {
        _ = writer
            .replacing(ins)
            .append(&.{
                0xFF, opcode, // call/jmp [rip+{}]
            })
            .addValueRef(i32, target_address);
    }
}

fn fixCondJmpIns(ins: *const cs.Insn, writer: *FixedCodeWriter) void {
    @setRuntimeSafety(false);
    const detail = ins.detail orelse unreachable;
    const x86 = detail.arch.x86;
    const displacement = Disassembler.findDisplacement(ins) orelse unreachable;

    const target_address: usize = @intCast(@as(isize, @intCast(ins.address)) + ins.size + displacement.value);

    _ = writer.replacing(ins);

    const do_rel32 = displacement.size >= 4 or blk: {
        const worst_case_size = writer.new_buf.items.len + ((writer.remainingSize() / 6) * 25);
        if (std.math.maxInt(i8) < worst_case_size) break :blk true;
        break :blk false;
    };

    var jmp_bytes: [14]u8 = .{
        0xFF, 0x25, 0x00, 0x00, 0x00, 0x00, // jmp [rip+0]
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // address 64bit value
    };
    @as(*usize, @ptrFromInt(@intFromPtr(jmp_bytes[6..].ptr))).* = target_address;

    // zig fmt: off
    if (do_rel32) {
        const opcode = if (x86.opcode[0] & 0x70 != 0x00) 0x80 | (x86.opcode[0] & 0x0F) else x86.opcode[1];

        _ = writer
            .append(&.{
                0x0F,
                opcode,
            })
            .addSliceRef(i32, &jmp_bytes);
    } else {
        _ = writer
            .append(&.{
                x86.opcode[0],
            })
            .addSliceRef(i8, &jmp_bytes);
    }
    // zig fmt: on
}

pub fn fixMovIns(ins: *const cs.Insn, writer: *FixedCodeWriter) void {
    @setRuntimeSafety(false);
    const detail = ins.detail orelse unreachable;
    const x86 = detail.arch.x86;
    const displacement = Disassembler.findDisplacement(ins) orelse unreachable;

    const target_address: usize = @intCast(@as(isize, @intCast(ins.address)) + ins.size + displacement.value);

    if (ins.id == cs.c.X86_INS_LEA) {
        const r7_reg = x86.rex == 0x48;
        const mov_rex: u8 = if (r7_reg) 0x48 else 0x49;
        const mov_opcode = 0xB8 + ((x86.modrm >> 3) & 0x07); // Extract bits 5-3
        var bytes: [10]u8 = .{
            mov_rex, // rex
            mov_opcode, // mov opcode
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // Placeholder for the address
        };
        @as(*usize, @ptrFromInt(@intFromPtr(bytes[2..].ptr))).* = target_address;
        _ = writer
            .replacing(ins)
            .append(&bytes);
    } else {
        // TODO: Optimize it... Doesn't support avx/simd floating point movs...
        const disp_offset = x86.encoding.disp_offset;
        const disp_size = x86.encoding.disp_size;
        std.debug.assert(disp_offset > 0);
        const start = ins.bytes[0..disp_offset];
        const end = ins.bytes[disp_offset + disp_size .. ins.size];
        var bytes: [17]u8 = .{
            0x50, // push rax
            0x48, 0xB8, // mov rax, {}
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // Placeholder for the address
            0x48, 0x8B, 0x00, // mov rax, [rax]
            0x48, 0x89, 0x05, // mov [rip+{reuse0}], rax
        };
        @as(*usize, @ptrFromInt(@intFromPtr(bytes[3..].ptr))).* = target_address;
        var ending_bytes: [16]u8 = .{
            0x51, // push rcx
            0x48, 0xB9, // mov rcx, {}
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // Placeholder for the address
            0x48, 0x89, 0x01, // mov [rcx], rax
            0x59, // pop rcx
            0x58, // pop rax
        };
        @as(*usize, @ptrFromInt(@intFromPtr(ending_bytes[3..].ptr))).* = target_address;
        _ = writer
            .replacing(ins)
            .append(&bytes)
            .addReuseRef(0)
            .append(&.{
                0x58, // pop rax
            })
            .append(start)
            .addReuseRef(0)
            .append(end)
            .append(&.{
                0x50, // push rax
                0x48, 0x8B, 0x05, // mov rax, [rip + {}]
            })
            .addReuseRef(0)
            .append(&ending_bytes);
    }
}

pub fn fix(allocator: std.mem.Allocator, disasm_iter_res: Disassembler.DisasmIterResult, reserve: usize) !FixedCode {
    @setRuntimeSafety(false);

    var tmp_detail: cs.Detail = undefined;
    var tmp_ins: cs.Insn = undefined;
    tmp_ins.detail = &tmp_detail;
    var iter = disasm_iter_res.csIter(&tmp_ins);

    var writer = try FixedCodeWriter.init(allocator, disasm_iter_res.code, reserve);
    while (iter.next()) |ins| {
        const detail = ins.detail orelse unreachable;

        const ins_type = Disassembler.detectInstructionType(ins.id, detail);
        if (!Disassembler.isRipRelativeInstruction(ins, ins_type)) continue;

        if (ins_type == .CALL) {
            fixCallJmpIns(ins, true, &writer);
        } else if (ins_type == .JMP) {
            fixCallJmpIns(ins, false, &writer);
        } else if (ins_type == .JMP_COND) {
            fixCondJmpIns(ins, &writer);
        } else {
            fixMovIns(ins, &writer);
        }
    }

    return writer.finalize();
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

    const disasm_iter_res = disasm.disasmIter(code, .{});

    const res = try fix(std.testing.allocator, disasm_iter_res, 0);
    defer std.testing.allocator.free(res.code);

    var read_offset: usize = 0;
    var ins_size: usize = 0;
    var jmp_offset: usize = 0;
    var jmp_addr: usize = 0;

    //try std.testing.expectEqualSlices(u8, code, res.fixed_code);

    ins_size = 2 + @sizeOf(u32);

    // call 0xfb ; call rel32
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0xff, 0x15 }, res.code[read_offset .. read_offset + 2]);
    read_offset += 2;

    jmp_offset = @as(*u32, @ptrFromInt(@intFromPtr(res.code[read_offset..].ptr))).* + read_offset + @sizeOf(u32);
    read_offset += @sizeOf(u32);
    try std.testing.expectEqual(0x3e + read_offset, jmp_offset);

    jmp_addr = @as(*usize, @ptrFromInt(@intFromPtr(res.code[jmp_offset..].ptr))).*;
    try std.testing.expectEqual(base + 5 + 0xfb, jmp_addr);

    // jmp 0x0e ; jmp rel8
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0xff, 0x25 }, res.code[read_offset .. read_offset + 2]);
    read_offset += 2;

    jmp_offset = @as(*u32, @ptrFromInt(@intFromPtr(res.code[8..].ptr))).* + read_offset + @sizeOf(u32);
    read_offset += @sizeOf(u32);
    try std.testing.expectEqual(0x40 + read_offset, jmp_offset);

    jmp_addr = @as(*usize, @ptrFromInt(@intFromPtr(res.code[jmp_offset..].ptr))).*;
    try std.testing.expectEqual(base + 7 + 0x0e, jmp_addr);

    // jmp 0xfb ; jmp rel32
    jmp_addr = @as(*usize, @ptrFromInt(@intFromPtr(res.code[jmp_offset + @sizeOf(usize) ..].ptr))).*;
    try std.testing.expectEqual(base + 12 + 0xfb, jmp_addr);
    read_offset += ins_size;

    ins_size = 25;
    // call [rip+0x10] ; call [rip+rel32]
    try std.testing.expectEqualSlices(u8, &[_]u8{
        0x50, // push rax
        0x48, 0x8b, 0x05, // mov rax, [rip + {}]
    }, res.code[read_offset .. read_offset + 4]);
    read_offset += 4;

    jmp_offset = @as(*u32, @ptrFromInt(@intFromPtr(res.code[read_offset..].ptr))).* + read_offset + @sizeOf(u32);
    read_offset += @sizeOf(u32);
    try std.testing.expectEqual(0x42 + read_offset, jmp_offset);

    jmp_addr = @as(*usize, @ptrFromInt(@intFromPtr(res.code[jmp_offset..].ptr))).*;
    try std.testing.expectEqual(base + 18 + 0x10, jmp_addr);
    read_offset += ins_size - 4 - @sizeOf(u32);
    try std.testing.expectEqual(0x15, res.code[read_offset - @sizeOf(u32) - 1]);
    const last_reused_offset = @as(*u32, @ptrFromInt(@intFromPtr(res.code[read_offset - @sizeOf(u32) ..].ptr))).* + read_offset;

    // jmp [rip+0x10] ; jmp [rip+rel32]
    try std.testing.expectEqualSlices(u8, &[_]u8{
        0x50, // push rax
        0x48, 0x8b, 0x05, // mov rax, [rip + {}]
    }, res.code[read_offset .. read_offset + 4]);
    read_offset += 4;

    jmp_offset = @as(*u32, @ptrFromInt(@intFromPtr(res.code[read_offset..].ptr))).* + read_offset + @sizeOf(u32);
    read_offset += @sizeOf(u32);
    try std.testing.expectEqual(0x39 + read_offset, jmp_offset);

    jmp_addr = @as(*usize, @ptrFromInt(@intFromPtr(res.code[jmp_offset..].ptr))).*;
    try std.testing.expectEqual(base + 24 + 0x10, jmp_addr);
    read_offset += ins_size - 4 - @sizeOf(u32);
    try std.testing.expectEqual(0x25, res.code[read_offset - @sizeOf(u32) - 1]);
    const reused_offset = @as(*u32, @ptrFromInt(@intFromPtr(res.code[read_offset - @sizeOf(u32) ..].ptr))).* + read_offset;
    try std.testing.expectEqual(last_reused_offset, reused_offset);
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

    const disasm_iter_res = disasm.disasmIter(code, .{});

    const res = try fix(std.testing.allocator, disasm_iter_res, 0);
    defer std.testing.allocator.free(res.code);

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

    const disasm_iter_res = disasm.disasmIter(code, .{});

    const res = try fix(std.testing.allocator, disasm_iter_res, 0);
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

    const disasm_iter_res = disasm.disasmIter(code, .{});

    const res = try fix(std.testing.allocator, disasm_iter_res, 0);
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

    const disasm_iter_res = disasm.disasmIter(code, .{});

    const res = try fix(std.testing.allocator, disasm_iter_res, 0);
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

    const disasm_iter_res = disasm.disasmIter(code, .{});

    const res = try fix(std.testing.allocator, disasm_iter_res, 0);
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

    const disasm_iter_res = disasm.disasmIter(code, .{});

    const res = try fix(std.testing.allocator, disasm_iter_res, 14);
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

    const disasm_iter_res = disasm.disasmIter(code, .{});

    const res = try fix(std.testing.allocator, disasm_iter_res, 14);
    defer std.testing.allocator.free(res.code);

    try std.testing.expectEqualSlices(u8, &[_]u8{
        0x48, 0x8B, 0x16, 0x48, 0x8B, 0xCE, 0x48, 0x8B, 0xF8, 0xFF, 0x12, 0x48, 0x3B, 0xF8,
        0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90,
    }, res.code);
}
