const std = @import("std");
const binder = @import("binder");
const config = @import("src/config.zig");
const arguments = @import("src/arguments.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSafe,
    });

    const options = b.addOptions();
    const argument_reload = b.option(bool, "reload", "Enable automatic backend/frontend rebuild") orelse false;
    options.addOption(bool, "reload", argument_reload);


    const lib_webview = b.dependency("webview", .{});
    const lib_httpz = b.dependency("httpz", .{
        .target = target,
        .optimize = optimize,
    });

    const frontend = try binder.generate(b, .{
        .source_dir = "src_quark",
        .target_file = "binder.zig",
        .namespace = "quark_frontend",
    });

    const webview_mod = b.addTranslateC(.{
        .root_source_file = lib_webview.path("core/include/webview/webview.h"),
        .optimize = optimize,
        .target = target,
    }).createModule();

    const frontend_mod = b.createModule(.{
        .root_source_file = .{ .cwd_relative = frontend },
    });

    const libquark_mod = b.addModule("libquark", .{
        .root_source_file = b.path("src/root.zig"),
    });

    libquark_mod.addImport("webview", webview_mod);
    libquark_mod.addImport("httpz", lib_httpz.module("httpz"));
    libquark_mod.addImport("frontend", frontend_mod);

    libquark_mod.addOptions("reload", options);

    const libquark = b.addLibrary(.{
        .name = "quark",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .linkage = .dynamic,
    });

    libquark.addIncludePath(lib_webview.path("core/include/webview/"));
    libquark.root_module.addCMacro("WEBVIEW_STATIC", "1");
    libquark.linkLibCpp();
    libquark.root_module.addImport("webview", webview_mod);
    libquark.root_module.addImport("httpz", lib_httpz.module("httpz"));
    libquark.root_module.addImport("frontend", frontend_mod);

    // libquark.root_module.define("enable_reload", if (argument_reload) "true" else "false"); // expose the argument to QuarkWindow.

    // libquark.root_module.arguments = .{
    //     .enable_reload = argument_reload,
    // };

    switch (@import("builtin").os.tag) {
        .macos => {
            libquark.addCSourceFile(.{ .file = lib_webview.path("core/src/webview.cc"), .flags = &.{"-std=c++11"} });
            libquark.linkFramework("WebKit");
        },
        .freebsd => {
            libquark.addCSourceFile(.{ .file = lib_webview.path("core/src/webview.cc"), .flags = &.{"-std=c++11"} });
            libquark.addIncludePath(.{ .cwd_relative = "/usr/local/include/cairo/" });
            libquark.addIncludePath(.{ .cwd_relative = "/usr/local/include/gtk-3.0/" });
            libquark.addIncludePath(.{ .cwd_relative = "/usr/local/include/glib-2.0/" });
            libquark.addIncludePath(.{ .cwd_relative = "/usr/local/lib/glib-2.0/include/" });
            libquark.addIncludePath(.{ .cwd_relative = "/usr/local/include/webkitgtk-4.1/" });
            libquark.addIncludePath(.{ .cwd_relative = "/usr/local/include/pango-1.0/" });
            libquark.addIncludePath(.{ .cwd_relative = "/usr/local/include/harfbuzz/" });
            libquark.addIncludePath(.{ .cwd_relative = "/usr/local/include/gdk-pixbuf-2.0/" });
            libquark.addIncludePath(.{ .cwd_relative = "/usr/local/include/atk-1.0/" });
            libquark.addIncludePath(.{ .cwd_relative = "/usr/local/include/libsoup-3.0/" });
            libquark.linkSystemLibrary("gtk-3");
            libquark.linkSystemLibrary("webkit2gtk-4.1");
        },
        .linux => {
            libquark.addCSourceFile(.{ .file = lib_webview.path("core/src/webview.cc"), .flags = &.{"-std=c++11"} });
            libquark.linkSystemLibrary("gtk4");
            libquark.linkSystemLibrary("webkitgtk-6.0");
        },
        else => {
            @compileError("Unsupported operating system for libquark.");
        },
    }

    b.installArtifact(libquark);
}
