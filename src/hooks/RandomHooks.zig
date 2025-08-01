const builtin = @import("builtin");
const std = @import("std");
const ba = @import("binary_analysis");

const GeneralRegisters = extern struct {
    r15: usize = 0,
    r14: usize = 0,
    r13: usize = 0,
    r12: usize = 0,
    r11: usize = 0,
    r10: usize = 0,
    r9: usize = 0,
    r8: usize = 0,
    rbp: usize = 0,
    rdi: usize = 0,
    rsi: usize = 0,
    rdx: usize = 0,
    rcx: usize = 0,
    rbx: usize = 0,
    rax: usize = 0,
    rsp: usize = 0,
};

const heap_state_saver = struct {
    const push_volatile_regs = switch (builtin.target.os.tag) {
        .windows =>
        \\ push %%rdx
        \\ push %%r8
        \\ push %%r9
        \\ push %%r10
        \\ push %%r11
        \\
        ,
        else => @compileError("TODO: Support them!"),
    };
    const pop_volatile_regs = switch (builtin.target.os.tag) {
        .windows =>
        \\ pop %%r11
        \\ pop %%r10
        \\ pop %%r9
        \\ pop %%r8
        \\ pop %%rdx
        \\
        ,
        else => @compileError("TODO: Support them!"),
    };

    const first_arg_reg = if (builtin.target.os.tag == .windows) "%%rcx" else "%%rdi";
    const not_first_arg_reg = if (builtin.target.os.tag == .windows) "%%rdi" else "%%rcx";
    const save_call_hook_template = std.fmt.comptimePrint(
        \\ push %%rsp
        \\ sub ${d}, %%rsp
        \\ push %%rax
        \\
    ++
        " push " ++ first_arg_reg ++ "\n" ++
        push_volatile_regs ++
        " push " ++ not_first_arg_reg ++ "\n" ++
        " mov ${d}, " ++ first_arg_reg ++ "\n" ++
        \\ call malloc
        \\
    ++
        " pop " ++ not_first_arg_reg ++ "\n" ++
        pop_volatile_regs ++
        \\ mov %%rax, {d}(%%rsp)
        \\
    ++
        " pop " ++ first_arg_reg ++ "\n" ++
        " mov " ++ first_arg_reg ++ ", {}(%%rax)" ++ "\n" ++
        " mov %%rax, " ++ first_arg_reg ++ "\n" ++
        \\ pop %%rax
        \\
    ++
        " mov %%rax, {}(" ++ first_arg_reg ++ ")" ++ "\n" ++
        " mov %%rbx, {}(" ++ first_arg_reg ++ ")" ++ "\n" ++
        " mov %%rdx, {}(" ++ first_arg_reg ++ ")" ++ "\n" ++
        " mov %%rsi, {}(" ++ first_arg_reg ++ ")" ++ "\n" ++
        " mov %%rbp, {}(" ++ first_arg_reg ++ ")" ++ "\n" ++
        " mov " ++ not_first_arg_reg ++ ", {}(" ++ first_arg_reg ++ ")" ++ "\n" ++
        // moving rsp to the saved rsp
        \\ mov {d}(%%rsp), %%rax
        \\
    ++
        " mov %%rax, {}(" ++ first_arg_reg ++ ")" ++ "\n" ++
        " mov %%r8, {}(" ++ first_arg_reg ++ ")" ++ "\n" ++
        " mov %%r9, {}(" ++ first_arg_reg ++ ")" ++ "\n" ++
        " mov %%r10, {}(" ++ first_arg_reg ++ ")" ++ "\n" ++
        " mov %%r11, {}(" ++ first_arg_reg ++ ")" ++ "\n" ++
        " mov %%r12, {}(" ++ first_arg_reg ++ ")" ++ "\n" ++
        " mov %%r13, {}(" ++ first_arg_reg ++ ")" ++ "\n" ++
        " mov %%r14, {}(" ++ first_arg_reg ++ ")" ++ "\n" ++
        " mov %%r15, {}(" ++ first_arg_reg ++ ")" ++ "\n" ++
        \\ callq %[onHook:P]
        \\
    , .{
        @sizeOf(*GeneralRegisters),
        @sizeOf(GeneralRegisters),
        @sizeOf(usize) * 2,
        @offsetOf(GeneralRegisters, first_arg_reg[2..]),
        @offsetOf(GeneralRegisters, "rax"),
        @offsetOf(GeneralRegisters, "rbx"),
        @offsetOf(GeneralRegisters, "rdx"),
        @offsetOf(GeneralRegisters, "rsi"),
        @offsetOf(GeneralRegisters, "rbp"),
        @offsetOf(GeneralRegisters, not_first_arg_reg[2..]),
        // the last 2 regs have been popped
        @sizeOf(*GeneralRegisters),
        @offsetOf(GeneralRegisters, "rsp"),
        @offsetOf(GeneralRegisters, "r8"),
        @offsetOf(GeneralRegisters, "r9"),
        @offsetOf(GeneralRegisters, "r10"),
        @offsetOf(GeneralRegisters, "r11"),
        @offsetOf(GeneralRegisters, "r12"),
        @offsetOf(GeneralRegisters, "r13"),
        @offsetOf(GeneralRegisters, "r14"),
        @offsetOf(GeneralRegisters, "r15"),
    });

    const restore_template = std.fmt.comptimePrint(
        \\ mov (%%rsp), %%rax
        \\ mov {}(%%rax), %%rbx
        \\ mov {}(%%rax), %%rcx
        \\ mov {}(%%rax), %%rdx
        \\ mov {}(%%rax), %%rsi
        \\ mov {}(%%rax), %%rdi
        \\ mov {}(%%rax), %%rbp
        //\\ mov {}(%%rax), %%rsp
        \\ mov {}(%%rax), %%r8
        \\ mov {}(%%rax), %%r9
        \\ mov {}(%%rax), %%r10
        \\ mov {}(%%rax), %%r11
        \\ mov {}(%%rax), %%r12
        \\ mov {}(%%rax), %%r13
        \\ mov {}(%%rax), %%r14
        \\ mov {}(%%rax), %%r15
        \\ mov {}(%%rax), %%rax
        \\
    ++
        " push " ++ first_arg_reg ++ "\n" ++
        " mov {d}(%%rsp), " ++ first_arg_reg ++ "\n" ++
        \\ push %%rax
        \\
    ++
        push_volatile_regs ++
        " push " ++ not_first_arg_reg ++ "\n" ++
        \\ call free
        \\
    ++
        " pop " ++ not_first_arg_reg ++ "\n" ++
        pop_volatile_regs ++
        \\ pop %%rax
        \\ 
    ++
        " pop " ++ first_arg_reg ++ "\n" ++
        \\ add ${d}, %%rsp
        \\ pop %%rsp
        \\
    , .{
        @offsetOf(GeneralRegisters, "rbx"),
        @offsetOf(GeneralRegisters, "rcx"),
        @offsetOf(GeneralRegisters, "rdx"),
        @offsetOf(GeneralRegisters, "rsi"),
        @offsetOf(GeneralRegisters, "rdi"),
        @offsetOf(GeneralRegisters, "rbp"),
        //@offsetOf(GeneralRegisters, "rsp"),
        @offsetOf(GeneralRegisters, "r8"),
        @offsetOf(GeneralRegisters, "r9"),
        @offsetOf(GeneralRegisters, "r10"),
        @offsetOf(GeneralRegisters, "r11"),
        @offsetOf(GeneralRegisters, "r12"),
        @offsetOf(GeneralRegisters, "r13"),
        @offsetOf(GeneralRegisters, "r14"),
        @offsetOf(GeneralRegisters, "r15"),
        @offsetOf(GeneralRegisters, "rax"),
        @sizeOf(*GeneralRegisters),
        @sizeOf(usize),
    });
};

