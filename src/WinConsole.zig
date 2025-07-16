const std = @import("std");
const windows = std.os.windows;
const windows_extra = @import("windows_extra");

const File = std.fs.File;

pub const Errors = error{
    FailedToAllocateConsole,
};

var initialized = std.atomic.Value(bool).init(false);

var last_stdin_handle: ?windows.HANDLE = null;
var last_stdout_handle: ?windows.HANDLE = null;
var last_stderr_handle: ?windows.HANDLE = null;

var out_lock = std.Thread.RwLock{};
var in_lock = std.Thread.RwLock{};

const default_file_reader: std.Io.Reader = std.fs.File.Reader.initInterface(&.{});

fn stdinStream(io_reader: *std.Io.Reader, w: *std.Io.Writer, limit: std.Io.Limit) std.Io.Reader.StreamError!usize {
    in_lock.lock();
    defer in_lock.unlock();
    return default_file_reader.vtable.stream(io_reader, w, limit);
}

fn stdinDiscard(io_reader: *std.Io.Reader, limit: std.Io.Limit) std.Io.Reader.Error!usize {
    in_lock.lock();
    defer in_lock.unlock();
    return default_file_reader.vtable.discard(io_reader, limit);
}

var stdin: std.fs.File.Reader = .{
    .interface = .{
        .vtable = &.{
            .stream = stdinStream,
            .discard = stdinDiscard,
        },
        .buffer = &.{},
        .seek = 0,
        .end = 0,
    },
    .file = undefined,
    .mode = .streaming,
};
var stdout: std.fs.File.Writer = .{
    .interface = std.fs.File.Writer.initInterface(&.{}),
    .file = undefined,
    .mode = .streaming,
};
var stderr: std.fs.File.Writer = .{
    .interface = std.fs.File.Writer.initInterface(&.{}),
    .file = undefined,
    .mode = .streaming,
};

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

    last_stderr_handle = windows.kernel32.GetStdHandle(windows.STD_ERROR_HANDLE);
    _ = windows_extra.SetStdHandle(windows.STD_ERROR_HANDLE, stdout_handle);

    stdin.file = .{ .handle = stdin_handle };
    stdout.file = .{ .handle = stdout_handle };
    stderr.file = .{ .handle = stdout_handle };

    initialized.store(true, .seq_cst);
}

pub fn deinit() void {
    if (!initialized.load(.seq_cst)) return;
    out_lock.lock();
    defer out_lock.unlock();
    in_lock.lock();
    defer in_lock.unlock();

    stdin.file.close();
    stdout.file.close();
    // stderr is the same as stdout in this case

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

pub fn stdinReader(buffer: []u8) ?*std.Io.Reader {
    if (!initialized.load(.seq_cst)) return null;
    {
        in_lock.lock();
        defer in_lock.unlock();
        stdin.interface.buffer = buffer;
    }
    return &stdin.interface;
}

pub fn println(comptime format: []const u8, args: anytype) void {
    if (!initialized.load(.seq_cst)) {
        std.debug.print(format ++ "\n", args);
        return;
    }
    out_lock.lock();
    defer out_lock.unlock();

    var buffer: [64]u8 = undefined;
    stdout.interface.buffer = &buffer;
    nosuspend stdout.interface.print(format ++ "\n", args) catch return;
    stdout.interface.flush() catch {};
}

pub fn eprintln(comptime format: []const u8, args: anytype) void {
    if (!initialized.load(.seq_cst)) {
        std.debug.print(format ++ "\n", args);
        return;
    }
    out_lock.lock();
    defer out_lock.unlock();

    var buffer: [64]u8 = undefined;
    stderr.interface.buffer = &buffer;
    nosuspend stderr.interface.print(format ++ "\n", args) catch return;
    stderr.interface.flush() catch {};
}
