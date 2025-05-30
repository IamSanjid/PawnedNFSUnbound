const std = @import("std");

const GeneralRegisters = struct {
    rbx: usize = 0,
    rcx: usize = 0,
    rdx: usize = 0,
    rsi: usize = 0,
    rdi: usize = 0,
    rbp: usize = 0,
    rsp: usize = 0,
    r8: usize = 0,
    r9: usize = 0,
    r10: usize = 0,
    r11: usize = 0,
    r12: usize = 0,
    r13: usize = 0,
    r14: usize = 0,
    r15: usize = 0,
};

// registers state, why a pointer to the value? just for you know api consistency(rax.*, eax.*, ax.* etc..)
var rax_value: usize = 0; // going to use rax register as a base for all other registers
var registers: GeneralRegisters = .{};

const rax: *usize = &rax_value;
const eax: *u32 = @ptrCast(rax);
const ax: *u16 = @ptrCast(rax);
const ah: *u8 = &(@as([*]u8, @ptrCast(rax)))[1];
const al: *u8 = @ptrCast(rax);

const rbx: *usize = &registers.rbx;
const ebx: *u32 = @ptrCast(rbx);
const bx: *u16 = @ptrCast(rbx);
const bh: *u8 = &(@as([*]u8, @ptrCast(rbx)))[1];
const bl: *u8 = @ptrCast(rbx);

const rcx: *usize = &registers.rcx;
const ecx: *u32 = @ptrCast(rcx);
const cx: *u16 = @ptrCast(rcx);
const ch: *u8 = &(@as([*]u8, @ptrCast(rcx)))[1];
const cl: *u8 = @ptrCast(rcx);

const rdx: *usize = &registers.rdx;
const edx: *u32 = @ptrCast(rdx);
const dx: *u16 = @ptrCast(rdx);
const dh: *u8 = &(@as([*]u8, @ptrCast(rdx)))[1];
const dl: *u8 = @ptrCast(rdx);

const rsi: *usize = &registers.rsi;
const esi: *u32 = @ptrCast(rsi);
const si: *u16 = @ptrCast(rsi);
const sil: *u8 = @ptrCast(rsi);

const rdi: *usize = &registers.rdi;
const edi: *u32 = @ptrCast(rdi);
const di: *u16 = @ptrCast(rdi);
const dil: *u8 = @ptrCast(rdi);

const rbp: *usize = &registers.rbp;
const ebp: *u32 = @ptrCast(rbp);
const bp: *u16 = @ptrCast(rbp);
const bpl: *u8 = @ptrCast(rbp);

const rsp: *usize = &registers.rsp;
const esp: *u32 = @ptrCast(rsp);
const sp: *u16 = @ptrCast(rsp);
const spl: *u8 = @ptrCast(rsp);

const r8: *usize = &registers.r8;
const r8d: *u32 = @ptrCast(r8);
const r8w: *u16 = @ptrCast(r8);
const r8b: *u8 = @ptrCast(r8);

const r9: *usize = &registers.r9;
const r9d: *u32 = @ptrCast(r9);
const r9w: *u16 = @ptrCast(r9);
const r9b: *u8 = @ptrCast(r9);

const r10: *usize = &registers.r10;
const r10d: *u32 = @ptrCast(r10);
const r10w: *u16 = @ptrCast(r10);
const r10b: *u8 = @ptrCast(r10);

const r11: *usize = &registers.r11;
const r11d: *u32 = @ptrCast(r11);
const r11w: *u16 = @ptrCast(r11);
const r11b: *u8 = @ptrCast(r11);

const r12: *usize = &registers.r12;
const r12d: *u32 = @ptrCast(r12);
const r12w: *u16 = @ptrCast(r12);
const r12b: *u8 = @ptrCast(r12);

const r13: *usize = &registers.r13;
const r13d: *u32 = @ptrCast(r13);
const r13w: *u16 = @ptrCast(r13);
const r13b: *u8 = @ptrCast(r13);

const r14: *usize = &registers.r14;
const r14d: *u32 = @ptrCast(r14);
const r14w: *u16 = @ptrCast(r14);
const r14b: *u8 = @ptrCast(r14);

