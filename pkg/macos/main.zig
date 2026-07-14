const builtin = @import("builtin");

pub const carbon = @import("carbon.zig");
pub const foundation = @import("foundation.zig");
pub const animation = @import("animation.zig");
pub const dispatch = @import("dispatch.zig");
pub const graphics = @import("graphics.zig");
pub const os = @import("os.zig");
pub const text = @import("text.zig");
pub const video = @import("video.zig");
pub const iosurface = @import("iosurface.zig");

// All of our C imports consolidated into one place. We used to
// import them one by one in each package but Zig 0.14 has some
// kind of issue with that I wasn't able to minimize.
pub const c = if (builtin.os.tag.isDarwin()) @import("c") else struct {};

test {
    @import("std").testing.refAllDecls(@This());
}
