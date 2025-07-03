const std = @import("std");
const webview = @import("webview");
const config = @import("config.zig");
const errors = @import("errors.zig");
const WebViewError = errors.WebViewError;
pub const frontend = @import("frontend");
const httpz = @import("httpz");
const arguments = @import("arguments.zig");

pub const QuarkWindow = struct {
    handle: webview.webview_t,
    config: *config.WindowConfig,
    allocator: std.mem.Allocator,
    gpa: std.heap.GeneralPurposeAllocator(.{}),
    server: ?*httpz.Server(void) = null,
    server_thread: ?std.Thread = null,
    server_gpa: ?std.heap.GeneralPurposeAllocator(.{}) = null,

    const Self = @This();

    pub fn create(window_config: *config.WindowConfig) (WebViewError || error{OutOfMemory})!Self {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        const allocator = gpa.allocator();

        const handle = webview.webview_create(@intFromBool(window_config.debug_mode), null);
        if (handle == null) return WebViewError.MissingDependency;

        var window = Self{
            .handle = handle,
            .config = window_config,
            .allocator = allocator,
            .gpa = gpa,
        };

        try window.initialize();
        return window;
    }

    fn initialize(self: *Self) WebViewError!void {
        self.set_title() catch |err| @panic(@errorName(err));

        if (arguments.reload) {
            self.reload_entrypoint() catch |err| @panic(@errorName(err));
        } else {
            self.setup_gvfs() catch |err| @panic(@errorName(err));
            self.load_entrypoint() catch |err| @panic(@errorName(err));
        }
    }

    fn set_title(self: *Self) WebViewError!void {
        return check_error(webview.webview_set_title(self.handle, self.config.title));
    }

    fn setup_gvfs(self: *Self) !void {
        var vfs = try @import("VFS/backend/qvfs.zig").QuarkVirtualFileSystem.init(self.allocator);
        defer vfs.deinit();

        const js_injection = try vfs.generate_injection_code();
        defer self.allocator.free(js_injection);

        const null_terminated = try self.allocator.dupeZ(u8, js_injection);
        defer self.allocator.free(null_terminated);

        try check_error(webview.webview_init(self.handle, null_terminated.ptr));
    }

    fn load_entrypoint(self: *Self) !void {
        const html_content = frontend.get("index.html") orelse return WebViewError.Unspecified;
        const null_terminated = try self.allocator.dupeZ(u8, html_content);
        defer self.allocator.free(null_terminated);

        try check_error(webview.webview_set_html(self.handle, null_terminated.ptr));
    }

    fn reload_entrypoint(self: *Self) !void { // AI was used for this function.
        if (self.server) |srv| {
            std.log.info("Stopping existing server...", .{});
            srv.stop();

            if (self.server_thread) |thread| {
                thread.join();
                self.server_thread = null;
            }

            std.time.sleep(100 * std.time.ns_per_ms);
            srv.deinit();

            if (self.server_gpa) |*server_gpa| {
                server_gpa.allocator().destroy(srv);
                _ = server_gpa.deinit();
                self.server_gpa = null;
            }

            self.server = null;
        }

        var server_gpa = std.heap.GeneralPurposeAllocator(.{}){};
        const server_allocator = server_gpa.allocator();

        const server_ptr = try server_allocator.create(httpz.Server(void));
        errdefer server_allocator.destroy(server_ptr);

        server_ptr.* = httpz.Server(void).init(server_allocator, .{
            .port = 58678,
            .address = "127.0.0.1",
        }, {}) catch |err| {
            server_allocator.destroy(server_ptr);
            std.log.err("Failed to initialize HTTP server: {}", .{err});
            return err;
        };

        self.server = server_ptr;
        self.server_gpa = server_gpa;

        var router = server_ptr.router(.{}) catch |err| {
            std.log.err("Failed to create router: {}", .{err});
            return err;
        };

        router.get("/*", struct {
            fn handler(req: *httpz.Request, res: *httpz.Response) !void {
                const path = if (std.mem.eql(u8, req.url.path, "/"))
                    "index.html"
                else
                    req.url.path[1..];

                const content = frontend.get(path) orelse {
                    res.status = 404;
                    res.body = "Not Found";
                    return;
                };

                res.body = content;
            }
        }.handler, .{});

        const thread = std.Thread.spawn(.{}, struct {
            fn run(srv: *httpz.Server(void)) void {
                std.log.info("Starting HTTP server on port 58678...", .{});
                srv.listen() catch |err| {
                    std.log.err("HTTP server error: {}", .{err});
                };
                std.log.info("HTTP server stopped", .{});
            }
        }.run, .{server_ptr}) catch |err| {
            std.log.err("Failed to spawn server thread: {}", .{err});
            return err;
        };

        self.server_thread = thread;

        std.time.sleep(500 * std.time.ns_per_ms);

        std.log.info("Navigating to localhost server...", .{});
        try check_error(webview.webview_navigate(self.handle, "http://127.0.0.1:58678"));
    }

    pub fn run(self: Self) WebViewError!void {
        return check_error(webview.webview_run(self.handle));
    }

    pub fn destroy(self: *Self) !void {
        if (self.server) |srv| {
            std.log.info("Stopping HTTP server...", .{});
            srv.stop();

            if (self.server_thread) |thread| {
                thread.join();
                self.server_thread = null;
            }

            srv.deinit();

            if (self.server_gpa) |*server_gpa| {
                server_gpa.allocator().destroy(srv);
                _ = server_gpa.deinit();
                self.server_gpa = null;
            }

            self.server = null;
        }


        if (self.handle != null) {
            try check_error(webview.webview_destroy(self.handle));
            self.handle = null;
        }

        _ = self.gpa.deinit();
    }
};

fn check_error(code: c_int) WebViewError!void {
    if (code != webview.WEBVIEW_ERROR_OK) {
        return errors.map_error(code);
    }
}
