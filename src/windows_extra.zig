const builtin = @import("builtin");
const std = @import("std");
const windows = std.os.windows;

pub const DLL_PROCESS_ATTACH: windows.DWORD = 1;
pub const DLL_PROCESS_DETACH: windows.DWORD = 0;
pub const DLL_THREAD_ATTACH: windows.DWORD = 2;
pub const DLL_THREAD_DETACH: windows.DWORD = 3;

pub const THREAD_TERMINATE: windows.DWORD = 0x0001;
pub const THREAD_SUSPEND_RESUME: windows.DWORD = 0x0002;
pub const THREAD_GET_CONTEXT: windows.DWORD = 0x0008;
pub const THREAD_SET_CONTEXT: windows.DWORD = 0x0010;
pub const THREAD_SET_INFORMATION: windows.DWORD = 0x0020;
pub const THREAD_QUERY_INFORMATION: windows.DWORD = 0x0040;
pub const THREAD_SET_THREAD_TOKEN: windows.DWORD = 0x0080;
pub const THREAD_IMPERSONATE: windows.DWORD = 0x0100;
pub const THREAD_DIRECT_IMPERSONATION: windows.DWORD = 0x0200;
pub const THREAD_SET_LIMITED_INFORMATION: windows.DWORD = 0x0400;
pub const THREAD_QUERY_LIMITED_INFORMATION: windows.DWORD = 0x0800;
pub const THREAD_RESUME: windows.DWORD = 0x1000;

pub const GW_HWNDNEXT: windows.UINT = 2;
pub const GW_HWNDPREV: windows.UINT = 3;

pub const GWLP_WNDPROC: windows.INT = -4;
pub const GWLP_HINSTANCE: windows.INT = -6;
pub const GWLP_HWNDPARENT: windows.INT = -8;
pub const GWLP_ID: windows.INT = -12;
pub const GWL_STYLE: windows.INT = -16;
pub const GWL_EXSTYLE: windows.INT = -20;
pub const GWLP_USERDATA: windows.INT = -21;

pub const THREADENTRY32 = extern struct {
    dwSize: windows.DWORD,
    cntUsage: windows.DWORD,
    th32ThreadID: windows.DWORD,
    th32OwnerProcessID: windows.DWORD,
    tpBasePri: windows.LONG,
    tpDeltaPri: windows.LONG,
    dwFlags: windows.DWORD,
};

pub extern "kernel32" fn DisableThreadLibraryCalls(hLibModule: windows.HMODULE) callconv(.winapi) windows.BOOL;

pub extern "kernel32" fn AllocConsole() callconv(.winapi) windows.BOOL;
pub extern "kernel32" fn FreeConsole() callconv(.winapi) windows.BOOL;

pub extern "kernel32" fn SetStdHandle(nStdHandle: windows.DWORD, hHandle: windows.HANDLE) callconv(.winapi) windows.BOOL;

pub extern "kernel32" fn CreateFileA(
    lpFileName: windows.LPCSTR,
    dwDesiredAccess: windows.DWORD,
    dwShareMode: windows.DWORD,
    lpSecurityAttributes: ?*windows.SECURITY_ATTRIBUTES,
    dwCreationDisposition: windows.DWORD,
    dwFlagsAndAttributes: windows.DWORD,
    hTemplateFile: ?windows.HANDLE,
) callconv(.winapi) windows.HANDLE;

pub extern "kernel32" fn FreeLibraryAndExitThread(
    hLibModule: windows.HMODULE,
    dwExitCode: windows.DWORD,
) callconv(.winapi) windows.BOOL;

pub extern "kernel32" fn FlushInstructionCache(
    hProcess: windows.HANDLE,
    lpBaseAddress: windows.LPCVOID,
    dwSize: windows.SIZE_T,
) callconv(.winapi) windows.BOOL;

pub extern "kernel32" fn K32GetModuleInformation(
    hProcess: windows.HANDLE,
    hModule: windows.HMODULE,
    lpmodinfo: *windows.MODULEINFO,
    cb: windows.DWORD,
) callconv(.winapi) windows.BOOL;
pub const GetModuleInformation = K32GetModuleInformation;

pub extern "kernel32" fn Thread32First(hSnapshot: windows.HANDLE, lpte: *THREADENTRY32) callconv(.winapi) windows.BOOL;
pub extern "kernel32" fn Thread32Next(hSnapshot: windows.HANDLE, lpte: *THREADENTRY32) callconv(.winapi) windows.BOOL;

pub extern "kernel32" fn OpenThread(
    dwDesiredAccess: windows.DWORD,
    bInheritHandle: windows.BOOL,
    dwThreadId: windows.DWORD,
) callconv(.winapi) windows.HANDLE;
pub extern "kernel32" fn SuspendThread(hThread: windows.HANDLE) callconv(.winapi) windows.DWORD;
pub extern "kernel32" fn ResumeThread(hThread: windows.HANDLE) callconv(.winapi) windows.DWORD;

pub extern "user32" fn GetDesktopWindow() callconv(.winapi) windows.HWND;
pub extern "user32" fn GetTopWindow(hWnd: ?windows.HWND) callconv(.winapi) ?windows.HWND;
pub extern "user32" fn GetWindow(hWnd: windows.HWND, wCmd: windows.UINT) callconv(.winapi) ?windows.HWND;
pub const GetNextWindow = GetWindow;
pub extern "user32" fn GetParent(hWnd: windows.HWND) callconv(.winapi) ?windows.HWND;
pub extern "user32" fn GetWindowLong(hWnd: windows.HWND, nIndex: windows.INT) callconv(.winapi) windows.LONG;
pub extern "user32" fn GetWindowLongPtrW(hWnd: windows.HWND, nIndex: windows.INT) callconv(.winapi) windows.LONG_PTR;
pub const GetWindowLongPtr = if (builtin.target.ptrBitWidth() == 64) GetWindowLongPtrW else GetWindowLong;
pub extern "user32" fn GetClassNameW(
    hWnd: windows.HWND,
    lpClassName: ?windows.LPWSTR,
    nMaxCount: windows.INT,
) callconv(.winapi) windows.INT;
pub extern "user32" fn GetWindowThreadProcessId(hWnd: windows.HWND, lpdwProcessId: ?*windows.DWORD) callconv(.winapi) windows.DWORD;
pub extern "user32" fn IsWindowVisible(hWnd: windows.HWND) callconv(.winapi) windows.BOOL;
