const builtin = @import("builtin");
const std = @import("std");
const windows = std.os.windows;
const windows_extra = @import("windows_extra");

const WinConsole = @import("WinConsole.zig");
const Hooks = @import("Hooks.zig");

const g_allocator = std.heap.c_allocator;

export fn onUserInput(input_wstr: [*:0]const u8) callconv(.winapi) void {
    const input = std.mem.trim(u8, std.mem.span(input_wstr), &std.ascii.whitespace);
    WinConsole.println("User Input: {s}", .{input});
    if (std.ascii.eqlIgnoreCase(input, "all_window")) {
        const th = std.Thread.spawn(.{}, printAllWindowInfo, .{}) catch |err| {
            std.debug.print("Failed to spawn thread: {}\n", .{err});
            return;
        };
        th.detach();
    }
}

fn printWindowInfo(hwnd: windows.HWND) void {
    std.debug.print("Found window: 0x{X}\n", .{@intFromPtr(hwnd)});

    const wndproc = windows_extra.GetWindowLongPtr(hwnd, windows_extra.GWLP_WNDPROC);
    std.debug.print("wndproc = 0x{X}\n", .{wndproc});

    var class_name: [256:0]u16 = undefined;
    const class_name_len = windows_extra.GetClassNameW(hwnd, class_name[0..], @truncate(@as(isize, @intCast(class_name.len))));
    if (class_name_len == 0) {
        std.debug.print("Failed to get class name: {}\n", .{windows.GetLastError()});
    } else {
        var class_name_str: [256]u8 = undefined;
        const class_name_str_len = std.unicode.utf16LeToUtf8(&class_name_str, class_name[0..@intCast(class_name_len)]) catch |err| {
            std.debug.print("Failed to convert class name: {}\n", .{err});
            return;
        };
        std.debug.print("Class Name: {s}\n", .{class_name_str[0..class_name_str_len]});
    }
}

fn printAllWindowInfo() void {
    const wait_time = 5;
    std.debug.print("Will try to print all the window in {} seconds...\n", .{wait_time});
    std.Thread.sleep(std.time.ns_per_s * wait_time);
    const current_pid = windows.GetCurrentProcessId();
    var hwnd_opt = windows_extra.GetTopWindow(windows_extra.GetDesktopWindow());

    while (hwnd_opt) |hwnd| : (hwnd_opt = windows_extra.GetNextWindow(hwnd, windows_extra.GW_HWNDNEXT)) {
        var pid: windows.DWORD = 0;
        _ = windows_extra.GetWindowThreadProcessId(hwnd, &pid);

        if (pid == current_pid) {
            printWindowInfo(hwnd);
        }
    }
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

            _ = windows_extra.DisableThreadLibraryCalls(hmodule);
            Hooks.init() catch |err| {
                std.debug.print("Failed to init hooks: {}\n", .{err});
            };
        },
        windows_extra.DLL_PROCESS_DETACH => {
            Hooks.deinit();

            //if (builtin.mode == .Debug) {
            // WinConsole.deinit();
            //}
        },
        else => {},
    }

    return windows.TRUE;
}
