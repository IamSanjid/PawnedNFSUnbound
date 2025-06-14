//!
//! Direct copy paste from smp_allocator of zig! Well, with some adjustments.
//!
//! The `slab_len` is equal to page size obtained during runtime.
//!
const builtin = @import("builtin");
const std = @import("std");
const windows = std.os.windows;
const posix = std.posix;

const assert = std.debug.assert;
const mem = std.mem;
const math = std.math;
const Allocator = std.mem.Allocator;
const TrampolineAllocator = @This();

/// Because of storing free list pointers, the minimum size class is 3.
const min_class: usize = math.log2(@sizeOf(usize));

const double_free_checker = struct {
    var mutex = std.Thread.Mutex{};
    var free_set = std.AutoHashMap(usize, void).init(std.heap.c_allocator);

    fn check(freed: usize, ret_address: usize) void {
        mutex.lock();
        defer mutex.unlock();
        const put = free_set.getOrPut(freed) catch return;
        if (put.found_existing) {
            std.debug.panicExtra(ret_address, "0x{X} is being freed twice!", .{freed});
        }
    }

    fn uncheck(using: usize) void {
        mutex.lock();
        defer mutex.unlock();
        _ = free_set.remove(using);
    }
};

info_allocator: Allocator,
next_addrs: []usize,
frees: []usize,
slabs: std.ArrayList([]u8),
slab_len: usize,

pub const vtable: Allocator.VTable = .{
    .alloc = alloc,
    .resize = resize,
    .remap = remap,
    .free = free,
};

pub fn init(info_allocator: Allocator) !TrampolineAllocator {
    const slab_len = std.heap.pageSize();
    const size_class_count = math.log2(slab_len) - min_class;

    const next_addrs = try info_allocator.alloc(usize, size_class_count);
    errdefer info_allocator.free(next_addrs);

    const frees = try info_allocator.alloc(usize, size_class_count);

    @memset(next_addrs, 0);
    @memset(frees, 0);

    return .{
        .info_allocator = info_allocator,
        .next_addrs = next_addrs,
        .frees = frees,
        .slab_len = slab_len,
        .slabs = std.ArrayList([]u8).init(info_allocator),
    };
}

pub fn allocator(self: *TrampolineAllocator) Allocator {
    return .{
        .ptr = self,
        .vtable = &.{
            .alloc = alloc,
            .resize = resize,
            .remap = remap,
            .free = free,
        },
    };
}

pub fn deinit(self: *TrampolineAllocator) void {
    self.info_allocator.free(self.next_addrs);
    self.info_allocator.free(self.frees);

    for (self.slabs.items) |slab| {
        unmap(@alignCast(slab));
    }
    self.slabs.deinit();
    // kind of marking we're done?
    self.slab_len = 0;
}

inline fn map(n: usize) ?[*]u8 {
    // Don't wanna call std.heap.pageSize() again and again, TrampolineAllocator should cache it!
    if (builtin.os.tag == .windows) {
        const memory = windows.VirtualAlloc(
            null,
            n,
            windows.MEM_COMMIT | windows.MEM_RESERVE,
            windows.PAGE_EXECUTE_READWRITE,
        ) catch return null;

        return @ptrCast(memory);
    } else {
        const memory = posix.mmap(
            null,
            n,
            posix.PROT.READ | posix.PROT.WRITE | posix.PROT.EXEC,
            posix.MAP{ .ANONYMOUS = true, .TYPE = .PRIVATE },
            0,
            0,
        ) catch return null;
        return memory.ptr;
    }
}

// should be aligned already our slab_len is `std.heap.pageSize()`
inline fn unmap(memory: []align(std.heap.page_size_min) u8) void {
    if (builtin.os.tag == .windows) {
        const base_addr: windows.PVOID = @ptrCast(memory.ptr);
        windows.VirtualFree(base_addr, 0, windows.MEM_RELEASE);
    } else {
        posix.munmap(memory);
    }
}

fn alloc(context: *anyopaque, len: usize, alignment: mem.Alignment, ra: usize) ?[*]u8 {
    _ = ra;
    const self: *TrampolineAllocator = @ptrCast(@alignCast(context));
    const class = sizeClassIndex(len, alignment);

    const size_class_count = self.frees.len;

    // needing more than the page size? doing something wrong...
    assert(class < size_class_count);

    const slot_size = slotSize(class);
    assert(self.slab_len % slot_size == 0);

    const top_free_ptr = self.frees[class];
    if (top_free_ptr != 0) {
        @branchHint(.likely);
        if (builtin.mode == .Debug) {
            double_free_checker.uncheck(top_free_ptr);
        }
        const node: *usize = @ptrFromInt(top_free_ptr);
        self.frees[class] = node.*;
        return @ptrFromInt(top_free_ptr);
    }

    const next_addr = self.next_addrs[class];
    if ((next_addr % self.slab_len) != 0) {
        @branchHint(.likely);
        if (builtin.mode == .Debug) {
            double_free_checker.uncheck(top_free_ptr);
        }
        self.next_addrs[class] = next_addr + slot_size;
        return @ptrFromInt(next_addr);
    }

    // slab alignment here ensures the % slab len earlier catches the end of slots.
    const slab = map(self.slab_len) orelse return null;
    self.slabs.append(slab[0..self.slab_len]) catch {
        unmap(@alignCast(slab[0..self.slab_len]));
        return null;
    };
    self.next_addrs[class] = @intFromPtr(slab) + slot_size;
    return slab;
}

