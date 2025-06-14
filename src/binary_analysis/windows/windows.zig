const std = @import("std");
const windows = std.os.windows;
const windows_extra = @import("windows_extra");

pub const x86_64 = @import("x86_64/x86_64.zig");

pub inline fn clearInstructionCache(addr: []u8) void {
    const address_ptr: windows.LPVOID = @ptrCast(addr.ptr);
    _ = windows_extra.FlushInstructionCache(windows.GetCurrentProcess(), address_ptr, addr.len);
}

pub fn copyToAsExecutable(to: usize, code: []const u8) !void {
    @setRuntimeSafety(false);
    if (code.len == 0) return;

    var old_protect: windows.DWORD = 0;
    const address_ptr: windows.LPVOID = @ptrFromInt(to);
    try windows.VirtualProtect(address_ptr, code.len, windows.PAGE_EXECUTE_READWRITE, &old_protect);

    const bytes: []u8 = @as([*]u8, @ptrCast(address_ptr))[0..code.len];
    @memcpy(bytes, code);

    var dummy: windows.DWORD = 0;
    try windows.VirtualProtect(address_ptr, code.len, old_protect, &dummy);

    clearInstructionCache(bytes);
}

pub const ModuleInfo = struct {
    name: []const u8,
    start: usize,
    end: usize,

    pub fn deinit(self: ModuleInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
    }
};

pub fn getModuleInfo(allocator: std.mem.Allocator, module_name: []const u8) !?ModuleInfo {
    const module_name_w = std.unicode.utf8ToUtf16LeAllocZ(allocator, module_name) catch return null;
    defer allocator.free(module_name_w);

    const module = windows.kernel32.GetModuleHandleW(module_name_w) orelse return null;

    var mod_info: windows.MODULEINFO = undefined;
    if (windows_extra.GetModuleInformation(windows.GetCurrentProcess(), module, &mod_info, @sizeOf(windows.MODULEINFO)) == windows.FALSE) return null;
    return .{
        .name = try allocator.dupe(u8, module_name),
        .start = @intFromPtr(module),
        .end = @intFromPtr(module) + mod_info.SizeOfImage,
    };
}
