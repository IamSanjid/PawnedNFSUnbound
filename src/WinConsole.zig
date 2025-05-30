const std = @import("std");
const windows = std.os.windows;
const windows_extra = @import("windows_extra");

const File = std.fs.File;

pub const Errors = error{
    FailedToAllocateConsole,
};

const allocator = std.heap.c_allocator;

var initialized = std.atomic.Value(bool).init(false);

var stdin: ?*File = null;
var stdout: ?*File = null;
var stderr: ?*File = null;

var last_stdin_handle: ?windows.HANDLE = null;
var last_stdout_handle: ?windows.HANDLE = null;
var last_stderr_handle: ?windows.HANDLE = null;

var out_lock = std.Thread.RwLock{};
var in_lock = std.Thread.RwLock{};

pub fn init() !void {
    if (initialized.load(.seq_cst)) return;
    if (windows_extra.AllocConsole() == windows.FALSE) {
        return Errors.FailedToAllocateConsole;
    }

    out_lock.lock();
    defer out_lock.unlock();
    in_lock.lock();
    defer in_lock.unlock();

    const stdin_handle = windows.kernel32.CreateFileW(
        std.unicode.utf8ToUtf16LeStringLiteral("CONIN$"),
        windows.GENERIC_READ,
        windows.FILE_SHARE_READ,
        null,
        windows.OPEN_EXISTING,
        0,
        null,
    );
    if (stdin_handle == windows.INVALID_HANDLE_VALUE) {
        return error.CreateFileError;
    }
    errdefer windows.CloseHandle(stdin_handle);
    last_stdin_handle = windows.kernel32.GetStdHandle(windows.STD_INPUT_HANDLE);
    _ = windows_extra.SetStdHandle(windows.STD_INPUT_HANDLE, stdin_handle);

    const stdout_handle = windows.kernel32.CreateFileW(
        std.unicode.utf8ToUtf16LeStringLiteral("CONOUT$"),
        windows.GENERIC_WRITE,
        windows.FILE_SHARE_WRITE,
        null,
        windows.OPEN_EXISTING,
        0,
        null,
    );
    if (stdout_handle == windows.INVALID_HANDLE_VALUE) {
        return error.CreateFileError;
    }
    errdefer windows.CloseHandle(stdout_handle);
    last_stdout_handle = windows.kernel32.GetStdHandle(windows.STD_OUTPUT_HANDLE);
    _ = windows_extra.SetStdHandle(windows.STD_OUTPUT_HANDLE, stdout_handle);

    const stderr_handle = windows.kernel32.CreateFileW(
        std.unicode.utf8ToUtf16LeStringLiteral("CONOUT$"),
        windows.GENERIC_WRITE,
        windows.FILE_SHARE_WRITE,
        null,
        windows.OPEN_EXISTING,
        0,
        null,
    );
    if (stderr_handle == windows.INVALID_HANDLE_VALUE) {
        return error.CreateFileError;
    }
    errdefer windows.CloseHandle(stderr_handle);
    last_stderr_handle = windows.kernel32.GetStdHandle(windows.STD_ERROR_HANDLE);
    _ = windows_extra.SetStdHandle(windows.STD_ERROR_HANDLE, stderr_handle);

    const conin = try allocator.create(File);
    errdefer allocator.destroy(conin);
    conin.* = .{ .handle = stdin_handle };

    const conout = try allocator.create(File);
    errdefer allocator.destroy(conout);
    conout.* = .{ .handle = stdout_handle };

    stdin = conin;
    stdout = conout;
    stderr = conout;

    initialized.store(true, .seq_cst);
}

pub fn deinit() void {
    if (!initialized.load(.seq_cst)) return;
    out_lock.lock();
    defer out_lock.unlock();
    in_lock.lock();
    defer in_lock.unlock();

    if (stdin) |s| {
        s.close();
        allocator.destroy(s);
        stdin = null;
    }
    if (stdout) |s| {
        s.close();
        allocator.destroy(s);
        stdout = null;
    }
    if (stderr) |s| {
        s.close();
        allocator.destroy(s);
        stderr = null;
    }

    if (last_stdin_handle) |h| {
        _ = windows_extra.SetStdHandle(windows.STD_INPUT_HANDLE, h);
        last_stdin_handle = null;
    }
    if (last_stdout_handle) |h| {
        _ = windows_extra.SetStdHandle(windows.STD_OUTPUT_HANDLE, h);
        last_stdout_handle = null;
    }
    if (last_stderr_handle) |h| {
        _ = windows_extra.SetStdHandle(windows.STD_ERROR_HANDLE, h);
        last_stderr_handle = null;
    }

    initialized.store(false, .seq_cst);
    _ = windows_extra.FreeConsole();
}

fn stdinReadImpl(self: *File, buffer: []u8) File.ReadError!usize {
    in_lock.lock();
    defer in_lock.unlock();
    return self.read(buffer);
}

pub fn stdinRead(buffer: []u8) File.ReadError!usize {
    if (!initialized.load(.seq_cst)) return error.NotOpenForReading;
    return stdinReadImpl(stdin.?, buffer);
}

pub const StdinReader = std.io.GenericReader(*File, File.ReadError, stdinReadImpl);
pub fn stdinReader() ?StdinReader {
    if (!initialized.load(.seq_cst)) return null;
    return .{ .context = stdin.? };
}

pub fn println(comptime format: []const u8, args: anytype) void {
    if (!initialized.load(.seq_cst)) {
        std.debug.print(format ++ "\n", args);
        return;
    }
    out_lock.lock();
    defer out_lock.unlock();
    nosuspend stdout.?.writer().print(format ++ "\n", args) catch return;
}

pub fn eprintln(comptime format: []const u8, args: anytype) void {
    if (!initialized.load(.seq_cst)) {
        std.debug.print(format ++ "\n", args);
        return;
    }
    out_lock.lock();
    defer out_lock.unlock();
    nosuspend stderr.?.writer().print(format ++ "\n", args) catch return;
}
