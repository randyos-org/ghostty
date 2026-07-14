const std = @import("std");
const windows = std.os.windows;

// Export any constants or functions we need from the Windows API so
// we can just import one file.
pub const kernel32 = windows.kernel32;
pub const ntdll = windows.ntdll;
pub const unexpectedError = windows.unexpectedError;
pub const unexpectedStatus = windows.unexpectedStatus;
pub const GetLastError = windows.GetLastError;
pub const OpenFile = windows.OpenFile;
pub const CloseHandle = windows.CloseHandle;
pub const GetCurrentProcessId = windows.GetCurrentProcessId;

pub const HRESULT = c_long;
pub const DWORD = windows.DWORD;
pub const HANDLE = windows.HANDLE;
pub const INVALID_HANDLE_VALUE = windows.INVALID_HANDLE_VALUE;
pub const MAX_PATH = windows.MAX_PATH;
pub const PROCESS = windows.PROCESS;
pub const NTSTATUS = windows.NTSTATUS;
pub const LARGE_INTEGER = windows.LARGE_INTEGER;
pub const S_OK: HRESULT = 0;
pub const SECURITY_ATTRIBUTES = windows.SECURITY_ATTRIBUTES;
pub const STARTUPINFOW = windows.STARTUPINFOW;
pub const STARTF_USESTDHANDLES = windows.STARTF_USESTDHANDLES;
pub const FALSE = windows.BOOL.FALSE;
pub const TRUE = windows.BOOL.TRUE;

/// `exp` seems to have been used to collect things that were not previously
/// part of the Zig stdlib.
pub const exp = struct {
    pub const HPCON = windows.LPVOID;

    pub const CREATE_UNICODE_ENVIRONMENT = 0x00000400;
    pub const EXTENDED_STARTUPINFO_PRESENT = 0x00080000;
    pub const LPPROC_THREAD_ATTRIBUTE_LIST = ?*anyopaque;

    pub const STATUS_PENDING = 0x00000103;
    pub const STILL_ACTIVE = STATUS_PENDING;

    pub const STARTUPINFOEX = extern struct {
        StartupInfo: windows.STARTUPINFOW,
        lpAttributeList: LPPROC_THREAD_ATTRIBUTE_LIST,
    };

    pub const kernel32 = struct {
        // ConPTY (CreatePseudoConsole/ResizePseudoConsole/ClosePseudoConsole)
        // is conhost.exe-mediated with no NT-syscall backing, unlike the
        // file/pipe/process-I/O APIs elsewhere in this file that migrated to
        // ntdll. Confirmed absent from Zig's own .zig sources (std and the
        // compiler) as of master 160e1b229 (2026-07-07) -- it only shows up
        // in the bundled mingw-w64 C headers/import libs Zig ships for C
        // interop, not as a std.os.windows binding. Re-check upstream if
        // this ever needs revisiting.
        pub extern "kernel32" fn CreatePseudoConsole(
            size: windows.COORD,
            hInput: windows.HANDLE,
            hOutput: windows.HANDLE,
            dwFlags: windows.DWORD,
            phPC: *HPCON,
        ) callconv(.winapi) HRESULT;
        pub extern "kernel32" fn ResizePseudoConsole(hPC: HPCON, size: windows.COORD) callconv(.winapi) HRESULT;
        pub extern "kernel32" fn ClosePseudoConsole(hPC: HPCON) callconv(.winapi) void;
        pub extern "kernel32" fn InitializeProcThreadAttributeList(
            lpAttributeList: LPPROC_THREAD_ATTRIBUTE_LIST,
            dwAttributeCount: windows.DWORD,
            dwFlags: windows.DWORD,
            lpSize: *windows.SIZE_T,
        ) callconv(.winapi) windows.BOOL;
        pub extern "kernel32" fn UpdateProcThreadAttribute(
            lpAttributeList: LPPROC_THREAD_ATTRIBUTE_LIST,
            dwFlags: windows.DWORD,
            Attribute: windows.DWORD_PTR,
            lpValue: windows.PVOID,
            cbSize: windows.SIZE_T,
            lpPreviousValue: ?windows.PVOID,
            lpReturnSize: ?*windows.SIZE_T,
        ) callconv(.winapi) windows.BOOL;
        // Duplicated here because lpCommandLine is not marked optional in zig std
        pub extern "kernel32" fn CreateProcessW(
            lpApplicationName: ?windows.LPWSTR,
            lpCommandLine: ?windows.LPWSTR,
            lpProcessAttributes: ?*windows.SECURITY_ATTRIBUTES,
            lpThreadAttributes: ?*windows.SECURITY_ATTRIBUTES,
            bInheritHandles: windows.BOOL,
            dwCreationFlags: windows.DWORD,
            lpEnvironment: ?*anyopaque,
            lpCurrentDirectory: ?windows.LPWSTR,
            lpStartupInfo: *windows.STARTUPINFOW,
            lpProcessInformation: *PROCESS_INFORMATION,
        ) callconv(.winapi) windows.BOOL;
        /// https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-getcomputernamea
        pub extern "kernel32" fn GetComputerNameA(
            lpBuffer: windows.LPSTR,
            nSize: *windows.DWORD,
        ) callconv(.winapi) windows.BOOL;
        /// https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-gettemppathw
        pub extern "kernel32" fn GetTempPathW(
            nBufferLength: windows.DWORD,
            lpBuffer: windows.LPWSTR,
        ) callconv(.winapi) windows.DWORD;
    };

    pub const PROC_THREAD_ATTRIBUTE_NUMBER = 0x0000FFFF;
    pub const PROC_THREAD_ATTRIBUTE_THREAD = 0x00010000;
    pub const PROC_THREAD_ATTRIBUTE_INPUT = 0x00020000;
    pub const PROC_THREAD_ATTRIBUTE_ADDITIVE = 0x00040000;

    pub const ProcThreadAttributeNumber = enum(windows.DWORD) {
        ProcThreadAttributePseudoConsole = 22,
        _,
    };

    /// Corresponds to the ProcThreadAttributeValue define in WinBase.h
    pub fn ProcThreadAttributeValue(
        comptime attribute: ProcThreadAttributeNumber,
        comptime thread: bool,
        comptime input: bool,
        comptime additive: bool,
    ) windows.DWORD {
        return (@intFromEnum(attribute) & PROC_THREAD_ATTRIBUTE_NUMBER) |
            (if (thread) PROC_THREAD_ATTRIBUTE_THREAD else 0) |
            (if (input) PROC_THREAD_ATTRIBUTE_INPUT else 0) |
            (if (additive) PROC_THREAD_ATTRIBUTE_ADDITIVE else 0);
    }

    pub const PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE = ProcThreadAttributeValue(.ProcThreadAttributePseudoConsole, false, true, false);
};

