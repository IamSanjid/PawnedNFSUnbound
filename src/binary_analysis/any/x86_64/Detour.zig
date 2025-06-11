const std = @import("std");

const any = @import("../any.zig");
const trampoline = any.trampoline;
const disasm = @import("disasm");

const emitAbsoluteJmp = any.x86_64.trampoline.emitAbsoluteJmp;

pub const absolute_jmp_size = std.mem.alignForward(usize, 14, @sizeOf(usize));
pub const Errors = error{
    OverwriteBoundaryNotFound,
    NotFound,
};

pub const JumpEntry = struct {
    detour_jmp: []u8,
    next_jmp: []u8,

    fn create() !@This() {
        const raw = try trampoline.alloc(absolute_jmp_size * 2);
        return .{
            .detour_jmp = raw[0..absolute_jmp_size],
            .next_jmp = raw[absolute_jmp_size..],
        };
    }

    fn flush(self: @This()) void {
        const addr: [*]u8 = self.detour_jmp.ptr;
        any.clearInstructionCache(addr[0 .. absolute_jmp_size * 2]);
    }

    fn destroy(self: @This()) void {
        // **UNSAFE** detour_jmp and next_jmp must be part of a contigious region
        trampoline.free(self.detour_jmp);
    }
};

pub const Attached = struct {
    /// Points to the hook chain trampoline. Basically the next address where
    /// the hook should jump back to for chain hook triggers.
    /// Chain hook can be disrupted by doing an early return/jumping to a different place
    /// other than this *trampoline* address.
    trampoline: usize,
    /// Points to the trampoline which has all the replaced instructions and jumps
    /// back to the original function.
    /// Useful when attaching at the start of a function, and caling that function
    /// from the detour function, or when trying to disrupt a chain of hooks just
    /// jump to this address.
    new_target: usize,
};

const JumpTable = std.AutoArrayHashMap(usize, JumpEntry);

const Info = struct {
    target: usize,
    jmp_table: JumpTable, // maintains insertion order!
    trampoline: []u8,
    original_code_offset: usize,
    overwritten_size: usize,
};

allocator: std.mem.Allocator,
attached: std.AutoArrayHashMap(usize, *Info),
disasmbler: disasm.x86_64,

const Self = @This();

pub fn init(allocator: std.mem.Allocator) !Self {
    const disasmbler = try disasm.x86_64.create(.{});
    return .{
        .allocator = allocator,
        .attached = .init(allocator),
        .disasmbler = disasmbler,
    };
}

