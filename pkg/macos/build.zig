const std = @import("std");
const builtin = @import("builtin");
const apple_sdk = @import("apple_sdk");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.addModule("macos", .{
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .name = "macos",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
        .linkage = .static,
    });

    // Some cross-platform packages (e.g. harfbuzz, for its optional CoreText
    // backend) unconditionally depend on the "macos" module/artifact.
    // The actual Darwin-only code paths within it are only reachable
    // (and therefore only need to compile) when something on a Darwin target
    // uses them.
    if (target.result.os.tag.isDarwin()) {
        lib.root_module.addCSourceFile(.{
            .file = b.path("os/zig_macos.c"),
            .flags = &.{"-std=c99"},
        });
        lib.root_module.addCSourceFile(.{
            .file = b.path("text/ext.c"),
        });
        lib.root_module.linkFramework("CoreFoundation", .{});
        lib.root_module.linkFramework("CoreGraphics", .{});
        lib.root_module.linkFramework("CoreText", .{});
        lib.root_module.linkFramework("CoreVideo", .{});
        lib.root_module.linkFramework("QuartzCore", .{});
        lib.root_module.linkFramework("IOSurface", .{});
        if (target.result.os.tag == .macos) {
            lib.root_module.linkFramework("Carbon", .{});
            module.linkFramework("Carbon", .{});
        }

        module.linkFramework("CoreFoundation", .{});
        module.linkFramework("CoreGraphics", .{});
        module.linkFramework("CoreText", .{});
        module.linkFramework("CoreVideo", .{});
        module.linkFramework("QuartzCore", .{});
        module.linkFramework("IOSurface", .{});

        try apple_sdk.addPaths(b, lib);

        const header_wf = b.addWriteFiles();
        const header_contents = contents: {
            var buf: std.ArrayList(u8) = .empty;
            buf.appendSlice(b.allocator,
                \\#include <CoreFoundation/CoreFoundation.h>
                \\#include <CoreGraphics/CoreGraphics.h>
                \\#include <CoreText/CoreText.h>
                \\#include <CoreVideo/CoreVideo.h>
                \\#include <CoreVideo/CVPixelBuffer.h>
                \\#include <QuartzCore/CALayer.h>
                \\#include <IOSurface/IOSurfaceRef.h>
                \\#include <dispatch/dispatch.h>
                \\#include <os/log.h>
                \\#include <os/signpost.h>
                \\
            ) catch @panic("OOM");
            if (target.result.os.tag == .macos) {
                buf.appendSlice(b.allocator, "#include <Carbon/Carbon.h>\n") catch @panic("OOM");
            }
            break :contents buf.items;
        };
        const translate_c = b.addTranslateC(.{
            .root_source_file = header_wf.add("macos-zig.h", header_contents),
            .target = target,
            .optimize = optimize,
        });
        module.addImport("c", translate_c.createModule());
    }
    b.installArtifact(lib);

    {
        const test_exe = b.addTest(.{
            .name = "test",
            .root_module = b.createModule(.{
                .root_source_file = b.path("main.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        if (target.result.os.tag.isDarwin()) {
            try apple_sdk.addPaths(b, test_exe);
        }
        test_exe.root_module.linkLibrary(lib);

        var it = module.import_table.iterator();
        while (it.next()) |entry| {
            test_exe.root_module.addImport(
                entry.key_ptr.*,
                entry.value_ptr.*,
            );
        }

        b.installArtifact(test_exe);

        const tests_run = b.addRunArtifact(test_exe);
        const test_step = b.step("test", "Run tests");
        test_step.dependOn(&tests_run.step);
    }
}