/// `ObjectHandleFlagInformation`'s payload. Not declared in
/// `std.os.windows`.
const OBJECT_HANDLE_FLAG_INFORMATION = extern struct {
    Inherit: windows.BOOLEAN,
    ProtectFromClose: windows.BOOLEAN,
};

/// `std.os.windows.kernel32.SetHandleInformation` was removed with no
/// Win32-level replacement (kernel32 itself no longer implements it) and
/// `std.os.windows.ntdll` doesn't declare `NtSetInformationObject` either,
/// so it's hand-declared here. This is the NT-native call kernel32's own
/// implementation used internally.
const NtSetInformationObject = @extern(*const fn (
    Handle: windows.HANDLE,
    ObjectInformationClass: windows.OBJECT.INFORMATION_CLASS,
    ObjectInformation: *anyopaque,
    ObjectInformationLength: windows.ULONG,
) callconv(.winapi) windows.NTSTATUS, .{ .name = "NtSetInformationObject", .library_name = "ntdll" });

pub fn setHandleInheritable(handle: windows.HANDLE, inheritable: bool) !void {
    var info: OBJECT_HANDLE_FLAG_INFORMATION = .{
        .Inherit = @intFromBool(inheritable),
        .ProtectFromClose = 0,
    };
    switch (NtSetInformationObject(
        handle,
        .HandleFlag,
        &info,
        @sizeOf(OBJECT_HANDLE_FLAG_INFORMATION),
    )) {
        .SUCCESS => {},
        else => |status| return windows.unexpectedStatus(status),
    }
}