fn resize(context: *anyopaque, memory: []u8, alignment: mem.Alignment, new_len: usize, ra: usize) bool {
    _ = ra;
    const self: *TrampolineAllocator = @ptrCast(@alignCast(context));
    const class = sizeClassIndex(memory.len, alignment);
    const new_class = sizeClassIndex(new_len, alignment);

    const size_class_count = self.frees.len;

    // needing more than the page size? doing something wrong...
    assert(class < size_class_count);

    return new_class == class;
}

fn remap(context: *anyopaque, memory: []u8, alignment: mem.Alignment, new_len: usize, ra: usize) ?[*]u8 {
    _ = ra;
    const self: *TrampolineAllocator = @ptrCast(@alignCast(context));
    const class = sizeClassIndex(memory.len, alignment);
    const new_class = sizeClassIndex(new_len, alignment);

    const size_class_count = self.frees.len;

    // needing more than the page size? doing something wrong...
    assert(class < size_class_count);

    return if (new_class == class) memory.ptr else null;
}

fn free(context: *anyopaque, memory: []u8, alignment: mem.Alignment, ra: usize) void {
    const self: *TrampolineAllocator = @ptrCast(@alignCast(context));
    const class = sizeClassIndex(memory.len, alignment);

    const size_class_count = self.frees.len;

    // needing more than the page size? doing something wrong...
    assert(class < size_class_count);

    if (builtin.mode == .Debug) {
        double_free_checker.check(@intFromPtr(memory.ptr), ra);
    }

    const node: *usize = @alignCast(@ptrCast(memory.ptr));

    node.* = self.frees[class];
    self.frees[class] = @intFromPtr(node);
}

fn sizeClassIndex(len: usize, alignment: mem.Alignment) usize {
    return @max(@bitSizeOf(usize) - @clz(len - 1), @intFromEnum(alignment), min_class) - min_class;
}

fn slotSize(class: usize) usize {
    return @as(usize, 1) << @intCast(class + min_class);
}

test "basic" {
    const alloc_size = 16 * 2;
    var trampoline = try TrampolineAllocator.init(std.testing.allocator);
    defer trampoline.deinit();

    const trampoline_allocator = trampoline.allocator();
    var b1 = try trampoline_allocator.alloc(u8, alloc_size);

    const b1_ptr: usize = @intFromPtr(b1.ptr);
    var b2_ptr: usize = undefined;

    {
        const b2 = try trampoline_allocator.alloc(u8, alloc_size);
        b2_ptr = @intFromPtr(b2.ptr);

        const diff = @intFromPtr(b2.ptr) - @intFromPtr(b1.ptr);
        try std.testing.expectEqual(alloc_size, diff);

        trampoline_allocator.free(b2);
    }
    {
        const b2 = try trampoline_allocator.alloc(u8, alloc_size);
        try std.testing.expectEqual(b2_ptr, @intFromPtr(b2.ptr));

        const diff = @intFromPtr(b2.ptr) - @intFromPtr(b1.ptr);
        try std.testing.expectEqual(alloc_size, diff);

        trampoline_allocator.free(b2);
    }

    {
        trampoline_allocator.free(b1);
        b1 = try trampoline_allocator.alloc(u8, alloc_size);
        try std.testing.expectEqual(b1_ptr, @intFromPtr(b1.ptr));

        const b2 = try trampoline_allocator.alloc(u8, alloc_size);
        var diff = @intFromPtr(b2.ptr) - @intFromPtr(b1.ptr);
        try std.testing.expectEqual(alloc_size, diff);
        defer trampoline_allocator.free(b2);

        const b3 = try trampoline_allocator.alloc(u8, alloc_size);
        diff = @intFromPtr(b3.ptr) - @intFromPtr(b1.ptr);
        try std.testing.expectEqual(alloc_size * 2, diff);
        defer trampoline_allocator.free(b3);
    }

    trampoline_allocator.free(b1);

    {
        // double free, should panic
        // trampoline_allocator.free(b1);

        const b2 = try trampoline_allocator.alloc(u8, alloc_size);
        var diff = @intFromPtr(b2.ptr) - @intFromPtr(b1.ptr);
        try std.testing.expectEqual(0, diff);
        trampoline_allocator.free(b2);

        b1 = try trampoline_allocator.alloc(u8, alloc_size);

        const b3 = try trampoline_allocator.alloc(u8, alloc_size);
        diff = @intFromPtr(b3.ptr) - @intFromPtr(b1.ptr);
        try std.testing.expectEqual(alloc_size, diff);
        trampoline_allocator.free(b3);

        trampoline_allocator.free(b2);
        // b2 memory was freed so it's being re-used by b1, so the next line will trigger double free
        // trampoline_allocator.free(b1);
    }
}
