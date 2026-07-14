const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const objc = @import("objc");
const macos = @import("macos");

/// Overrides the argv that `iterator()` yields, taking priority over
/// whatever the OS reports. `ghostty_init(argc, argv)` (see main_c.zig) is a
/// public C API: embedding host applications are explicitly allowed to pass
/// an argv that differs from (or is unrelated to) the host process's own
/// real command line, and we must parse *that*, not requery the OS out from
/// under them. This mirrors the old `std.os.argv = argv[0..argc]` override
/// mechanism that `std.process.ArgIterator` used to read on POSIX (removed
/// along with `std.os.argv` itself), just made explicit and cross-platform.
pub var override: ?[]const [*:0]const u8 = null;

/// Returns an iterator over the command line arguments. This may or may
/// not allocate depending on the platform.
///
/// For Zig-aware readers: this is the same as std.process.argsWithAllocator
/// but handles macOS using NSProcessInfo instead of libc argc/argv, and
/// respects `override` above if it's set.
pub fn iterator(allocator: Allocator) ArgIterator.InitError!ArgIterator {
    if (override) |argv| return .{ .override = .{ .argv = argv } };
    return .{ .real = try .initWithAllocator(allocator) };
}

/// Duck-typed to std.process.Args.Iterator
pub const ArgIterator = union(enum) {
    override: IteratorOverride,
    real: RealArgIterator,

    pub const InitError = RealArgIterator.InitError;

    pub fn deinit(self: *ArgIterator) void {
        switch (self.*) {
            inline else => |*v| v.deinit(),
        }
    }

    pub fn next(self: *ArgIterator) ?[:0]const u8 {
        return switch (self.*) {
            inline else => |*v| v.next(),
        };
    }

    pub fn skip(self: *ArgIterator) bool {
        return switch (self.*) {
            inline else => |*v| v.skip(),
        };
    }
};

/// Iterates over an explicitly provided argv, e.g. from `ghostty_init`.
const IteratorOverride = struct {
    argv: []const [*:0]const u8,
    index: usize = 0,

    pub fn deinit(_: *IteratorOverride) void {}

    pub fn next(self: *IteratorOverride) ?[:0]const u8 {
        if (self.index >= self.argv.len) return null;
        defer self.index += 1;
        return std.mem.sliceTo(self.argv[self.index], 0);
    }

    pub fn skip(self: *IteratorOverride) bool {
        if (self.index >= self.argv.len) return false;
        self.index += 1;
        return true;
    }
};

const RealArgIterator = switch (builtin.os.tag) {
    .macos => IteratorMacOS,
    .windows => IteratorWindows,
    else => IteratorPosix,
};

/// std.process.Args.Iterator now needs a `std.process.Args` (i.e. an OS
/// argv/command-line vector), which used to be supplied for free via the
/// now-removed `std.os.argv` global. `main()`/`ghostty_init()` don't (yet)
/// thread a `std.process.Init` through to here, so this reads the live
/// command line directly from the OS instead.
const IteratorWindows = struct {
    inner: std.process.Args.Iterator,

    pub const InitError = std.process.Args.Iterator.InitError;

    pub fn initWithAllocator(alloc: Allocator) InitError!IteratorWindows {
        const vector = std.os.windows.peb().ProcessParameters.CommandLine.slice();
        return .{ .inner = try .initAllocator(.{ .vector = vector }, alloc) };
    }

    pub fn deinit(self: *IteratorWindows) void {
        self.inner.deinit();
    }

    pub fn next(self: *IteratorWindows) ?[:0]const u8 {
        return self.inner.next();
    }

    pub fn skip(self: *IteratorWindows) bool {
        return self.inner.skip();
    }
};

