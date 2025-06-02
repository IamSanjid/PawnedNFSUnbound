const builtin = @import("builtin");
const std = @import("std");
const windows = std.os.windows;
const windows_extra = @import("windows_extra");

const WinConsole = @import("WinConsole.zig");

const g_allocator = std.heap.c_allocator;

const OnUserInputFn = fn ([*:0]const u8) callconv(.winapi) void;

const Dll = struct {
    handle: ?windows.HMODULE = null,
    path: []const u8,

    fn load(path: []const u8) !Dll {
        const path_copy = if (std.ascii.endsWithIgnoreCase(path, ".dll"))
            try g_allocator.dupe(u8, path)
        else
            try std.fmt.allocPrint(g_allocator, "{s}.dll", .{path});
        errdefer g_allocator.free(path_copy);

        const dll_path_w = windows.sliceToPrefixedFileW(null, path_copy) catch return error.InvalidPath;
        const handle = windows.kernel32.LoadLibraryW(dll_path_w.span()) orelse return error.LoadLibraryFailed;
        return Dll{
            .handle = handle,
            .path = path_copy,
        };
    }

    fn reload(self: *Dll) !void {
        if (self.handle) |handle| {
            _ = windows.kernel32.FreeLibrary(handle);
        }

        const dll_path_w = windows.sliceToPrefixedFileW(null, self.path) catch unreachable;
        self.handle = windows.kernel32.LoadLibraryW(dll_path_w.span()) orelse return error.LoadLibraryFailed;
    }

    fn getFn(self: Dll, comptime FnType: type, fn_name: [:0]const u8) ?*FnType {
        if (self.handle) |handle| {
            const fn_ptr = windows.kernel32.GetProcAddress(handle, fn_name.ptr) orelse return null;
            return @ptrCast(@alignCast(fn_ptr));
        }
        return null;
    }

    fn deinit(self: Dll) void {
        if (self.handle) |handle| {
            _ = windows.kernel32.FreeLibrary(handle);
        }
        g_allocator.free(self.path);
    }
};

var loaded_dlls = std.StringArrayHashMap(Dll).init(g_allocator);

fn sanitizePath(dll_path: []const u8) []const u8 {
    return std.mem.trim(u8, std.mem.trim(u8, dll_path, "\""), &std.ascii.whitespace);
}

fn loadDll(path: []const u8) !void {
    const dll_info = try Dll.load(sanitizePath(path));
    const dll_name = std.mem.trimEnd(u8, std.fs.path.basename(dll_info.path), ".dll");
    try loaded_dlls.put(dll_name, dll_info);
}

fn reloadDll(path: []const u8) !void {
    const dll_path = sanitizePath(path);
    const dll_name = if (std.ascii.endsWithIgnoreCase(dll_path, ".dll"))
        std.mem.trimEnd(u8, std.fs.path.basename(dll_path), ".dll")
    else
        dll_path;

    const dll_entry = loaded_dlls.getEntry(dll_name) orelse return;
    const dll_info = dll_entry.value_ptr;

    try dll_info.reload();
}

fn unloadDll(path: []const u8) bool {
    const dll_path = sanitizePath(path);
    const dll_name = if (std.ascii.endsWithIgnoreCase(dll_path, ".dll"))
        std.mem.trimEnd(u8, std.fs.path.basename(dll_path), ".dll")
    else
        dll_path;

    const dll_entry = loaded_dlls.fetchSwapRemove(dll_name) orelse return false;
    dll_entry.value.deinit();
    return true;
}

fn mainThread(module: windows.HMODULE) !void {
    const reader = WinConsole.stdinReader() orelse return;
    WinConsole.println("DllModule: {}\n", .{module});

    var buffer: [512]u8 = undefined;

    while (true) {
        const str = try reader.readUntilDelimiter(&buffer, '\n');

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
                WinConsole.println("Usage: reload <dll_path/name>", .{});
                continue;
            }
            const dll_path = full_cmd[cmd.len + 1 ..]; // +1 for space
            reloadDll(dll_path) catch |e| {
                WinConsole.eprintln(
                    "Failed to re-load DLL: {s} for {}, last error: {}",
                    .{ dll_path, e, windows.GetLastError() },
                );
                continue;
            };
        } else if (std.ascii.eqlIgnoreCase(cmd, "unload")) {
            if (splitted.peek() == null) {
                WinConsole.println("Usage: load <dll_path/name>", .{});
                continue;
            }
            const dll_path = full_cmd[cmd.len + 1 ..]; // +1 for space
            if (unloadDll(dll_path)) WinConsole.println("DLL unloaded: {s}", .{dll_path});
        } else if (std.ascii.eqlIgnoreCase(cmd, "list")) {
            var iter = loaded_dlls.iterator();
            while (iter.next()) |entry| {
                WinConsole.eprintln("Loaded DLL: {s} at {x}", .{ entry.key_ptr.*, entry.value_ptr.handle.? });
            }
        } else {
            var iter = loaded_dlls.iterator();
            while (iter.next()) |entry| {
                const onUserInput = entry.value_ptr.getFn(OnUserInputFn, "onUserInput") orelse {
                    WinConsole.eprintln("Couldn't find `onUserInput` in {s}", .{entry.value_ptr.path});
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