/// Options for `createPipe`. Mirrors the shape of std's own internal
/// `Io.Threaded.CreatePipeOptions`/`windowsCreatePipe`.
pub const CreatePipeOptions = struct {
    server: End = .{},
    client: End = .{},
    /// Whether the server end can read (i.e. the client can write).
    inbound: bool = false,
    /// Whether the server end can write (i.e. the client can read).
    outbound: bool = false,
    maximum_instances: windows.ULONG = 1,
    quota: windows.ULONG = 4096,
    /// Matches kernel32's own historical `CreatePipe` default: 60
    /// seconds, negative/relative, in 100ns units.
    default_timeout: windows.LARGE_INTEGER = -60 * std.time.ns_per_s / 100,

    pub const End = struct {
        inheritable: bool = false,
        mode: windows.FILE.MODE = .{ .IO = .SYNCHRONOUS_NONALERT },
    };
};

/// `std.os.windows.kernel32.CreatePipe`/`CreateNamedPipeW` were removed
/// with no Win32-level replacement (kernel32 itself no longer implements
/// them). This mirrors the NT-native technique std's own
/// `Io.Threaded.windowsCreatePipe` uses: a pipe is created via
/// `NtCreateNamedPipeFile`, then the other end is opened relative to it
/// via `NtOpenFile`. An "anonymous" pipe (no `server`/`client` options
/// given) is just this same pipe created with an empty relative object
/// name, so the object is never given a name anything else could open.
pub fn createPipe(options: CreatePipeOptions) ![2]windows.HANDLE {
    const device = try namedPipeDevice();
    defer _ = CloseHandle(device);

    var status_block: windows.IO_STATUS_BLOCK = undefined;

    var server_handle: windows.HANDLE = undefined;
    switch (windows.ntdll.NtCreateNamedPipeFile(
        &server_handle,
        .{
            .SPECIFIC = .{ .FILE_PIPE = .{
                .READ_DATA = options.inbound,
                .WRITE_DATA = options.outbound,
                .WRITE_ATTRIBUTES = true,
            } },
            .STANDARD = .{ .SYNCHRONIZE = true },
        },
        &.{
            .RootDirectory = device,
            .Attributes = .{ .INHERIT = options.server.inheritable },
        },
        &status_block,
        .{ .READ = true, .WRITE = true },
        .CREATE,
        options.server.mode,
        .{ .TYPE = .BYTE_STREAM },
        .{ .MODE = .BYTE_STREAM },
        .{ .OPERATION = .QUEUE },
        options.maximum_instances,
        if (options.inbound) options.quota else 0,
        if (options.outbound) options.quota else 0,
        &options.default_timeout,
    )) {
        .SUCCESS => {},
        else => |status| return windows.unexpectedStatus(status),
    }
    errdefer _ = CloseHandle(server_handle);

    var client_handle: windows.HANDLE = undefined;
    switch (windows.ntdll.NtOpenFile(
        &client_handle,
        .{
            .SPECIFIC = .{ .FILE_PIPE = .{
                .READ_DATA = options.outbound,
                .WRITE_DATA = options.inbound,
                .WRITE_ATTRIBUTES = true,
            } },
            .STANDARD = .{ .SYNCHRONIZE = true },
        },
        &.{
            .RootDirectory = server_handle,
            .Attributes = .{ .INHERIT = options.client.inheritable },
        },
        &status_block,
        .{ .READ = true, .WRITE = true },
        options.client.mode,
    )) {
        .SUCCESS => {},
        else => |status| return windows.unexpectedStatus(status),
    }

    return .{ server_handle, client_handle };
}

fn namedPipeDevice() !windows.HANDLE {
    var handle: windows.HANDLE = undefined;
    var status_block: windows.IO_STATUS_BLOCK = undefined;
    switch (windows.ntdll.NtOpenFile(
        &handle,
        .{ .STANDARD = .{ .SYNCHRONIZE = true } },
        &.{ .ObjectName = @constCast(&windows.UNICODE_STRING.init(
            &.{ '\\', 'D', 'e', 'v', 'i', 'c', 'e', '\\', 'N', 'a', 'm', 'e', 'd', 'P', 'i', 'p', 'e', '\\' },
        )) },
        &status_block,
        .VALID_FLAGS,
        .{ .IO = .SYNCHRONOUS_NONALERT },
    )) {
        .SUCCESS => return handle,
        else => |status| return windows.unexpectedStatus(status),
    }
}