/// See `IteratorWindows`. There's no portable ambient way to recover argv
/// after startup on POSIX without a libc-specific extension (unlike
/// `environ`, which libc does expose globally -- see `env.zig`), so this
/// is a stub until `main()` threads a real `std.process.Init` (and its
/// `args`) down to callers.
const IteratorPosix = struct {
    done: bool = false,

    pub const InitError = error{};

    pub fn initWithAllocator(_: Allocator) InitError!IteratorPosix {
        return .{};
    }

    pub fn deinit(_: *IteratorPosix) void {}

    pub fn next(self: *IteratorPosix) ?[:0]const u8 {
        if (self.done) return null;
        self.done = true;
        return "";
    }

    pub fn skip(self: *IteratorPosix) bool {
        if (self.done) return false;
        self.done = true;
        return true;
    }
};

/// This is an ArgIterator (duck-typed for std.process.ArgIterator) for
/// NSApplicationMain-based applications on macOS. It uses NSProcessInfo to
/// get the command line arguments since libc argc/argv pointers are not
/// valid.
///
/// I believe this should work for all macOS applications even if
/// NSApplicationMain is not used, but I haven't tested that so I'm not
/// sure. If/when libghostty is ever used outside of NSApplicationMain
/// then we can revisit this.
const IteratorMacOS = struct {
    alloc: Allocator,
    index: usize,
    count: usize,
    buf: [:0]u8,
    args: objc.Object,

    pub const InitError = Allocator.Error;

    pub fn initWithAllocator(alloc: Allocator) InitError!IteratorMacOS {
        const NSProcessInfo = objc.getClass("NSProcessInfo").?;
        const info = NSProcessInfo.msgSend(objc.Object, objc.sel("processInfo"), .{});
        const args = info.getProperty(objc.Object, "arguments");
        errdefer args.release();

        // Determine our maximum length so we can allocate the buffer to
        // fit all values.
        var max: usize = 0;
        const count: usize = @intCast(args.getProperty(c_ulong, "count"));
        for (0..count) |i| {
            const nsstr = args.msgSend(
                objc.Object,
                objc.sel("objectAtIndex:"),
                .{@as(c_ulong, @intCast(i))},
            );

            const maxlen: usize = @intCast(nsstr.msgSend(
                c_ulong,
                objc.sel("maximumLengthOfBytesUsingEncoding:"),
                .{@as(c_ulong, 4)},
            ));

            max = @max(max, maxlen);
        }

        // Allocate our buffer. We add 1 for the null terminator.
        const buf = try alloc.allocSentinel(u8, max, 0);
        errdefer alloc.free(buf);

        return .{
            .alloc = alloc,
            .index = 0,
            .count = count,
            .buf = buf,
            .args = args,
        };
    }

    pub fn deinit(self: *IteratorMacOS) void {
        self.alloc.free(self.buf);

        // Note: we don't release self.args because it is a pointer copy
        // not a retained object.
    }

    pub fn next(self: *IteratorMacOS) ?[:0]const u8 {
        if (self.index == self.count) return null;

        // NSString. No release because not a copy.
        const nsstr = self.args.msgSend(
            objc.Object,
            objc.sel("objectAtIndex:"),
            .{@as(c_ulong, @intCast(self.index))},
        );
        self.index += 1;

        // Convert to string using getCString. Our buffer should always
        // be big enough because we precomputed the maximum length.
        if (!nsstr.msgSend(
            bool,
            objc.sel("getCString:maxLength:encoding:"),
            .{
                @as([*]u8, @ptrCast(self.buf.ptr)),
                @as(c_ulong, @intCast(self.buf.len)),
                @as(c_ulong, 4), // NSUTF8StringEncoding
            },
        )) {
            // This should never happen... if it does, we just return empty.
            return "";
        }

        return std.mem.sliceTo(self.buf, 0);
    }

    pub fn skip(self: *IteratorMacOS) bool {
        if (self.index == self.count) return false;
        self.index += 1;
        return true;
    }
};

test "args" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var iter = try iterator(alloc);
    defer iter.deinit();
    try testing.expect(iter.next().?.len > 0);
}
