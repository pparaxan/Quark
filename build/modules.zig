const std = @import("std");
const binder = @import("binder");

pub fn modules(b: *std.Build, lib_webview: *std.Build.Dependency, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) !void {
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
    libquark_mod.addImport("frontend", frontend_mod);
}
