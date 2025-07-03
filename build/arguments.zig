const std = @import("std");

pub fn arguments(b: *std.Build, libquark_mod: *std.Build.Module) void {
    const options = b.addOptions();

    const argument_reload = b.option(bool, "reload", "Enable automatic backend/frontend rebuild") orelse false;
    options.addOption(bool, "reload", argument_reload);

    libquark_mod.addOptions("reload", options);
}
