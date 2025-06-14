const std = @import("std");
const windows = std.os.windows;

const ba = @import("binary_analysis");

const WinConsole = @import("WinConsole.zig");
const g_allocator = std.heap.c_allocator;

const Errors = error{
    HookAddressNotFound,
    HookFailed,
    HookAlreadyExists,
    HookNotFound,
};

var detour: ?ba.Detour = null;

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

pub fn init() !void {
    detour = try ba.Detour.init(std.heap.c_allocator);

    // Auto-Generated!!!
    //try @import("hooks/CopyRaceVehicleConfig.zig").init(&detour.?);

    // Auto-Generated!!!
    try @import("hooks/DoSomething.zig").init(&detour.?);
}

pub fn deinit() void {
    // Auto-Generated!!!
    @import("hooks/DoSomething.zig").deinit();
    var detour_ctx = detour orelse return;
    detour_ctx.deinit();
    detour = null;
}
