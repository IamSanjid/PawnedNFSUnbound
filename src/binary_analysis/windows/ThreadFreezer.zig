/// Suspends threads in a Windows process to freeze its execution.
const std = @import("std");
const windows = std.os.windows;
const windows_extra = @import("windows_extra");

const ThreadFreezer = @This();

ids: std.ArrayList(windows.DWORD),

/// This will immidiately suspend all threads in the current process except the current thread.
pub fn init(allocator: std.mem.Allocator) !ThreadFreezer {
    var ids = try scanThreads(allocator);

    // Freezing threads now...
    var i: usize = ids.items.len - 1;
    while (true) : (i -= 1) {
        const id = ids.items[i];
        const thread_handle = windows_extra.OpenThread(
            windows_extra.THREAD_SUSPEND_RESUME | windows_extra.THREAD_QUERY_INFORMATION,
            windows.FALSE,
            id,
        );
        if (thread_handle == windows.INVALID_HANDLE_VALUE) {
            _ = ids.orderedRemove(i);
        } else {
            defer windows.CloseHandle(thread_handle);
            _ = windows_extra.SuspendThread(thread_handle);
        }
        if (i == 0) break;
    }

    return .{ .ids = ids };
}

/// Resumes all threads that were suspended by `init`.
pub fn deinit(self: ThreadFreezer) void {
    for (self.ids.items) |id| {
        const thread_handle = windows_extra.OpenThread(windows_extra.THREAD_SUSPEND_RESUME, windows.FALSE, id);
        if (thread_handle != windows.INVALID_HANDLE_VALUE) {
            defer windows.CloseHandle(thread_handle);
            _ = windows_extra.ResumeThread(thread_handle);
        }
    }
    self.ids.deinit();
}

fn scanThreads(allocator: std.mem.Allocator) !std.ArrayList(windows.DWORD) {
    var ids = std.ArrayList(windows.DWORD).init(allocator);
    errdefer ids.deinit();

    const th_snap_shot = windows.kernel32.CreateToolhelp32Snapshot(windows.TH32CS_SNAPTHREAD, 0);
    if (th_snap_shot == windows.INVALID_HANDLE_VALUE) {
        return ids;
    }
    defer windows.CloseHandle(th_snap_shot);

    var th_entry: windows_extra.THREADENTRY32 = undefined;
    th_entry.dwSize = @sizeOf(windows_extra.THREADENTRY32);
    if (windows_extra.Thread32First(th_snap_shot, &th_entry) == windows.FALSE) {
        return ids;
    }
    if (isThreadEntryOkay(th_entry)) {
        try ids.append(th_entry.th32ThreadID);
    }
    th_entry.dwSize = @sizeOf(windows_extra.THREADENTRY32);
    while (windows_extra.Thread32Next(th_snap_shot, &th_entry) == windows.TRUE) {
        if (isThreadEntryOkay(th_entry)) {
            try ids.append(th_entry.th32ThreadID);
        }
        th_entry.dwSize = @sizeOf(windows_extra.THREADENTRY32);
    }
    if (windows.GetLastError() != windows.Win32Error.NO_MORE_FILES) {
        return error.FailedToEnumerateThreads;
    }

    return ids;
}

fn isThreadEntryOkay(entry: windows_extra.THREADENTRY32) bool {
    if (entry.dwSize < (@offsetOf(windows_extra.THREADENTRY32, "th32OwnerProcessID") + @sizeOf(windows.DWORD))) {
        return false;
    }
    if (entry.th32OwnerProcessID != windows.GetCurrentProcessId()) {
        return false;
    }
    if (entry.th32ThreadID == windows.GetCurrentThreadId()) {
        return false;
    }
    return true;
}
