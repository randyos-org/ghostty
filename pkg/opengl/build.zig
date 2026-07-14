const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path("../../vendor/glad/include/glad/gl.h"),
        .target = target,
        .optimize = optimize,
    });
    translate_c.addIncludePath(b.path("../../vendor/glad/include"));

    const module = b.addModule("opengl", .{
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.addIncludePath(b.path("../../vendor/glad/include"));

    // module.addImport("c", translate_c.createModule());
    // TODO(zig-0.17.0-dev.203 translate-c + watch hang): `zig build
    // -fincremental --watch` deadlocks whenever the build graph contains a
    // `TranslateC` step on this exact snapshot (translate-c's `make()`
    // doesn't complete its `--listen=-` handshake with the watch build
    // server). We're intentionally pinned to dev.203 for ZLS compatibility,
    // so we work around it here instead of upgrading. `zig build` (without
    // --watch) still runs `translate_c` fine and was used once to produce
    // `ctmp/opengl/gl.zig` (gitignored, not committed -- this is a vendored
    // C header we don't expect to change). Once translate-c+watch is fixed
    // upstream (or we move off dev.203), delete ctmp/ and restore the line
    // below in place of the ctmp module.
    module.addImport("c", b.createModule(.{
        .root_source_file = b.path("../../ctmp/opengl/gl.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    }));
}