const r15: *usize = &registers.r15;
const r15d: *u32 = @ptrCast(r15);
const r15w: *u16 = @ptrCast(r15);
const r15b: *u8 = @ptrCast(r15);

const FloatRegister = @Vector(4, f32);
const FloatingRegisters = struct {
    xmm0: FloatRegister = std.mem.zeroes(FloatRegister),
    xmm1: FloatRegister = std.mem.zeroes(FloatRegister),
    xmm2: FloatRegister = std.mem.zeroes(FloatRegister),
    xmm3: FloatRegister = std.mem.zeroes(FloatRegister),
    xmm4: FloatRegister = std.mem.zeroes(FloatRegister),
    xmm5: FloatRegister = std.mem.zeroes(FloatRegister),
    xmm6: FloatRegister = std.mem.zeroes(FloatRegister),
    xmm7: FloatRegister = std.mem.zeroes(FloatRegister),
    xmm8: FloatRegister = std.mem.zeroes(FloatRegister),
    xmm9: FloatRegister = std.mem.zeroes(FloatRegister),
    xmm10: FloatRegister = std.mem.zeroes(FloatRegister),
    xmm11: FloatRegister = std.mem.zeroes(FloatRegister),
    xmm12: FloatRegister = std.mem.zeroes(FloatRegister),
    xmm13: FloatRegister = std.mem.zeroes(FloatRegister),
    xmm14: FloatRegister = std.mem.zeroes(FloatRegister),
    xmm15: FloatRegister = std.mem.zeroes(FloatRegister),
};
var float_registers: FloatingRegisters = .{};

const xmm0: *FloatRegister = &float_registers.xmm0;
const xmm1: *FloatRegister = &float_registers.xmm1;
const xmm2: *FloatRegister = &float_registers.xmm2;
const xmm3: *FloatRegister = &float_registers.xmm3;
const xmm4: *FloatRegister = &float_registers.xmm4;
const xmm5: *FloatRegister = &float_registers.xmm5;
const xmm6: *FloatRegister = &float_registers.xmm6;
const xmm7: *FloatRegister = &float_registers.xmm7;
const xmm8: *FloatRegister = &float_registers.xmm8;
const xmm9: *FloatRegister = &float_registers.xmm9;
const xmm10: *FloatRegister = &float_registers.xmm10;
const xmm11: *FloatRegister = &float_registers.xmm11;
const xmm12: *FloatRegister = &float_registers.xmm12;
const xmm13: *FloatRegister = &float_registers.xmm13;
const xmm14: *FloatRegister = &float_registers.xmm14;
const xmm15: *FloatRegister = &float_registers.xmm15;

