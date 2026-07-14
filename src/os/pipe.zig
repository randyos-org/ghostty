const std = @import("std");
const builtin = @import("builtin");
const windows = @import("windows.zig");
const posix = std.posix;

/// pipe() that works on Windows and POSIX. For POSIX systems, this sets
/// CLOEXEC on the file descriptors.
pub fn pipe() ![2]posix.fd_t {
    switch (builtin.os.tag) {
        else => return try posix.pipe2(.{ .CLOEXEC = true }),
        .windows => {
            const ends = try windows.createPipe(.{ .inbound = true });
            return .{ ends[0], ends[1] };
        },
    }
}

/// Closes a raw fd/HANDLE. Replaces the removed `std.posix.close`.
pub fn close(io: std.Io, fd: posix.fd_t) void {
    (std.Io.File{ .handle = fd, .flags = .{ .nonblocking = false } }).close(io);
}
