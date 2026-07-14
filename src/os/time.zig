const std = @import("std");

/// Returns the current Unix time in seconds, replacing the removed
/// `std.time.timestamp()`.
pub fn unixTimestamp(io: std.Io) i64 {
    const ns = std.Io.Clock.real.now(io).nanoseconds;
    return @intCast(@divTrunc(ns, std.time.ns_per_s));
}