pub fn hookFn() callconv(.naked) noreturn {
    @setRuntimeSafety(false);
    // saving state....
    // One day zig will get there, one day!
    asm volatile (
        \\
        : [_] "={rax}" (rax_value),
        :
        : "rax"
    );
    asm volatile (std.fmt.comptimePrint(
            \\ mov %%rbx, {}(%[general_base])
            \\ mov %%rcx, {}(%[general_base])
            \\ mov %%rdx, {}(%[general_base])
            \\ mov %%rsi, {}(%[general_base])
            \\ mov %%rdi, {}(%[general_base])
            \\ mov %%rbp, {}(%[general_base])
            \\ mov %%rsp, {}(%[general_base])
            \\ mov %%r8, {}(%[general_base])
            \\ mov %%r9, {}(%[general_base])
            \\ mov %%r10, {}(%[general_base])
            \\ mov %%r11, {}(%[general_base])
            \\ mov %%r12, {}(%[general_base])
            \\ mov %%r13, {}(%[general_base])
            \\ mov %%r14, {}(%[general_base])
            \\ mov %%r15, {}(%[general_base])
        , .{
            @offsetOf(GeneralRegisters, "rbx"),
            @offsetOf(GeneralRegisters, "rcx"),
            @offsetOf(GeneralRegisters, "rdx"),
            @offsetOf(GeneralRegisters, "rsi"),
            @offsetOf(GeneralRegisters, "rdi"),
            @offsetOf(GeneralRegisters, "rbp"),
            @offsetOf(GeneralRegisters, "rsp"),
            @offsetOf(GeneralRegisters, "r8"),
            @offsetOf(GeneralRegisters, "r9"),
            @offsetOf(GeneralRegisters, "r10"),
            @offsetOf(GeneralRegisters, "r11"),
            @offsetOf(GeneralRegisters, "r12"),
            @offsetOf(GeneralRegisters, "r13"),
            @offsetOf(GeneralRegisters, "r14"),
            @offsetOf(GeneralRegisters, "r15"),
        })
        :
        : [general_base] "{rax}" (&registers),
        : "rax", "memory"
    );
    asm volatile (std.fmt.comptimePrint(
            \\ movups %%xmm0, {}(%[float_base])
            \\ movups %%xmm1, {}(%[float_base])
            \\ movups %%xmm2, {}(%[float_base])
            \\ movups %%xmm3, {}(%[float_base])
            \\ movups %%xmm4, {}(%[float_base])
            \\ movups %%xmm5, {}(%[float_base])
            \\ movups %%xmm6, {}(%[float_base])
            \\ movups %%xmm7, {}(%[float_base])
            \\ movups %%xmm8, {}(%[float_base])
            \\ movups %%xmm9, {}(%[float_base])
            \\ movups %%xmm10, {}(%[float_base])
            \\ movups %%xmm11, {}(%[float_base])
            \\ movups %%xmm12, {}(%[float_base])
            \\ movups %%xmm13, {}(%[float_base])
            \\ movups %%xmm14, {}(%[float_base])
            \\ movups %%xmm15, {}(%[float_base])
        , .{
            @offsetOf(FloatingRegisters, "xmm0"),
            @offsetOf(FloatingRegisters, "xmm1"),
            @offsetOf(FloatingRegisters, "xmm2"),
            @offsetOf(FloatingRegisters, "xmm3"),
            @offsetOf(FloatingRegisters, "xmm4"),
            @offsetOf(FloatingRegisters, "xmm5"),
            @offsetOf(FloatingRegisters, "xmm6"),
            @offsetOf(FloatingRegisters, "xmm7"),
            @offsetOf(FloatingRegisters, "xmm8"),
            @offsetOf(FloatingRegisters, "xmm9"),
            @offsetOf(FloatingRegisters, "xmm10"),
            @offsetOf(FloatingRegisters, "xmm11"),
            @offsetOf(FloatingRegisters, "xmm12"),
            @offsetOf(FloatingRegisters, "xmm13"),
            @offsetOf(FloatingRegisters, "xmm14"),
            @offsetOf(FloatingRegisters, "xmm15"),
        })
        :
        : [float_base] "r" (&float_registers),
        : "memory"
    );

    // custom code
    asm volatile (
        \\ callq %[onHook:P]
        :
        : [onHook] "X" (&onHook),
        : "rax", "rbx", "rcx", "rdx", "rsi", "rdi", "rbp", "rsp", "r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15", "memory"
    );

    // restoring state...
    asm volatile (std.fmt.comptimePrint(
            \\ movups {}(%[float_base]), %%xmm0
            \\ movups {}(%[float_base]), %%xmm1
            \\ movups {}(%[float_base]), %%xmm2
            \\ movups {}(%[float_base]), %%xmm3
            \\ movups {}(%[float_base]), %%xmm4
            \\ movups {}(%[float_base]), %%xmm5
            \\ movups {}(%[float_base]), %%xmm6
            \\ movups {}(%[float_base]), %%xmm7
            \\ movups {}(%[float_base]), %%xmm8
            \\ movups {}(%[float_base]), %%xmm9
            \\ movups {}(%[float_base]), %%xmm10
            \\ movups {}(%[float_base]), %%xmm11
            \\ movups {}(%[float_base]), %%xmm12
            \\ movups {}(%[float_base]), %%xmm13
            \\ movups {}(%[float_base]), %%xmm14
            \\ movups {}(%[float_base]), %%xmm15
        , .{
            @offsetOf(FloatingRegisters, "xmm0"),
            @offsetOf(FloatingRegisters, "xmm1"),
            @offsetOf(FloatingRegisters, "xmm2"),
            @offsetOf(FloatingRegisters, "xmm3"),
            @offsetOf(FloatingRegisters, "xmm4"),
            @offsetOf(FloatingRegisters, "xmm5"),
            @offsetOf(FloatingRegisters, "xmm6"),
            @offsetOf(FloatingRegisters, "xmm7"),
            @offsetOf(FloatingRegisters, "xmm8"),
            @offsetOf(FloatingRegisters, "xmm9"),
            @offsetOf(FloatingRegisters, "xmm10"),
            @offsetOf(FloatingRegisters, "xmm11"),
            @offsetOf(FloatingRegisters, "xmm12"),
            @offsetOf(FloatingRegisters, "xmm13"),
            @offsetOf(FloatingRegisters, "xmm14"),
            @offsetOf(FloatingRegisters, "xmm15"),
        })
        :
        : [float_base] "r" (&float_registers),
        : "memory"
    );
    asm volatile (std.fmt.comptimePrint(
            \\ mov {}(%[general_base]), %%rbx
            \\ mov {}(%[general_base]), %%rcx
            \\ mov {}(%[general_base]), %%rdx
            \\ mov {}(%[general_base]), %%rsi
            \\ mov {}(%[general_base]), %%rdi
            \\ mov {}(%[general_base]), %%rbp
            \\ mov {}(%[general_base]), %%rsp
            \\ mov {}(%[general_base]), %%r8
            \\ mov {}(%[general_base]), %%r9
            \\ mov {}(%[general_base]), %%r10
            \\ mov {}(%[general_base]), %%r11
            \\ mov {}(%[general_base]), %%r12
            \\ mov {}(%[general_base]), %%r13
            \\ mov {}(%[general_base]), %%r14
            \\ mov {}(%[general_base]), %%r15
        , .{
            @offsetOf(GeneralRegisters, "rbx"),
            @offsetOf(GeneralRegisters, "rcx"),
            @offsetOf(GeneralRegisters, "rdx"),
            @offsetOf(GeneralRegisters, "rsi"),
            @offsetOf(GeneralRegisters, "rdi"),
            @offsetOf(GeneralRegisters, "rbp"),
            @offsetOf(GeneralRegisters, "rsp"),
            @offsetOf(GeneralRegisters, "r8"),
            @offsetOf(GeneralRegisters, "r9"),
            @offsetOf(GeneralRegisters, "r10"),
            @offsetOf(GeneralRegisters, "r11"),
            @offsetOf(GeneralRegisters, "r12"),
            @offsetOf(GeneralRegisters, "r13"),
            @offsetOf(GeneralRegisters, "r14"),
            @offsetOf(GeneralRegisters, "r15"),
        })
        :
        : [general_base] "{rax}" (&registers),
        : "memory"
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
        : [_] "{rax}" (rax_value),
    );
}

pub const name = "DoSomething";

fn onHook() callconv(.c) void {
    // heck, we can even change register values directly from here!

    std.debug.print(
        \\On `DoSomething` custom hook!
        \\RAX: 0x{x}
        \\RBX: 0x{x}
        \\RCX: 0x{x}
        \\RDX: 0x{x}
        \\RSI: 0x{x}
        \\RDI: 0x{x}
        \\RBP: 0x{x}
        \\RSP: 0x{x}
        \\R8: 0x{x}
        \\R9: 0x{x}
        \\R10: 0x{x}
        \\R11: 0x{x}
        \\R12: 0x{x}
        \\R13: 0x{x}
        \\R14: 0x{x}
        \\R15: 0x{x}
    ,
        .{
            rax.*,
            rbx.*,
            rcx.*,
            rdx.*,
            rsi.*,
            rdi.*,
            rbp.*,
            rsp.*,
            r8.*,
            r9.*,
            r10.*,
            r11.*,
            r12.*,
            r13.*,
            r14.*,
            r15.*,
        },
    );
}
