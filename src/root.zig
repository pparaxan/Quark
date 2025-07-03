const std = @import("std");

pub const WindowConfig = @import("config.zig").WindowConfig;
pub const WindowHint = @import("config.zig").WindowHint;
pub const QuarkWindow = @import("window.zig").QuarkWindow;

pub fn create_window(config: *WindowConfig) !QuarkWindow {
    return QuarkWindow.create(config);
}

pub fn execute_window(window: QuarkWindow) !void {
    return window.run();
}

pub fn destroy_window(window: *QuarkWindow) !void {
    return window.destroy();
}
