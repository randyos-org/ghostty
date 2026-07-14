//! `std.process.ArgIteratorGeneral` was removed with no replacement. It was
//! used in two places (`config/command.zig` for parsing a `command = "..."`
//! shell string, and `benchmark/cli.zig` for synthetic test args) as a
//! "best effort" shell-like tokenizer -- not a real shell, just whitespace
//! splitting with basic quote/escape handling. This reimplements that same
//! best-effort behavior locally.
const std = @import("std");
const Allocator = std.mem.Allocator;

/// Tokenizes `input` into words, eagerly, respecting single/double quotes
/// (stripped from the result) and backslash escapes outside of single
/// quotes. All returned arguments are owned by this iterator and freed
/// together on `deinit`.
pub const ArgIterator = struct {
    alloc: Allocator,
    args: [][:0]const u8,
    index: usize = 0,

    pub fn init(alloc: Allocator, input: []const u8) Allocator.Error!ArgIterator {
        var args: std.ArrayList([:0]const u8) = .empty;
        errdefer {
            for (args.items) |arg| alloc.free(arg);
            args.deinit(alloc);
        }

        var buf: std.ArrayList(u8) = .empty;
        defer buf.deinit(alloc);

        var quote: ?u8 = null;
        var in_word = false;
        var i: usize = 0;
        while (i < input.len) : (i += 1) {
            const c = input[i];

            if (quote) |q| {
                if (c == q) {
                    quote = null;
                    continue;
                }
                if (q == '"' and c == '\\' and i + 1 < input.len) {
                    const escaped = input[i + 1];
                    if (escaped == '"' or escaped == '\\') {
                        try buf.append(alloc, escaped);
                        i += 1;
                        continue;
                    }
                }
                try buf.append(alloc, c);
                continue;
            }

            switch (c) {
                ' ', '\t', '\n', '\r' => {
                    if (in_word) {
                        try args.append(alloc, try buf.toOwnedSliceSentinel(alloc, 0));
                        in_word = false;
                    }
                },
                '\'', '"' => {
                    quote = c;
                    in_word = true;
                },
                '\\' => {
                    if (i + 1 < input.len) {
                        i += 1;
                        try buf.append(alloc, input[i]);
                        in_word = true;
                    }
                },
                else => {
                    try buf.append(alloc, c);
                    in_word = true;
                },
            }
        }
        if (in_word) try args.append(alloc, try buf.toOwnedSliceSentinel(alloc, 0));

        return .{ .alloc = alloc, .args = try args.toOwnedSlice(alloc) };
    }

    pub fn next(self: *ArgIterator) ?[:0]const u8 {
        if (self.index >= self.args.len) return null;
        defer self.index += 1;
        return self.args[self.index];
    }

    pub fn deinit(self: *ArgIterator) void {
        for (self.args) |arg| self.alloc.free(arg);
        self.alloc.free(self.args);
    }
};

test "basic" {
    const testing = std.testing;
    var iter = try ArgIterator.init(testing.allocator, "foo bar baz");
    defer iter.deinit();
    try testing.expectEqualStrings("foo", iter.next().?);
    try testing.expectEqualStrings("bar", iter.next().?);
    try testing.expectEqualStrings("baz", iter.next().?);
    try testing.expect(iter.next() == null);
}

test "quotes" {
    const testing = std.testing;
    var iter = try ArgIterator.init(testing.allocator, "foo 'bar baz' \"qux\"");
    defer iter.deinit();
    try testing.expectEqualStrings("foo", iter.next().?);
    try testing.expectEqualStrings("bar baz", iter.next().?);
    try testing.expectEqualStrings("qux", iter.next().?);
    try testing.expect(iter.next() == null);
}
