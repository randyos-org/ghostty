//! minimal re-implementation of the classic `std.SegmentedList`,
//! which was removed from Zig's standard library entirely (not renamed).
//! Elements live in fixed-size segments that are heap
//! allocated as needed; existing segments are never moved or reallocated
//! (only new ones appended), so pointers returned by `at()` remain valid
//! for the datastructure's lifetime, unlike `ArrayList`, which
//! reallocates and invalidates pointers on growth. That stability
//! guarantee is load-bearing for both callers (`SegmentedPool` holds
//! pointers to in-flight async I/O requests; `font/Collection.zig` hands
//! out stable font-face pointers), so this can't just be swapped for
//! `ArrayListUnmanaged` the way lower-stakes call sites (e.g. the OSC
//! color-operation list) were.
//!
//! Only implements the subset of the real `std.SegmentedList` API this
//! repo actually uses: `len`/`count()`, `at()`, `growCapacity()`,
//! `append()`, `constIterator()`, `deinit()`. `prealloc` elements live
//! inline in the struct itself (zero heap allocations), matching the
//! original's optimization that lets a `SegmentedList` be default- or
//! statically-initialized with `prealloc` valid slots and no allocator
//! call. `SegmentedPool` relies on this for its own zero-arg struct
//! field defaults.
const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn SegmentedList(comptime T: type, comptime prealloc: usize) type {
    // Chunk size for segments allocated beyond the inline `prealloc`
    // elements. Arbitrary; only affects allocation granularity, not
    // correctness. Must be nonzero to avoid division by zero below.
    const segment_size = @max(prealloc, 8);

    return struct {
        const Self = @This();
        const Segment = [segment_size]T;

        /// Number of logically-valid elements. Safe to set directly (as
        /// `SegmentedPool` does) to mark additional already-inline
        /// `prealloc` slots valid without going through `append`.
        len: usize = 0,
        first: [prealloc]T = undefined,
        rest: std.ArrayListUnmanaged(*Segment) = .empty,

        /// An empty list. Equivalent to `.{}` -- provided so call sites
        /// can use the same `.empty` convention as `ArrayListUnmanaged`.
        pub const empty: Self = .{};

        pub fn deinit(self: *Self, alloc: Allocator) void {
            for (self.rest.items) |seg| alloc.destroy(seg);
            self.rest.deinit(alloc);
            self.* = undefined;
        }

        pub fn at(self: *Self, i: usize) *T {
            if (i < prealloc) return &self.first[i];
            const rel = i - prealloc;
            return &self.rest.items[rel / segment_size][rel % segment_size];
        }

        pub fn count(self: *const Self) usize {
            return self.len;
        }

        /// Ensures storage for at least `new_capacity` elements exists.
        /// Does not change `len`.
        pub fn growCapacity(self: *Self, alloc: Allocator, new_capacity: usize) !void {
            if (new_capacity <= prealloc) return;
            const rel_capacity = new_capacity - prealloc;
            const needed = (rel_capacity + segment_size - 1) / segment_size;
            while (self.rest.items.len < needed) {
                const seg = try alloc.create(Segment);
                try self.rest.append(alloc, seg);
            }
        }

        pub fn append(self: *Self, alloc: Allocator, value: T) !void {
            try self.growCapacity(alloc, self.len + 1);
            self.at(self.len).* = value;
            self.len += 1;
        }

        /// Grows the list by one and returns a pointer to the
        /// (uninitialized) new slot for the caller to fill in.
        pub fn addOne(self: *Self, alloc: Allocator) !*T {
            try self.growCapacity(alloc, self.len + 1);
            const ptr = self.at(self.len);
            self.len += 1;
            return ptr;
        }

        pub const Iterator = struct {
            list: *Self,
            index: usize,

            pub fn next(it: *Iterator) ?*T {
                if (it.index >= it.list.len) return null;
                defer it.index += 1;
                return it.list.at(it.index);
            }
        };

        pub fn constIterator(self: *const Self, start: usize) Iterator {
            return .{ .list = @constCast(self), .index = start };
        }

        pub fn iterator(self: *Self, start: usize) Iterator {
            return .{ .list = self, .index = start };
        }
    };
}

test "SegmentedList basic" {
    const testing = std.testing;
    var list: SegmentedList(u8, 2) = .{};
    defer list.deinit(testing.allocator);

    try list.append(testing.allocator, 1);
    try list.append(testing.allocator, 2);
    try list.append(testing.allocator, 3);

    try testing.expectEqual(@as(usize, 3), list.count());
    try testing.expectEqual(@as(u8, 1), list.at(0).*);
    try testing.expectEqual(@as(u8, 2), list.at(1).*);
    try testing.expectEqual(@as(u8, 3), list.at(2).*);

    var it = list.constIterator(0);
    var sum: usize = 0;
    while (it.next()) |v| sum += v.*;
    try testing.expectEqual(@as(usize, 6), sum);
}

test "SegmentedList prealloc default-init with no allocator" {
    var list: SegmentedList(u8, 4) = .{ .len = 4 };
    defer list.* = undefined;

    for (0..4) |i| list.at(i).* = @intCast(i);
    for (0..4) |i| try std.testing.expectEqual(@as(u8, @intCast(i)), list.at(i).*);
}
