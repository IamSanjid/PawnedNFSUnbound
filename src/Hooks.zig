const std = @import("std");
const windows = std.os.windows;

const c = @cImport({
    @cDefine("WIN32_LEAN_AND_MEAN", "1");
    @cInclude("windows.h");
    @cInclude("detours.h");
});

const ba = @import("binary_analysis");

const WinConsole = @import("WinConsole.zig");
const g_allocator = std.heap.c_allocator;

const Errors = error{
    HookAddressNotFound,
    HookFailed,
    HookAlreadyExists,
    HookNotFound,
};

const DetourHookInfo = struct {
    address: usize,
    detour: usize,
    trampoline: usize,
};

const AbsoluteHookInfo = struct {
    address: usize,
    detour: usize,
    trampoline: []u8,
    original_code_offset: usize,
};

var detour_hooks = std.StringArrayHashMap(*DetourHookInfo).init(g_allocator);
var absolute_hooks = std.StringArrayHashMap(*AbsoluteHookInfo).init(g_allocator);
var disasmbler: ba.disasm.x86_64 = undefined;

fn getAddressForHook(module_name: []const u8, hook_name: []const u8) ?usize {
    const module_name_w = std.unicode.utf8ToUtf16LeAllocZ(g_allocator, module_name) catch return null;
    defer g_allocator.free(module_name_w);

    const module_addr_opt = windows.kernel32.GetModuleHandleW(module_name_w);
    if (module_addr_opt == null) {
        return null;
    }
    const module_addr: usize = @intFromPtr(module_addr_opt.?);

    // TODO: Get offset from config or do AOB search and stuff...

    // Auto-Generated!!!
    if (std.ascii.eqlIgnoreCase(hook_name, "DoSomething")) {
        // ptest.exe+182C2
        //return module_addr + 0x182D5;
        return module_addr + 0x182C2;
    }
    // Auto-Generated!!!
    if (std.ascii.eqlIgnoreCase(hook_name, "DoSomething2")) {
        return module_addr + 0x13839;
    }
    // Auto-Generated!!!
    if (std.ascii.eqlIgnoreCase(hook_name, "AllRaceAvailable")) {
        return module_addr + 0x2313424;
    }
    // Auto-Generated!!!
    if (std.ascii.eqlIgnoreCase(hook_name, "RaceConfigCopy")) {
        return module_addr + 0x25A1737;
    }
    if (std.ascii.eqlIgnoreCase(hook_name, "RaceConfigCopyReset")) {
        return module_addr + 0x9066BC4;
    }
    return null;
}

// TODO: Don't need this when we can find some way to do direct `jmp *something`, `something` needs to be exported for now it to work.
fn prepareDetourWithJmp(detour_addr: usize, jmp_to: usize) !void {
    @setRuntimeSafety(false); // alignments probably will not be fine so we just gonna trust ourselves

    const detour_code: [*]u8 = @ptrFromInt(detour_addr);

    const max_ending_index = 512;
    const extra_detour_space = 16;

    var ending_index: usize = 0;
    var next_instruction: u8 = 0x90; // nop
    var matches: usize = 0;
    while (ending_index <= max_ending_index) {
        if (detour_code[ending_index] == next_instruction) {
            matches += 1;
            next_instruction = if (next_instruction == 0x90) 0xCC else 0x90;
        }

        ending_index += 1; // breaking after +1 so that we point to the first 0x90
        // usually on x86_64 a full raw absolute address jump needs 14 bytes :")
        if (matches == extra_detour_space) {
            break;
        }
    }

    if (ending_index >= max_ending_index) {
        return error.DetourInvalidOrTooLong;
    }
    ending_index -= matches;

    _ = try ba.windows.x86_64.trampoline.emitAbsoluteJmp(detour_addr + ending_index, jmp_to, null);
}

fn hook(on_module: []const u8, hook_name: []const u8, to_detour: usize) !*DetourHookInfo {
    const hook_addr = getAddressForHook(on_module, hook_name) orelse return Errors.HookAddressNotFound;
    const hook_info = detour_hooks.get(hook_name) orelse {
        var ret_trampoline: c.PDETOUR_TRAMPOLINE = null;

        var target_addr: c.PVOID = @alignCast(@as(c.PVOID, @ptrFromInt(hook_addr)));
        const detour_addr: c.PVOID = @alignCast(@as(c.PVOID, @ptrFromInt(to_detour)));

        const detour_err = c.DetourAttachEx(&target_addr, detour_addr, &ret_trampoline, null, null);
        if (detour_err != c.NO_ERROR) {
            WinConsole.eprintln("Failed to hook: {s}, error: {}", .{ hook_name, detour_err });
            return Errors.HookFailed;
        }

        const trampoline_addr = @intFromPtr(ret_trampoline);
        prepareDetourWithJmp(to_detour, trampoline_addr) catch |err| {
            WinConsole.eprintln("Failed to prepare jmp instruction of hook: {s}", .{hook_name});
            return err;
        };

        const new_hook_info = try g_allocator.create(DetourHookInfo);
        errdefer g_allocator.destroy(new_hook_info);
        new_hook_info.* = DetourHookInfo{
            .address = hook_addr,
            .detour = to_detour,
            .trampoline = trampoline_addr,
        };

        try detour_hooks.put(hook_name, new_hook_info);
        return new_hook_info;
    };

    return hook_info;
}