/// `std.os.windows.kernel32.CancelIoEx` was removed with no Win32-level
/// replacement. `NtCancelSynchronousIoFile` is the NT-native equivalent
/// for canceling a blocking (non-overlapped) I/O operation issued by
/// another thread: it identifies the target by that thread's own
/// handle rather than the file handle the operation was issued
/// against, since a synchronous read has no separate identifying token
/// (like an `OVERLAPPED`) the way an asynchronous one does.
pub fn cancelSynchronousIo(thread_handle: windows.HANDLE) !void {
    var status_block: windows.IO_STATUS_BLOCK = undefined;
    switch (windows.ntdll.NtCancelSynchronousIoFile(thread_handle, null, &status_block)) {
        .SUCCESS, .NOT_FOUND => {},
        else => |status| return windows.unexpectedStatus(status),
    }
}

/// `std.os.windows.kernel32.ReadFile` was removed; `NtReadFile` is the
/// NT-native replacement. Returns `error.Cancelled` if the read was
/// interrupted by `cancelSynchronousIo` from another thread.
pub fn readFile(handle: windows.HANDLE, buffer: []u8) !usize {
    var status_block: windows.IO_STATUS_BLOCK = undefined;
    switch (windows.ntdll.NtReadFile(
        handle,
        null,
        null,
        null,
        &status_block,
        @ptrCast(buffer.ptr),
        @intCast(buffer.len),
        null,
        null,
    )) {
        .SUCCESS => return @intCast(status_block.Information),
        .CANCELLED => return error.Cancelled,
        else => |status| return windows.unexpectedStatus(status),
    }
}

/// `std.os.windows.kernel32.PeekNamedPipe` was removed; the NT-native
/// replacement is querying `FilePipeLocalInformation`, which reports the
/// same "bytes available to read without blocking" count.
pub fn pipeBytesAvailable(handle: windows.HANDLE) !windows.ULONG {
    var info: windows.FILE.PIPE.LOCAL_INFORMATION = undefined;
    var status_block: windows.IO_STATUS_BLOCK = undefined;
    switch (windows.ntdll.NtQueryInformationFile(
        handle,
        &status_block,
        &info,
        @sizeOf(windows.FILE.PIPE.LOCAL_INFORMATION),
        .PipeLocal,
    )) {
        .SUCCESS => return info.ReadDataAvailable,
        else => |status| return windows.unexpectedStatus(status),
    }
}

/// `std.os.windows.kernel32.CreateFileW` was removed; `NtCreateFile` is
/// the NT-native replacement. Opens the NT-native null device (`NUL`'s
/// underlying object), used as a placeholder handle for stdin/stdout/
/// stderr streams that aren't otherwise redirected.
pub fn openNulDevice() !windows.HANDLE {
    var handle: windows.HANDLE = undefined;
    var status_block: windows.IO_STATUS_BLOCK = undefined;
    switch (windows.ntdll.NtCreateFile(
        &handle,
        .{
            .GENERIC = .{ .READ = true },
            .STANDARD = .{ .SYNCHRONIZE = true },
        },
        &.{ .ObjectName = @constCast(&windows.UNICODE_STRING.init(
            &.{ '\\', 'D', 'e', 'v', 'i', 'c', 'e', '\\', 'N', 'u', 'l', 'l' },
        )) },
        &status_block,
        null,
        .{},
        .{ .READ = true },
        .OPEN,
        .{ .IO = .SYNCHRONOUS_NONALERT },
        null,
        0,
    )) {
        .SUCCESS => return handle,
        else => |status| return windows.unexpectedStatus(status),
    }
}

// The declarations below were present in std.os.windows before Zig's
// deliberate migration toward NT-native APIs (ntdll) instead of thin
// Win32/kernel32 wrappers; see
// https://codeberg.org/ziglang/zig/issues/31131 ("Windows: Prefer the
// Native API over Win32") for the rationale. Where no typed replacement exists,
// the raw Win32 value is used as-is.

pub const PROCESS_INFORMATION = extern struct {
    hProcess: windows.HANDLE,
    hThread: windows.HANDLE,
    dwProcessId: DWORD,
    dwThreadId: DWORD,
};
