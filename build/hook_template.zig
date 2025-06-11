const builtin = @import("builtin");
const std = @import("std");

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

pub fn hookFn() callconv(.naked) noreturn {
    @setRuntimeSafety(false);

    asm volatile (stack_state_saver.save_call_hook_template
        :
        : [onHook] "X" (&onHook),
        : "memory", "cc"
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

pub const name = "${HOOK_NAME}";

fn onHook(regs: *GeneralRegisters) callconv(.c) void {
    std.debug.print("On {s} hook! Regs: 0x{X}\n", .{ name, regs });
}