const stack_state_saver = struct {
    const first_arg_reg = if (builtin.target.os.tag == .windows) "%%rcx" else "%%rdi";
    const save_call_hook_template = std.fmt.comptimePrint(
        \\ push %%rsp
        \\ push %%rax
        \\ push %%rbx
        \\ push %%rcx
        \\ push %%rdx
        \\ push %%rsi
        \\ push %%rdi
        \\ push %%rbp
        \\ push %%r8
        \\ push %%r9
        \\ push %%r10
        \\ push %%r11
        \\ push %%r12
        \\ push %%r13
        \\ push %%r14
        \\ push %%r15
        \\
    ++
        "mov %%rsp, " ++ first_arg_reg ++ "\n" ++
        \\ callq %[onHook:P]
        \\ pop %%r15
        \\ pop %%r14
        \\ pop %%r13
        \\ pop %%r12
        \\ pop %%r11
        \\ pop %%r10
        \\ pop %%r9
        \\ pop %%r8
        \\ pop %%rbp
        \\ pop %%rdi
        \\ pop %%rsi
        \\ pop %%rdx
        \\ pop %%rcx
        \\ pop %%rbx
        \\ pop %%rax
        \\ pop %%rsp
    , .{});
};

fn hookFn() callconv(.naked) noreturn {
    @setRuntimeSafety(false);

    // asm volatile (stack_state_saver.save_call_hook_template
    //     :
    //     : [onHook] "X" (&onHook),
    //     : "memory", "cc"
    // );
    asm volatile (
        \\ cmpl $0x100, 0x8(%%rcx)
        \\ jne 1f
        \\ movl $0x00, 0x8(%%rcx)
        \\ 1:
    );

    // our special signature to detect end of function, too lazy to detect with other means :)
    asm volatile (
        \\ nop
        \\ int $3
        \\ nop
        \\ int $3
        \\ nop
        \\ int $3
        \\ nop
        \\ int $3
        \\ nop
        \\ int $3
        \\ nop
        \\ int $3
        \\ nop
        \\ int $3
        \\ nop
        \\ int $3
    );
}