pub fn attach(self: *Self, target: usize, detour: usize) !Attached {
    @setRuntimeSafety(false);

    const get_put_res = try self.attached.getOrPut(target);
    if (!get_put_res.found_existing) {
        const found_res = any.x86_64.safe_overwrite_boundary.find(self.disasmbler, target, 14) orelse {
            return Errors.OverwriteBoundaryNotFound;
        };

        const overwrite_bytes = found_res.safe_size;
        const original_code: []const u8 = @as([*]const u8, @ptrFromInt(target))[0..overwrite_bytes];
        const disasm_iter_res = found_res.disasm_iter_res;

        const fixed = try any.x86_64.relative_rip_instructions.fix(self.allocator, disasm_iter_res, 14);
        defer self.allocator.free(fixed.code);

        const code = fixed.code;
        const jmp_back_write_offset = fixed.reserved_offset;

        const ret_trampoline = try trampoline.alloc(code.len + original_code.len);
        errdefer trampoline.free(ret_trampoline);
        // copy the fixed/original code to the trampoline
        @memcpy(ret_trampoline, code);
        @memcpy(ret_trampoline[code.len..], original_code);

        const jmp_entry = try JumpEntry.create();
        errdefer jmp_entry.destroy();
        // kind of like a jmp table
        _ = try emitAbsoluteJmp(@intFromPtr(jmp_entry.detour_jmp.ptr), detour, absolute_jmp_size);
        _ = try emitAbsoluteJmp(@intFromPtr(jmp_entry.next_jmp.ptr), @intFromPtr(ret_trampoline.ptr), absolute_jmp_size);

        // check if original code is ending with jmp or ret instruction
        const ending_ins = any.x86_64.func_end.detect(disasm_iter_res);
        // overwrite the target instructions with jmp to trampoline
        const jmp_back_original = try emitAbsoluteJmp(target, @intFromPtr(jmp_entry.detour_jmp.ptr), overwrite_bytes);
        if (ending_ins) |end_ins| {
            std.debug.print("Ending pos: {}\n", .{end_ins});
        } else {
            // if there is no ending instruction, we need to write a jmp back to the original code
            _ = try emitAbsoluteJmp(@intFromPtr(ret_trampoline.ptr) + jmp_back_write_offset, jmp_back_original, null);
        }

        var jmp_table = JumpTable.init(self.allocator);
        try jmp_table.put(detour, jmp_entry);
        errdefer jmp_table.deinit();

        const new_info = try self.allocator.create(Info);
        errdefer self.allocator.destroy(new_info);

        new_info.* = Info{
            .target = target,
            .jmp_table = jmp_table,
            .trampoline = ret_trampoline,
            .original_code_offset = code.len,
            .overwritten_size = overwrite_bytes,
        };
        get_put_res.value_ptr.* = new_info;

        return .{
            .trampoline = @intFromPtr(jmp_entry.next_jmp.ptr),
            .new_target = @intFromPtr(ret_trampoline.ptr),
        };
    } else if (get_put_res.value_ptr.*.jmp_table.get(detour)) |jmp_entry| {
        return .{
            .trampoline = @intFromPtr(jmp_entry.next_jmp.ptr),
            .new_target = @intFromPtr(get_put_res.value_ptr.*.trampoline.ptr),
        };
    } else {
        const info = get_put_res.value_ptr.*;

        const jmp_table = info.jmp_table.values();
        const last_jmp_entry = jmp_table[jmp_table.len - 1];

        const new_jmp_entry = try JumpEntry.create();
        errdefer new_jmp_entry.destroy();
        @memcpy(new_jmp_entry.next_jmp, last_jmp_entry.next_jmp);

        try info.jmp_table.put(detour, new_jmp_entry);
        errdefer _ = info.jmp_table.orderedRemove(detour);

        // **UNSAFE** We're sure the previously allocated trampoline regions have enough space to store *absolute_jmp_size* bytes
        _ = try emitAbsoluteJmp(@intFromPtr(new_jmp_entry.detour_jmp.ptr), detour, absolute_jmp_size);
        _ = try emitAbsoluteJmp(@intFromPtr(last_jmp_entry.next_jmp.ptr), @intFromPtr(new_jmp_entry.detour_jmp.ptr), absolute_jmp_size);
        new_jmp_entry.flush();

        return .{
            .trampoline = @intFromPtr(new_jmp_entry.next_jmp.ptr),
            .new_target = @intFromPtr(info.trampoline.ptr),
        };
    }
}

pub fn detach(self: *Self, target: usize, detour: usize) !void {
    const info = self.attached.get(target) orelse return;
    const jmp_table = info.jmp_table.values();

    if (jmp_table.len <= 1) {
        // should be last or empty..
        const kv = info.jmp_table.fetchOrderedRemove(detour) orelse return;
        defer kv.value.destroy();
        if (info.original_code_offset > 0) {
            try trampoline.restore(target, info.trampoline[info.original_code_offset..]);
        }
        return;
    }

    const index = info.jmp_table.getIndex(detour) orelse return;
    const current_entry = jmp_table[index];
    defer current_entry.destroy();

    if (index == 0) {
        const next_entry = jmp_table[index + 1];
        _ = try emitAbsoluteJmp(target, @intFromPtr(next_entry.detour_jmp.ptr), info.overwritten_size);
        info.jmp_table.orderedRemoveAt(index);
        return;
    }

    const prev_entry = jmp_table[index - 1];
    @memcpy(prev_entry.next_jmp, current_entry.next_jmp);
    prev_entry.flush();
    info.jmp_table.orderedRemoveAt(index);
}

pub fn deinit(self: *Self) void {
    for (self.attached.values()) |info| {
        if (info.original_code_offset > 0) {
            trampoline.restore(info.target, info.trampoline[info.original_code_offset..]) catch {};
        }
        trampoline.free(info.trampoline);

        for (info.jmp_table.values()) |entry| {
            entry.destroy();
        }

        info.jmp_table.deinit();
        self.allocator.destroy(info);
    }
    self.attached.deinit();
}

