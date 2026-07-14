const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const build_config = @import("../build_config.zig");
const apprt = @import("../apprt.zig");
const global_state = &@import("../global.zig").state;

const log = std.log.scoped(.@"os-open");

/// Open a URL in the default handling application.
///
/// Any output on stderr is logged as a warning in the application logs.
/// Output on stdout is ignored.
///
/// This function is purposely simple for the sake of providing some portable
/// way to open URLs. If you are implementing an apprt for Ghostty, you should
/// consider doing something special-cased for your platform.
pub fn open(
    alloc: Allocator,
    kind: apprt.action.OpenUrl.Kind,
    url: []const u8,
) !void {
    const argv: []const []const u8 = switch (builtin.os.tag) {
        .linux, .freebsd => &.{ "xdg-open", url },

        .windows => &.{ "rundll32", "url.dll,FileProtocolHandler", url },

        .macos => switch (kind) {
            .text => &.{ "open", "-t", url },
            .html, .unknown => &.{ "open", url },
        },

        .ios => return error.Unimplemented,
        else => @compileError("unsupported OS"),
    };

    // In the snap on Linux the launcher exports LD_LIBRARY_PATH pointing at
    // the snap's bundled libraries. Leaking this into child process can can be
    // problematic, so let's drop it from the env
    var snap_env: std.process.Environ.Map = if (comptime build_config.snap) blk: {
        var env = try std.process.Environ.createMap(.{ .block = .global }, alloc);
        _ = env.orderedRemove("LD_LIBRARY_PATH");
        break :blk env;
    } else undefined;
    defer if (comptime build_config.snap) snap_env.deinit();

    const exe = try std.process.spawn(global_state.io, .{
        .argv = argv,
        // Ignore anything from stdout.
        .stdout = .ignore,
        // Pipe stderr so we can log the stderr from the command.
        .stderr = .pipe,
        .environ_map = if (comptime build_config.snap) &snap_env else null,
    });

    // Create a thread that handles collecting output and reaping the process.
    // This is done in a separate thread because SOME open implementations block
    // and some do not. It's easier to just spawn a thread to handle this so
    // that we never block.
    const thread = try std.Thread.spawn(.{}, openThread, .{exe});
    thread.detach();
}

fn openThread(exe_: std.process.Child) void {
    // Copy the exe so it is non-const. This is necessary because wait()
    // requires a mutable reference and we can't have one as a thread
    // param.
    var exe = exe_;
    if (exe.stderr) |stderr| {
        var buffer: [256]u8 = undefined;
        var stream = stderr.readerStreaming(global_state.io, &buffer);
        const reader = &stream.interface;
        while (true) {
            const line = reader.takeDelimiterExclusive('\n') catch |outer| switch (outer) {
                error.EndOfStream => break,
                error.ReadFailed => break,
                error.StreamTooLong => reader.take(buffer.len) catch |inner| switch (inner) {
                    error.ReadFailed => break,
                    error.EndOfStream => break,
                },
            };
            log.warn("open stderr={s}", .{line});
        }
    }
    _ = exe.wait(global_state.io) catch {};
}