fn hookDefWindowProc() callconv(.naked) noreturn {
    @setRuntimeSafety(false);

    // saving on the stack was taking too much space..
    asm volatile (heap_state_saver.save_call_hook_template
        :
        : [onHook] "X" (&onDefaultWndProc),
        : .{ .memory = true, .cc = true });

    asm volatile (heap_state_saver.restore_template);

    // our special signature to detect end of function, too lazy to detect with other means :)
    asm volatile (
        \\ nop
        \\ int $3
        \\ nop
        \\ int $3
        \\ nop
        \\ int $3
        \\ nop
        \\ int $3
        \\ nop
        \\ int $3
        \\ nop
        \\ int $3
        \\ nop
        \\ int $3
        \\ nop
        \\ int $3
    );
}

var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
const allocator = arena.allocator();

var scanner = ba.aob.Scanner.init(allocator);

var raw_file: ?std.fs.File = null;

/// Initializes the *RandomHooks* hook with the given detour context.
pub fn init(detour: *ba.Detour) !void {
    _ = arena.reset(.free_all);

    const module = try ba.windows.getModuleInfo(allocator, base_module);
    defer module.deinit(allocator);

    // try hookTo(detour, module.start + 0x7389BE, @intFromPtr(&hookFn));

    const u32_module = try ba.windows.getModuleInfo(allocator, "USER32.dll");
    defer u32_module.deinit(allocator);

    //USER32.dll+AD10 - 48 89 5C 24 08        - mov [rsp+08],rbx
    try hookTo(detour, u32_module.start + 0xAD10, @intFromPtr(&hookDefWindowProc));
    //USER32.dll+C6C0 - 48 89 5C 24 08        - mov [rsp+08],rbx
    //try hookTo(detour, u32_module.start + 0xC6C0, @intFromPtr(&hookDefWindowProc));

    raw_file = try std.fs.createFileAbsolute("logs.txt", .{});
}

fn hookTo(detour: *ba.Detour, hook_target: usize, hook_fn_start: usize) !void {
    const attached_info = try detour.attach(hook_target, hook_fn_start);

    try scanner.search_ranges.append(.{
        .start = hook_fn_start,
        .end = hook_fn_start + 512,
    });

    var search_ctx = scanner.newSearch();
    defer search_ctx.deinit();
    try search_ctx.searchBytes(&hook_fn_end_signature, .{ .find_one_per_range = true });
    const hook_fn_end = search_ctx.result.getLast().start;

    _ = try ba.Detour.emitJmp(hook_fn_end, attached_info.trampoline, null);
}

/// Cleans up resources allocated by the *RandomHooks* hook
pub fn deinit() void {
    if (raw_file) |f| {
        f.close();
    }
    _ = arena.reset(.free_all);
    arena.deinit();
}

pub const hook_fn_end_signature = [_]u8{ 0x90, 0xCC } ** 8;
pub const name = "RandomHooks";
pub const base_module = "NeedForSpeedUnbound.exe";

extern "c" fn fprintf(file: *std.c.FILE, fmt: [*:0]const u8, ...) callconv(.c) c_int;

fn usizeToHexAlloc(value: usize) ![]u8 {
    @setRuntimeSafety(false);
    if (value == 0) {
        const mem: [*]u8 = @ptrCast(std.c.malloc(@sizeOf(u8)) orelse return error.OutOfMemory);
        mem[0] = '0';
        return mem[0..1];
    }

    // Calculate how many hex digits we need
    var temp = value;
    var len: usize = 0;
    while (temp > 0) {
        temp /= 16;
        len += 1;
    }

    const buf: [*]u8 = @ptrCast(std.c.malloc(@sizeOf(u8) * len) orelse return error.OutOfMemory);
    const hex_chars = "0123456789ABCDEF";

    temp = value;
    var i = len;
    while (temp > 0) {
        i -= 1;
        buf[i] = hex_chars[temp % 16];
        temp /= 16;
    }

    return buf[0..len];
}

fn onDefaultWndProc(regs: *GeneralRegisters) callconv(.c) void {
    @setRuntimeSafety(false);
    //std.debug.print("MSG Type: RDX(UINT,MSG) = 0x{}\n", .{regs.rdx});
    //_ = regs;
    if (raw_file) |f| {
        const hex_rdx = usizeToHexAlloc(regs.rdx) catch return;
        defer std.c.free(@ptrCast(hex_rdx));
        f.writeAll("MSG Type: RDX(UINT,MSG) = 0x") catch return;
        f.writeAll(hex_rdx) catch return;
        f.writeAll("\n") catch return;
        //f.writeAll("IME called\n") catch {};
    }
}
