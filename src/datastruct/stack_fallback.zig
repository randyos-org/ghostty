//! `std.heap.stackFallback`/`StackFallbackAllocator` were
//! removed from std entirely (not renamed). This is a
//! minimal re-implementation matching the classic API and behavior: an
//! allocator that services allocations from a fixed stack buffer first,
//! falling back to a parent allocator once that buffer is exhausted.
const std = @import("std");
const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;

pub fn StackFallbackAllocator(comptime size: usize) type {
    return struct {
        const Self = @This();

        buffer: [size]u8 = undefined,
        fallback_allocator: Allocator,
        fixed_buffer_allocator: FixedBufferAllocator = undefined,

        pub fn get(self: *Self) Allocator {
            self.fixed_buffer_allocator = .init(&self.buffer);
            return .{
                .ptr = self,
                .vtable = &.{
                    .alloc = alloc,
                    .resize = resize,
                    .remap = remap,
                    .free = free,
                },
            };
        }

        fn alloc(ctx: *anyopaque, len: usize, alignment: Alignment, ret_addr: usize) ?[*]u8 {
            const self: *Self = @ptrCast(@alignCast(ctx));
            return FixedBufferAllocator.alloc(&self.fixed_buffer_allocator, len, alignment, ret_addr) orelse
                return self.fallback_allocator.vtable.alloc(self.fallback_allocator.ptr, len, alignment, ret_addr);
        }

        fn resize(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) bool {
            const self: *Self = @ptrCast(@alignCast(ctx));
            if (self.fixed_buffer_allocator.ownsPtr(memory.ptr)) {
                return FixedBufferAllocator.resize(&self.fixed_buffer_allocator, memory, alignment, new_len, ret_addr);
            }
            return self.fallback_allocator.vtable.resize(self.fallback_allocator.ptr, memory, alignment, new_len, ret_addr);
        }

        fn remap(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
            const self: *Self = @ptrCast(@alignCast(ctx));
            if (self.fixed_buffer_allocator.ownsPtr(memory.ptr)) {
                return FixedBufferAllocator.remap(&self.fixed_buffer_allocator, memory, alignment, new_len, ret_addr);
            }
            return self.fallback_allocator.vtable.remap(self.fallback_allocator.ptr, memory, alignment, new_len, ret_addr);
        }

        fn free(ctx: *anyopaque, memory: []u8, alignment: Alignment, ret_addr: usize) void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            if (self.fixed_buffer_allocator.ownsPtr(memory.ptr)) {
                return FixedBufferAllocator.free(&self.fixed_buffer_allocator, memory, alignment, ret_addr);
            }
            return self.fallback_allocator.vtable.free(self.fallback_allocator.ptr, memory, alignment, ret_addr);
        }
    };
}

pub fn stackFallback(comptime size: usize, fallback_allocator: Allocator) StackFallbackAllocator(size) {
    return .{ .fallback_allocator = fallback_allocator };
}

test "stackFallback basic" {
    const testing = std.testing;
    var stack = stackFallback(64, testing.allocator);
    const alloc = stack.get();

    const small = try alloc.alloc(u8, 8);
    defer alloc.free(small);
    try testing.expectEqual(@as(usize, 8), small.len);

    // Exceeds the stack buffer, should fall back to the parent allocator.
    const big = try alloc.alloc(u8, 4096);
    defer alloc.free(big);
    try testing.expectEqual(@as(usize, 4096), big.len);
}