test "usage" {
    @setRuntimeSafety(false);
    const allocator = std.testing.allocator;
    var detour = try Self.init(allocator);
    defer detour.deinit();

    var mut_code = [_]u8{
        0x55, // push rbp
        0x48, 0x89, 0xE5, // mov rbp, rsp
        0x48, 0x83, 0xEC, 0x20, // sub rsp, 0x20
        0x48, 0x89, 0x4D, 0x10, // mov [rbp+0x10], rcx
        0x48, 0x89, 0x55, 0x18, // mov [rbp+0x18], rdx
        0x90, 0x90, 0x90, 0x90, // nopes
    };
    const code: []u8 = &mut_code;

    const attached1 = try detour.attach(@intFromPtr(code.ptr), 0x1000);
    const attached2 = try detour.attach(@intFromPtr(code.ptr), 0x2000);
    try std.testing.expectEqual(attached1.new_target, attached2.new_target);

    const attached3 = try detour.attach(@intFromPtr(code.ptr), 0x3000);

    const info = detour.attached.get(@intFromPtr(code.ptr)) orelse unreachable;
    const jump_entry1 = info.jmp_table.get(0x1000) orelse unreachable;
    const jump_entry2 = info.jmp_table.get(0x2000) orelse unreachable;
    const jump_entry3 = info.jmp_table.get(0x3000) orelse unreachable;

    var expected = std.ArrayList(u8).init(allocator);
    defer expected.deinit();

    try expected.appendSlice(&.{
        0xFF, 0x25, 0x00, 0x00, 0x00, 0x00, // jmp [rip + 0x00]
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // raw address
    });
    @as(*usize, @ptrFromInt(@intFromPtr(expected.items[expected.items.len - @sizeOf(usize) ..].ptr))).* = @intFromPtr(jump_entry1.detour_jmp.ptr);
    try expected.appendNTimes(0x90, 6);
    try std.testing.expectEqualSlices(u8, expected.items, code);

    try std.testing.expectEqualSlices(u8, &.{
        0xFF, 0x25, 0x00, 0x00, 0x00, 0x00, // jmp [rip + 0x00]
        0x00, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // raw address
        0x90, 0x90, // nops
    }, jump_entry1.detour_jmp);
    try std.testing.expectEqualSlices(u8, &.{
        0xFF, 0x25, 0x00, 0x00, 0x00, 0x00, // jmp [rip + 0x00]
        0x00, 0x20, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // raw address
        0x90, 0x90, // nops
    }, jump_entry2.detour_jmp);
    try std.testing.expectEqualSlices(u8, &.{
        0xFF, 0x25, 0x00, 0x00, 0x00, 0x00, // jmp [rip + 0x00]
        0x00, 0x30, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // raw address
        0x90, 0x90, // nops
    }, jump_entry3.detour_jmp);

    // after detaching the 2nd hook the 1st hook should jump to the 3rd hook.
    try detour.detach(@intFromPtr(code.ptr), 0x2000);
    expected.clearRetainingCapacity();
    try expected.appendSlice(&.{
        0xFF, 0x25, 0x00, 0x00, 0x00, 0x00, // jmp [rip + 0x00]
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // raw address
    });
    @as(*usize, @ptrFromInt(@intFromPtr(expected.items[expected.items.len - @sizeOf(usize) ..].ptr))).* = @intFromPtr(jump_entry3.detour_jmp.ptr);
    try expected.appendNTimes(0x90, 2);
    try std.testing.expectEqualSlices(u8, expected.items, jump_entry1.next_jmp);

    // after detaching the 1st and 2nd hook the main target should now jump to the 3rd hook
    try detour.detach(@intFromPtr(code.ptr), 0x1000);
    expected.clearRetainingCapacity();
    try expected.appendSlice(&.{
        0xFF, 0x25, 0x00, 0x00, 0x00, 0x00, // jmp [rip + 0x00]
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // raw address
    });
    @as(*usize, @ptrFromInt(@intFromPtr(expected.items[expected.items.len - @sizeOf(usize) ..].ptr))).* = @intFromPtr(jump_entry3.detour_jmp.ptr);
    try expected.appendNTimes(0x90, 6);
    try std.testing.expectEqualSlices(u8, expected.items, code);

    // trampoline should contain original replaced instructions
    const trampoline_code: [*]const u8 = @ptrFromInt(attached3.new_target);
    try std.testing.expectEqualSlices(u8, &.{
        0x55, // push rbp
        0x48, 0x89, 0xE5, // mov rbp, rsp
        0x48, 0x83, 0xEC, 0x20, // sub rsp, 0x20
        0x48, 0x89, 0x4D, 0x10, // mov [rbp+0x10], rcx
        0x48, 0x89, 0x55, 0x18, // mov [rbp+0x18], rdx
    }, trampoline_code[0..absolute_jmp_size]);

    // the trampoline jump back address should point to the next original instruction
    const jmp_back_addr_read = @intFromPtr(trampoline_code[absolute_jmp_size + 6 .. absolute_jmp_size + 6 + @sizeOf(usize)].ptr);
    const jmp_back_addr = @as(*usize, @ptrFromInt(jmp_back_addr_read)).*;
    try std.testing.expectEqual(@intFromPtr(code[absolute_jmp_size..].ptr), jmp_back_addr);
}
