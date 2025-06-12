const Allocator = @import("std").mem.Allocator;
const cs = @import("capstone_z");

pub fn FilteredMapIterator(
    comptime T: type,
    comptime CtxType: type,
    comptime filtered_map: fn (index: usize, insn: *const cs.Insn, ctx: CtxType) ?T,
) type {
    return struct {
        iter: cs.IterUnmanaged,
        ctx: CtxType,
        index: usize = 0,

        const IterSelf = @This();

        /// Doesn't allocate, uses `cs.disasmIter`.
        /// The `ins` parameter is a pointer to a `cs.Insn` that must be allocated by the caller.
        /// **NOTE**: the `ins` pointer must contain a valid `cs.Detail` pointer when the detail option is enabled.
        pub fn init(handle: cs.Handle, code: []const u8, address: usize, ins: *cs.Insn, ctx: CtxType) IterSelf {
            const iter = cs.disasmIter(handle, code, address, ins);
            return IterSelf{
                .iter = iter,
                .ctx = ctx,
            };
        }

        pub fn next(self: *IterSelf) ?T {
            while (self.iter.next()) |insn| {
                const current_index = self.index;
                self.index += 1;
                if (filtered_map(current_index, insn, self.ctx)) |instruction| {
                    return instruction;
                }
            }
            return null;
        }

        pub fn reset(self: *IterSelf) void {
            self.iter.reset();
            self.index = 0;
        }
    };
}

pub fn FilteredMapIteratorManaged(
    comptime T: type,
    comptime CtxType: type,
    comptime filtered_map: fn (index: usize, insn: *const cs.Insn, ctx: CtxType) ?T,
) type {
    return struct {
        iter: cs.IterManaged,
        ctx: CtxType,
        index: usize = 0,

        const IterSelf = @This();

        pub fn init(allocator: Allocator, handle: cs.Handle, code: []const u8, address: usize, ctx: CtxType) IterSelf {
            const iter = cs.disasmIterManaged(allocator, handle, code, address);
            return IterSelf{
                .iter = iter,
                .ctx = ctx,
            };
        }

        pub fn next(self: *IterSelf) ?T {
            while (self.iter.next()) |insn| {
                const current_index = self.index;
                self.index += 1;
                if (filtered_map(current_index, insn, self.ctx)) |instruction| {
                    return instruction;
                }
            }
            return null;
        }

        pub fn reset(self: *IterSelf) void {
            self.iter.reset();
            self.index = 0;
        }
    };
}
