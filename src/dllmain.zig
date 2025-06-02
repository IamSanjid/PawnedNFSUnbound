const builtin = @import("builtin");
const std = @import("std");
const windows = std.os.windows;
const windows_extra = @import("windows_extra");

const c = @cImport({
    @cDefine("WIN32_LEAN_AND_MEAN", "1");
    @cInclude("windows.h");
    @cInclude("detours.h");
});

const WinConsole = @import("WinConsole.zig");
const Hooks = @import("Hooks.zig");

const g_allocator = std.heap.c_allocator;

export fn onUserInput(input: [*:0]const u8) callconv(.winapi) void {
    WinConsole.println("User Input: {s}", .{input});
}

// fn mainThread(module: windows.HMODULE) !void {
//     const reader = WinConsole.stdinReader() orelse return;
//     WinConsole.println("DllModule: {}\n", .{module});

//     while (true) {
//         const str = (try reader.readUntilDelimiterOrEofAlloc(g_allocator, '\n', 4096)) orelse return;
//         WinConsole.println("ECHO: {s}", .{str});
//     }
//     // const reader = std.io.getStdIn().reader();
//     // const writer = std.io.getStdOut().writer();
//     // try writer.print("DllModule: {}\n", .{module});

//     // while (true) {
//     //     const str = (try reader.readUntilDelimiterOrEofAlloc(g_allocator, '\n', 4096)) orelse return;
//     //     try writer.print("ECHO: {s}\n", .{str});
//     // }

//     // TODO: Implement GUI?
// }

pub fn DllMain(hinst: windows.HINSTANCE, dw_reason: windows.DWORD, _: windows.LPVOID) callconv(.winapi) windows.BOOL {
    const hmodule: windows.HMODULE = @ptrCast(hinst);

    if (c.DetourIsHelperProcess() != 0) {
        return windows.TRUE;
    }

    switch (dw_reason) {
        windows_extra.DLL_PROCESS_ATTACH => {
            //if (builtin.mode == .Debug) {
            // WinConsole.init() catch |err| {
            //     if (err == WinConsole.Errors.FailedToAllocateConsole) {
            //         std.debug.print("Failed to allocate console: {}\n", .{windows.GetLastError()});
            //     } else {
            //         std.debug.print("Failed to initialize console: {}\n", .{err});
            //     }
            // };
            //}

            // const th = std.Thread.spawn(.{}, mainThread, .{hmodule}) catch |err| {
            //     std.debug.print("Failed to spawn thread: {}\n", .{err});
            //     return windows.FALSE;
            // };
            // th.detach();

            _ = c.DetourRestoreAfterWith();
            _ = windows_extra.DisableThreadLibraryCalls(hmodule);
            _ = c.DetourTransactionBegin();
            _ = c.DetourUpdateThread(windows.GetCurrentThread());
            Hooks.init() catch |err| {
                std.debug.print("Failed to init hooks: {}\n", .{err});
            };
            _ = c.DetourTransactionCommit();
        },
        windows_extra.DLL_PROCESS_DETACH => {
            _ = c.DetourTransactionBegin();
            _ = c.DetourUpdateThread(windows.GetCurrentThread());
            Hooks.deinit();
            _ = c.DetourTransactionCommit();

            //if (builtin.mode == .Debug) {
            // WinConsole.deinit();
            //}
            //_ = windows_extra.FreeLibraryAndExitThread(hmodule, 0);
        },
        else => {},
    }

    return windows.TRUE;
}