fn hookAbsolute(on_module: []const u8, hook_name: []const u8, to_detour: usize) !*AbsoluteHookInfo {
    @setRuntimeSafety(false);

    const hook_addr = getAddressForHook(on_module, hook_name) orelse return Errors.HookAddressNotFound;
    const hook_info = absolute_hooks.get(hook_name) orelse {
        const found_region = ba.any.x86_64.safe_overwrite_boundary.find(disasmbler, hook_addr, 14) orelse {
            WinConsole.eprintln("Failed to find safe overwrite boundary for hook: {s}", .{hook_name});
            return Errors.HookFailed;
        };
        const overwrite_bytes = found_region.safe_size;
        const original_code: []const u8 = @as([*]const u8, @ptrFromInt(hook_addr))[0..overwrite_bytes];
        const disasm_iter_res = found_region.disasm_iter_res;

        const fixed = ba.any.x86_64.relative_rip_instructions.fix(
            g_allocator,
            disasm_iter_res,
            14,
        ) catch |err| {
            WinConsole.eprintln("Failed to fix relative rip changes code for hook: {s}, error: {}", .{ hook_name, err });
            return err;
        };
        defer g_allocator.free(fixed.code);

        const code = fixed.code;
        const jmp_back_write_offset = fixed.reserved_offset;

        const ret_trampoline = ba.windows.trampoline.alloc(code.len + original_code.len) catch |err| {
            WinConsole.eprintln("Failed to allocate trampoline for hook: {s}, error: {}", .{ hook_name, err });
            return err;
        };
        // copy the fixed/original code to the trampoline
        @memcpy(ret_trampoline, code);
        @memcpy(ret_trampoline[code.len..], original_code);

        // check if original code is ending with jmp or ret instruction
        const ending_ins = ba.any.x86_64.func_end.detect(disasm_iter_res);
        // overwrite the target instructions with jmp to trampoline
        const jmp_back_original = try ba.windows.x86_64.trampoline.emitAbsoluteJmp(hook_addr, to_detour, overwrite_bytes);
        if (ending_ins) |end_ins| {
            WinConsole.println("Ending pos: {}", .{end_ins});
        } else {
            // if there is no ending instruction, we need to write a jmp back to the original code
            _ = try ba.windows.x86_64.trampoline.emitAbsoluteJmp(@intFromPtr(ret_trampoline.ptr) + jmp_back_write_offset, jmp_back_original, null);
        }

        prepareDetourWithJmp(to_detour, @intFromPtr(ret_trampoline.ptr)) catch |err| {
            WinConsole.eprintln("Failed to prepare jmp instruction of hook: {s}, error: {}", .{ hook_name, err });
            return err;
        };
        const new_hook_info = try g_allocator.create(AbsoluteHookInfo);
        errdefer g_allocator.destroy(new_hook_info);
        new_hook_info.* = AbsoluteHookInfo{
            .address = hook_addr,
            .detour = to_detour,
            .trampoline = ret_trampoline,
            .original_code_offset = code.len,
        };
        try absolute_hooks.put(hook_name, new_hook_info);
        return new_hook_info;
    };

    return hook_info;
}

pub fn init() !void {
    disasmbler = try ba.disasm.x86_64.create(.{});

    // Auto-Generated!!!
    //_ = try hookAbsolute("ptest.exe", "DoSomething", @intFromPtr(&(@import("hooks/DoSomething.zig").hookFn)), 14);
    //_ = try hook("ptest.exe", "DoSomething", @intFromPtr(&(@import("hooks/DoSomething.zig").hookFn)));

    // Auto-Generated!!!
    //_ = try hook("ptest.exe", "DoSomething2", @intFromPtr(&(@import("hooks/DoSomething2.zig").hookFn)));

    // Auto-Generated!!!
    //_ = try hookAbsolute("NeedForSpeedUnbound.exe", "AllRaceAvailable", @intFromPtr(&(@import("hooks/AllRaceAvailable.zig").hookFn)));

    // Auto-Generated!!!
    _ = try hookAbsolute("NeedForSpeedUnbound.exe", "RaceConfigCopy", @intFromPtr(&(@import("hooks/RaceConfigCopy.zig").hookFn)));
    _ = try hookAbsolute("NeedForSpeedUnbound.exe", "RaceConfigCopyReset", @intFromPtr(&(@import("hooks/RaceConfigCopy.zig").hookFn2)));
}

pub fn deinit() void {
    var detour_hooks_iter = detour_hooks.iterator();
    while (detour_hooks_iter.next()) |hk| {
        var target_addr: c.PVOID = @alignCast(@as(c.PVOID, @ptrFromInt(hk.value_ptr.*.address)));
        const detour_addr: c.PVOID = @alignCast(@as(c.PVOID, @ptrFromInt(hk.value_ptr.*.detour)));
        _ = c.DetourDetach(&target_addr, detour_addr);

        g_allocator.destroy(hk.value_ptr.*);
    }
    detour_hooks.clearRetainingCapacity();

    var absolute_hooks_iter = absolute_hooks.iterator();
    while (absolute_hooks_iter.next()) |hk| {
        const hook_info = hk.value_ptr.*;
        if (hook_info.trampoline.len > 0) {
            if (hook_info.original_code_offset > 0) {
                const restore_code = hook_info.trampoline[hook_info.original_code_offset..];
                ba.windows.trampoline.restore(hook_info.address, restore_code) catch |err| {
                    WinConsole.eprintln("Failed to restore original code for hook: {s}, error: {}", .{ hk.key_ptr.*, err });
                };
            }
            ba.windows.trampoline.free(hook_info.trampoline);
        }
        g_allocator.destroy(hook_info);
    }
    absolute_hooks.clearRetainingCapacity();
    disasmbler.deinit();
}
