const std = @import("std");

// saved registers avoid using them in any other place
var rax: usize = 0;
var rbx: usize = 0;
var rcx: usize = 0;
var rdx: usize = 0;
var rsi: usize = 0;
var rdi: usize = 0;
var rbp: usize = 0;
var rsp: usize = 0;
var r8: usize = 0;
var r9: usize = 0;
var r10: usize = 0;
var r11: usize = 0;
var r12: usize = 0;
var r13: usize = 0;
var r14: usize = 0;
var r15: usize = 0;

pub fn hookFn() callconv(.naked) noreturn {
    @setRuntimeSafety(false);
    // saving state....
    // One day zig will get there, one day!
    asm volatile (
        \\
        : [r14] "={r14}" (r14),
          [r15] "={r15}" (r15),
        :
        : "r14", "r15"
    );
    asm volatile (
        \\
        : [rax] "={rax}" (rax),
          [rbx] "={rbx}" (rbx),
          [rcx] "={rcx}" (rcx),
          [rdx] "={rdx}" (rdx),
          [rsi] "={rsi}" (rsi),
          [rdi] "={rdi}" (rdi),
          [rbp] "={rbp}" (rbp),
          [rsp] "={rsp}" (rsp),
          [r8] "={r8}" (r8),
          [r9] "={r9}" (r9),
          [r10] "={r10}" (r10),
          [r11] "={r11}" (r11),
          [r12] "={r12}" (r12),
          [r13] "={r13}" (r13),
        :
        : "rax", "rbx", "rcx", "rdx", "rsi", "rdi", "rbp", "rsp", "r8", "r9", "r10", "r11", "r12", "r13"
    );

    // custom code
    asm volatile (
        \\ callq %[onHook:P]
        :
        : [onHook] "X" (&onHook),
        : "memory"
    );

    // restoring state and jumping....
    asm volatile (
        \\
        :
        : [rax] "{rax}" (rax),
          [rbx] "{rbx}" (rbx),
          [rcx] "{rcx}" (rcx),
          [rdx] "{rdx}" (rdx),
          [rsi] "{rsi}" (rsi),
          [rdi] "{rdi}" (rdi),
          [rbp] "{rbp}" (rbp),
          [rsp] "{rsp}" (rsp),
          [r8] "{r8}" (r8),
          [r9] "{r9}" (r9),
          [r10] "{r10}" (r10),
          [r11] "{r11}" (r11),
          [r12] "{r12}" (r12),
          [r13] "{r13}" (r13),
        : "rax", "rbx", "rcx", "rdx", "rsi", "rdi", "rbp", "rsp", "r8", "r9", "r10", "r11", "r12", "r13"
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
        :
        : [r14] "{r14}" (r14),
          [r15] "{r15}" (r15),
    );
}

const Something = extern struct { a: c_int, b: c_int };
fn onHook() void {
    // heck, we can even change register values directly from here!
    // rcx = Something
    const something: *Something = @alignCast(@as(*Something, @ptrFromInt(rcx)));
    std.debug.print("On `DoSomething2` custom hook!\n  original values:\n  {any}\n", .{something.*});
    something.*.a += 10;
    something.*.b += 10;
}

pub const name = "DoSomething2";
