const builtin = @import("builtin");
const std = @import("std");
const windows = std.os.windows;
const windows_extra = @import("windows_extra");

const WinConsole = @import("WinConsole.zig");

const g_allocator = std.heap.c_allocator;

const OnUserInputFn = fn ([*:0]const u8) callconv(.winapi) void;

const Dll = struct {
    handle: ?std.DynLib = null,
    path: []const u8,

    fn load(path: []const u8) !Dll {
        const path_copy = if (std.ascii.endsWithIgnoreCase(path, ".dll"))
            try g_allocator.dupe(u8, path)
        else
            try std.fmt.allocPrint(g_allocator, "{s}.dll", .{path});
        errdefer g_allocator.free(path_copy);

        const handle = try std.DynLib.open(path_copy);
        return Dll{
            .handle = handle,
            .path = path_copy,
        };
    }

    fn reload(self: *Dll) !void {
        if (self.handle) |*handle| {
            handle.close();
        }

        self.handle = try std.DynLib.open(self.path);
    }

    fn getFn(self: *Dll, comptime FnType: type, fn_name: [:0]const u8) ?*FnType {
        if (self.handle) |*handle| {
            return handle.lookup(*FnType, fn_name) orelse return null;
        }
        return null;
    }

    fn deinit(self: *Dll) void {
        if (self.handle) |*handle| {
            handle.close();
        }
        self.handle = null;
        g_allocator.free(self.path);
    }
};

var loaded_dlls = std.ArrayList(Dll).init(g_allocator);

fn sanitizePath(dll_path: []const u8) []const u8 {
    return std.mem.trim(u8, std.mem.trim(u8, dll_path, "\""), &std.ascii.whitespace);
}

fn loadDll(path: []const u8) !void {
    const dll = try Dll.load(sanitizePath(path));
    try loaded_dlls.append(dll);
}

fn reloadDll(index: usize) !void {
    if (index >= loaded_dlls.items.len) return error.IndexOutOfBounds;

    var dll = loaded_dlls.items[index];
    try dll.reload();
}

fn unloadDll(index: usize) bool {
    if (index >= loaded_dlls.items.len) return false;

    var dll = loaded_dlls.orderedRemove(index);
    dll.deinit();

    return true;
}

fn mainThread(module: windows.HMODULE) !void {
    var buffer: [512]u8 = undefined;
    var reader = WinConsole.stdinReader(&buffer) orelse return;
    WinConsole.println("DllModule: {}\n", .{module});

    while (true) {
        const str = try reader.interface.takeDelimiterExclusive('\n');

        const full_cmd = std.mem.trim(u8, str, &std.ascii.whitespace);
        var splitted = std.mem.splitScalar(u8, full_cmd, ' ');
        const cmd = splitted.next() orelse continue;

        if (std.ascii.eqlIgnoreCase(cmd, "load")) {
            if (splitted.peek() == null) {
                WinConsole.println("Usage: load <dll_path>", .{});
                continue;
            }
            const dll_path = full_cmd[cmd.len + 1 ..]; // +1 for space
            loadDll(dll_path) catch |e| {
                WinConsole.eprintln(
                    "Failed to load DLL: {s} for {}, last error: {}",
                    .{ dll_path, e, windows.GetLastError() },
                );
                continue;
            };
        } else if (std.ascii.eqlIgnoreCase(cmd, "reload")) {
            if (splitted.peek() == null) {
                WinConsole.println("Usage: reload <index(use `list` cmd to check)>", .{});
                continue;
            }
            const dll_index = full_cmd[cmd.len + 1 ..];
            const index = std.fmt.parseInt(usize, dll_index, 0) catch {
                WinConsole.eprintln("Usage: reload <index(use `list` cmd to check)>", .{});
                continue;
            };
            reloadDll(index) catch |e| {
                WinConsole.eprintln(
                    "Failed to re-load DLL index {} for {}, last error: {}",
                    .{ index, e, windows.GetLastError() },
                );
                continue;
            };
        } else if (std.ascii.eqlIgnoreCase(cmd, "unload")) {
            if (splitted.peek() == null) {
                WinConsole.println("Usage: unload <index(use `list` cmd to check)>", .{});
                continue;
            }
            const dll_index = full_cmd[cmd.len + 1 ..];
            const index = std.fmt.parseInt(usize, dll_index, 0) catch {
                WinConsole.eprintln("Usage: reload <index(use `list` cmd to check)>", .{});
                continue;
            };
            if (unloadDll(index)) WinConsole.println("DLL unloaded index: {}", .{index});
        } else if (std.ascii.eqlIgnoreCase(cmd, "list")) {
            for (loaded_dlls.items, 0..) |dll, i| {
                WinConsole.eprintln("Loaded DLL: [{}] {s}", .{ i, dll.path });
            }
        } else {
            for (loaded_dlls.items) |*dll| {
                const onUserInput = dll.getFn(OnUserInputFn, "onUserInput") orelse {
                    WinConsole.eprintln("Couldn't find `onUserInput` in {s}", .{dll.path});
                    continue;
                };
                const str_z = try g_allocator.dupeZ(u8, str);
                defer g_allocator.free(str_z);
                onUserInput(str_z.ptr);
            }
            WinConsole.println("ECHO: {s}", .{str});
        }
    }

    // TODO: Implement GUI?
}

pub fn DllMain(hinst: windows.HINSTANCE, dw_reason: windows.DWORD, reserved: windows.LPVOID) callconv(.winapi) windows.BOOL {
    _ = reserved;
    const hmodule: windows.HMODULE = @ptrCast(hinst);

    switch (dw_reason) {
        windows_extra.DLL_PROCESS_ATTACH => {
            //if (builtin.mode == .Debug) {
            WinConsole.init() catch |err| {
                if (err == WinConsole.Errors.FailedToAllocateConsole) {
                    std.debug.print("Failed to allocate console: {}\n", .{windows.GetLastError()});
                } else {
                    std.debug.print("Failed to initialize console: {}\n", .{err});
                }
            };
            //}

            const th = std.Thread.spawn(.{}, mainThread, .{hmodule}) catch |err| {
                std.debug.print("Failed to spawn thread: {}\n", .{err});
                return windows.FALSE;
            };
            th.detach();
        },
        windows_extra.DLL_THREAD_ATTACH => {},
        windows_extra.DLL_THREAD_DETACH => {},
        windows_extra.DLL_PROCESS_DETACH => {

            //if (builtin.mode == .Debug) {
            WinConsole.deinit();
            //}
        },
        else => {},
    }

    return windows.TRUE;
}
