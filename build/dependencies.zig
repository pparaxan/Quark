const std = @import("std");
const build = @import("../build.zig");

pub fn dependencies(b: *std.Build) ![]*std.Build.Dependency {
    const allocator = std.heap.page_allocator;
    var deps = std.ArrayList(*std.Build.Dependency).init(allocator);
    try deps.append(b.dependency("webview", .{}));
    try deps.append(b.dependency("httpz", .{}));

    return deps.items;
}
