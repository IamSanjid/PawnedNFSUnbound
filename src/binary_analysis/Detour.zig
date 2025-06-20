const builtin = @import("builtin");
const std = @import("std");

const disasm = @import("disasm");
const any = @import("any/any.zig");
const windows = @import("windows/windows.zig");
const posix = @import("posix.zig");

const Allocator = std.mem.Allocator;
const TrampolineAllocator = @import("TrampolineAllocator.zig");

/// To write jmp instruction.
const safe_buf_size: usize = 64;

pub fn Detour(comptime arch: std.Target.Cpu.Arch, comptime os: std.Target.Os.Tag) type {
    return struct {
        const fixRelativeInstructions = switch (arch) {
            .x86_64 => any.x86_64.relative_rip_instructions.fix,
            else => @compileError("TODO: Support more archs"),
        };
        const detectFuncEnd = switch (arch) {
            .x86_64 => any.x86_64.func_end.detect,
            else => @compileError("TODO: Support more archs"),
        };

        const raw_jmp_size = switch (arch) {
            .x86_64 => any.x86_64.absolute_jmp_size,
            else => @compileError("TODO: Support more archs"),
        };
        pub const absolute_jmp_size = std.mem.alignForward(usize, raw_jmp_size, @sizeOf(usize));
        pub const Errors = error{
            OverwriteBoundaryNotFound,
            NotFound,
        };

        pub const JumpEntry = struct {
            detour_jmp: []u8,
            next_jmp: []u8,

            fn create(trampoline_allocator: Allocator) !@This() {
                const raw = try trampoline_allocator.alloc(u8, absolute_jmp_size * 2);
                return .{
                    .detour_jmp = raw[0..absolute_jmp_size],
                    .next_jmp = raw[absolute_jmp_size..],
                };
            }

            fn flush(self: @This()) void {
                const addr: [*]u8 = self.detour_jmp.ptr;
                if (os == .windows) {
                    windows.clearInstructionCache(addr[0 .. absolute_jmp_size * 2]);
                } else {
                    // try other stuff or posix?
                    any.clearInstructionCache(addr[0 .. absolute_jmp_size * 2]);
                }
            }

            fn destroy(self: @This(), trampoline_allocator: Allocator) void {
                // **UNSAFE** detour_jmp and next_jmp must be part of a contigious region
                const full_mem = self.detour_jmp.ptr[0 .. absolute_jmp_size * 2];
                trampoline_allocator.free(full_mem);
            }
        };

        pub const Attached = struct {
            /// Points to the instruction which will jump to the next hook trampoline or to the original
            /// target trampoline.
            /// Basically the next address where the hook should jump back either to give control to the
            /// original target or to trigger the next hook of the chain.
            ///
            /// Chain hooks can be disrupted by doing an early return/jumping to a different place
            /// other than this *trampoline* address.
            trampoline: usize,
            /// Points to the trampoline which has all the replaced instructions and jumps
            /// back to the original function.
            ///
            /// Useful when attaching at the start of a function, and then caling that function
            /// from the detour function, or when trying to prevent other hooks from being called in
            /// the chain just jump to this address.
            new_target: usize,
        };

        // maintains insertion order!
        const JumpTable = std.AutoArrayHashMap(usize, JumpEntry);

        const Info = struct {
            target: usize,
            jmp_table: JumpTable,
            trampoline: []u8,
            original_code_offset: usize,
            overwritten: usize,
        };

        allocator: Allocator,
        attached: std.AutoHashMap(usize, *Info),
        trampoline_allocator: TrampolineAllocator,
        disassmbler: disasm.capstone.ManagedHandle,

        const Self = @This();

        pub fn init(allocator: Allocator) !Self {
            const disassmbler = try disasm.createManagedCapstone(arch, .{ .detail = true });
            const trampoline_allocator = try TrampolineAllocator.init(allocator);
            return .{
                .allocator = allocator,
                .trampoline_allocator = trampoline_allocator,
                .attached = .init(allocator),
                .disassmbler = disassmbler,
            };
        }

        pub fn attach(self: *Self, target: usize, detour: usize) !Attached {
            @setRuntimeSafety(false);

            const trampoline_allocator = self.trampoline_allocator.allocator();

            const get_put_res = try self.attached.getOrPut(target);
            if (!get_put_res.found_existing) {
                const found_region = any.safe_overwrite_boundary.find(self.disassmbler.native, target, 14) orelse {
                    return Errors.OverwriteBoundaryNotFound;
                };

                const overwrite_bytes = found_region.len;
                const original_code: []const u8 = @as([*]const u8, @ptrFromInt(target))[0..overwrite_bytes];

                const fixed = try fixRelativeInstructions(self.allocator, self.disassmbler.native, found_region, 14);
                defer self.allocator.free(fixed.code);

                const code = fixed.code;
                const jmp_back_write_offset = fixed.reserved_offset;

                const ret_trampoline = try trampoline_allocator.alloc(u8, code.len + original_code.len);
                errdefer trampoline_allocator.free(ret_trampoline);
                // copy the fixed/original code to the trampoline
                @memcpy(ret_trampoline, code);
                @memcpy(ret_trampoline[code.len..], original_code);

                const jmp_entry = try JumpEntry.create(trampoline_allocator);
                errdefer jmp_entry.destroy(trampoline_allocator);
                // kind of like a jmp table
                _ = writeJmpInstruction(jmp_entry.detour_jmp, detour, absolute_jmp_size);
                _ = writeJmpInstruction(jmp_entry.next_jmp, @intFromPtr(ret_trampoline.ptr), absolute_jmp_size);
                jmp_entry.flush();

                // check if original code is ending with jmp or ret instruction
                const ending_ins = detectFuncEnd(self.disassmbler.native, found_region);
                // overwrite the target instructions with jmp to trampoline
                const jmp_back_original = try emitJmp(target, @intFromPtr(jmp_entry.detour_jmp.ptr), overwrite_bytes);
                if (ending_ins) |end_ins| {
                    std.debug.print("Ending pos: {}\n", .{end_ins});
                } else {
                    // if there is no ending instruction, we need to write a jmp back to the original code
                    const ret_trampoline_jmp_buf: [*]u8 = @ptrFromInt(@intFromPtr(ret_trampoline.ptr) + jmp_back_write_offset);
                    _ = try emitJmp(@intFromPtr(ret_trampoline_jmp_buf[0..safe_buf_size].ptr), jmp_back_original, null);
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
                    .overwritten = overwrite_bytes,
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

                const new_jmp_entry = try JumpEntry.create(trampoline_allocator);
                errdefer new_jmp_entry.destroy(trampoline_allocator);
                @memcpy(new_jmp_entry.next_jmp, last_jmp_entry.next_jmp);

                try info.jmp_table.put(detour, new_jmp_entry);
                errdefer _ = info.jmp_table.orderedRemove(detour);

                // **UNSAFE** We're sure the previously allocated trampoline regions have enough space to store *absolute_jmp_size* bytes
                _ = writeJmpInstruction(new_jmp_entry.detour_jmp, detour, absolute_jmp_size);
                _ = writeJmpInstruction(last_jmp_entry.next_jmp, @intFromPtr(new_jmp_entry.detour_jmp.ptr), absolute_jmp_size);
                last_jmp_entry.flush();
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
            const trampoline_allocator = self.trampoline_allocator.allocator();

            if (jmp_table.len <= 1) {
                // should be last or empty..
                const kv = info.jmp_table.fetchOrderedRemove(detour) orelse return;
                defer kv.value.destroy(trampoline_allocator);
                if (info.original_code_offset > 0) {
                    try copyToAsExecutable(target, info.trampoline[info.original_code_offset..]);
                }
                self.allocator.destroy(info);
                _ = self.attached.remove(target);
                return;
            }

            const index = info.jmp_table.getIndex(detour) orelse return;
            const current_entry = jmp_table[index];
            defer current_entry.destroy(trampoline_allocator);

            if (index == 0) {
                const next_entry = jmp_table[index + 1];
                _ = try emitJmp(target, @intFromPtr(next_entry.detour_jmp.ptr), info.overwritten);
                info.jmp_table.orderedRemoveAt(index);
                return;
            }

            const prev_entry = jmp_table[index - 1];
            @memcpy(prev_entry.next_jmp, current_entry.next_jmp);
            prev_entry.flush();
            info.jmp_table.orderedRemoveAt(index);
        }

        pub fn deinit(self: *Self) void {
            const trampoline_allocator = self.trampoline_allocator.allocator();
            var iter = self.attached.valueIterator();
            while (iter.next()) |info_ptr| {
                const info = info_ptr.*;
                if (info.original_code_offset > 0) {
                    copyToAsExecutable(info.target, info.trampoline[info.original_code_offset..]) catch {};
                }
                trampoline_allocator.free(info.trampoline);

                for (info.jmp_table.values()) |entry| {
                    entry.destroy(trampoline_allocator);
                }

                info.jmp_table.deinit();
                self.allocator.destroy(info);
            }
            self.attached.deinit();
            self.trampoline_allocator.deinit();
        }

        pub fn writeJmpInstruction(buf: []u8, target: usize, overwrite_bytes: ?usize) usize {
            var ins_len: usize = undefined;

            std.debug.assert(overwrite_bytes orelse 0 < 64);

            switch (arch) {
                .x86_64 => {
                    ins_len = overwrite_bytes orelse any.x86_64.absolute_jmp_size;
                    any.x86_64.writeJmpInstruction(buf, target);
                    for (0..ins_len - any.x86_64.absolute_jmp_size) |i| {
                        buf[any.x86_64.absolute_jmp_size + i] = 0x90; // nop
                    }
                },
                else => @compileError("TODO: Add support for more architectrures."),
            }
            return ins_len;
        }

        /// Deals with memory protections.
        pub fn emitJmp(to: usize, target: usize, overwrite_bytes: ?usize) !usize {
            var ins_buf: [safe_buf_size]u8 = undefined;

            std.debug.assert(overwrite_bytes orelse 0 < 64);

            const ins_len = writeJmpInstruction(&ins_buf, target, overwrite_bytes);
            try copyToAsExecutable(to, ins_buf[0..ins_len]);
            return to + ins_len;
        }

        /// Copies after making the region memory protected.
        pub fn copyToAsExecutable(to: usize, code: []const u8) !void {
            if (os == .windows) {
                try windows.copyToAsExecutable(to, code);
            } else {
                // try posix or other stuff...
                try posix.copyToAsExecutable(to, code);
            }
        }
    };
}

test "usage x86_64" {
    @setRuntimeSafety(false);
    const allocator = std.testing.allocator;
    const TargetDetour = Detour(.x86_64, .linux);
    var detour = try TargetDetour.init(allocator);
    defer detour.deinit();

    const non_mut_code = [_]u8{
        0x55, // push rbp
        0x48, 0x89, 0xE5, // mov rbp, rsp
        0x48, 0x83, 0xEC, 0x20, // sub rsp, 0x20
        0x48, 0x89, 0x4D, 0x10, // mov [rbp+0x10], rcx
        0x48, 0x89, 0x55, 0x18, // mov [rbp+0x18], rdx
        0x90, 0x90, 0x90, 0x90, // nopes
    };
    const code: []const u8 = &non_mut_code;
    const code_jump_back_address = @intFromPtr(code[TargetDetour.absolute_jmp_size..].ptr);

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

    // 3rd hook should go back to original target trampoline
    var trampoline_code: [*]const u8 = @ptrFromInt(attached3.trampoline);
    expected.clearRetainingCapacity();
    try expected.appendSlice(&.{
        0xFF, 0x25, 0x00, 0x00, 0x00, 0x00, // jmp [rip + 0x00]
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // raw address
    });
    @as(*usize, @ptrFromInt(@intFromPtr(expected.items[expected.items.len - @sizeOf(usize) ..].ptr))).* = attached3.new_target;
    try expected.appendNTimes(0x90, 2);
    try std.testing.expectEqualSlices(u8, expected.items, jump_entry3.next_jmp);
    try std.testing.expectEqualSlices(u8, expected.items, trampoline_code[0..expected.items.len]);

    // trampoline should contain original replaced instructions
    trampoline_code = @ptrFromInt(attached3.new_target);
    try std.testing.expectEqualSlices(u8, &.{
        0x55, // push rbp
        0x48, 0x89, 0xE5, // mov rbp, rsp
        0x48, 0x83, 0xEC, 0x20, // sub rsp, 0x20
        0x48, 0x89, 0x4D, 0x10, // mov [rbp+0x10], rcx
        0x48, 0x89, 0x55, 0x18, // mov [rbp+0x18], rdx
    }, trampoline_code[0..TargetDetour.absolute_jmp_size]);

    // the trampoline jump back address should point to the next original instruction
    const jmp_back_addr_read = @intFromPtr(trampoline_code[TargetDetour.absolute_jmp_size + 6 .. TargetDetour.absolute_jmp_size + 6 + @sizeOf(usize)].ptr);
    const jmp_back_addr = @as(*usize, @ptrFromInt(jmp_back_addr_read)).*;
    try std.testing.expectEqual(code_jump_back_address, jmp_back_addr);

    const attached4 = try detour.attach(@intFromPtr(code.ptr), 0x4000);

    const jump_entry4 = info.jmp_table.get(0x4000) orelse unreachable;
    try std.testing.expectEqualSlices(u8, &.{
        0xFF, 0x25, 0x00, 0x00, 0x00, 0x00, // jmp [rip + 0x00]
        0x00, 0x40, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // raw address
        0x90, 0x90, // nops
    }, jump_entry4.detour_jmp);

    // trampoline should contain original replaced instructions to attached4 too
    trampoline_code = @ptrFromInt(attached4.new_target);
    try std.testing.expectEqualSlices(u8, &.{
        0x55, // push rbp
        0x48, 0x89, 0xE5, // mov rbp, rsp
        0x48, 0x83, 0xEC, 0x20, // sub rsp, 0x20
        0x48, 0x89, 0x4D, 0x10, // mov [rbp+0x10], rcx
        0x48, 0x89, 0x55, 0x18, // mov [rbp+0x18], rdx
    }, trampoline_code[0..TargetDetour.absolute_jmp_size]);

    // 3rd hook now should be jmping to this new 4th hook
    trampoline_code = @ptrFromInt(attached3.trampoline);
    expected.clearRetainingCapacity();
    try expected.appendSlice(&.{
        0xFF, 0x25, 0x00, 0x00, 0x00, 0x00, // jmp [rip + 0x00]
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // raw address
    });
    @as(*usize, @ptrFromInt(@intFromPtr(expected.items[expected.items.len - @sizeOf(usize) ..].ptr))).* = @intFromPtr(jump_entry4.detour_jmp.ptr);
    try expected.appendNTimes(0x90, 2);
    try std.testing.expectEqualSlices(u8, expected.items, jump_entry3.next_jmp);
    try std.testing.expectEqualSlices(u8, expected.items, trampoline_code[0..expected.items.len]);
}
