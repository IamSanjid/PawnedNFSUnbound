const std = @import("std");
const windows = std.os.windows;
pub const DLL_PROCESS_ATTACH: windows.DWORD = 1;
pub const DLL_PROCESS_DETACH: windows.DWORD = 0;
pub const DLL_THREAD_ATTACH: windows.DWORD = 2;
pub const DLL_THREAD_DETACH: windows.DWORD = 3;

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
