const std = @import("std");

pub fn build(b: *std.Build) !void {
    const msvc_include_path = b.path("../../msvc");
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.addModule("wuffs", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const unit_tests = b.addTest(.{
        .name = "test",
        .root_module = module,
    });
    unit_tests.root_module.link_libc = true;

    var flags: std.ArrayList([]const u8) = .empty;
    defer flags.deinit(b.allocator);
    try flags.append(b.allocator, "-DWUFFS_IMPLEMENTATION");
    if (target.result.abi == .msvc) {
        try flags.append(b.allocator, "-fno-sanitize=undefined");
        try flags.append(b.allocator, "-fno-sanitize-trap=undefined");
    }
    inline for (@import("src/c.zig").defines) |key| {
        try flags.append(b.allocator, "-D" ++ key);
    }

    if (b.lazyDependency("wuffs", .{})) |wuffs_dep| {
        // shadow <stdint.h> with our own shim ahead of the
        // real MSVC one on the include search path.
        // see src/msvc_compat/stdint.h for why.
        // Only relevant on the MSVC ABI; GNU/other targets use Zig's own
        // bundled, standard-conforming libc headers and never see this.
        if (target.result.abi == .msvc) {
            module.addIncludePath(msvc_include_path);
        }
        module.addIncludePath(wuffs_dep.path("release/c"));
        module.addCSourceFile(.{
            .file = wuffs_dep.path("release/c/wuffs-v0.4.c"),
            .flags = flags.items,
        });
        // Generate the bindings with the baseline CPU model, not the
        // real target's.
        // Aro doesn't yet implement some newer Clang builtins
        // (__builtin_elementwise_fshl/fshr/clzg) that the bundled
        // AVX-512 intrinsic headers' declarations use.
        // Wuffs only includes those headers on this path when
        // __AVX2__ is defined; baseline x86_64 stops at SSE2,
        // so this keeps Aro away from headers it can't parse.
        // The bindings are unaffected -- wuffs's public API is
        // identical either way (CPU arch only changes private function
        // bodies).  Note that the *compiled* C object above still uses the real
        // target/CPU with full SIMD enabled.
        // var tc_query = target.query;
        // tc_query.cpu_model = .baseline;
        // const translate_c = b.addTranslateC(.{
        //     .root_source_file = wuffs_dep.path("release/c/wuffs-v0.4.c"),
        //     // .target = target,
        //     .target = b.resolveTargetQuery(tc_query),
        //     .optimize = optimize,
        // });
        // if (target.result.abi == .msvc) {
        //     translate_c.addIncludePath(msvc_include_path);
        // }
        // inline for (@import("src/c.zig").defines) |key| {
        //     translate_c.defineCMacro(key, "1");
        // }
        // module.addImport("wuffs.h", translate_c.createModule());
        // TODO: fix this later if addTranslateC is updated to support -mcpu

        // This must invoke `zig translate-c` directly rather than use
        // b.addTranslateC: Step.TranslateC only forwards the arch-os-abi
        // triple and silently drops the target's CPU model (it never
        // passes -mcpu), so Aro falls back to native CPU detection no
        // matter what `.target` it's given.
        //
        // TODO: drop the ctmp versions when we confirm the build is fixed
        // const translate_c = b.addSystemCommand(&.{
        //     b.graph.zig_exe,
        //     "translate-c",
        //     "-lc",
        //     "-target",
        //     try target.query.zigTriple(b.allocator),
        //     "-mcpu",
        //     "baseline",
        // });
        // if (target.result.abi == .msvc) {
        //     translate_c.addArg("-I");
        //     translate_c.addDirectoryArg(msvc_include_path);
        // }
        // inline for (@import("src/c.zig").defines) |key| {
        //     translate_c.addArgs(&.{ "-D", key ++ "=1" });
        // }
        // translate_c.addFileArg(wuffs_dep.path("release/c/wuffs-v0.4.c"));
        // module.addImport("wuffs.h", b.createModule(.{
        //     .root_source_file = translate_c.captureStdOut(.{
        //         .basename = "wuffs.zig",
        //     }),
        //     .target = target,
        //     .optimize = optimize,
        //     .link_libc = true,
        // }));
        module.addImport("wuffs.h", b.createModule(.{
            .root_source_file = b.path("../../ctmp/wuffs/wuffs.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }));
    }

    if (b.lazyDependency("pixels", .{})) |pixels_dep| {
        inline for (.{ "000000", "FFFFFF" }) |color| {
            inline for (.{ "gif", "jpg", "png", "ppm" }) |extension| {
                const filename = std.fmt.comptimePrint(
                    "1x1#{s}.{s}",
                    .{ color, extension },
                );
                unit_tests.root_module.addAnonymousImport(filename, .{
                    .root_source_file = pixels_dep.path(filename),
                });
            }
        }
    }

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
