const std = @import("std");
const events = @import("../events.zig");
const glfw = @import("glfw");

pub const Window = struct {
    _window: *glfw.Window,
    maybe_event_queue: ?*events.Queue,

    pub fn init(alloc: std.mem.Allocator, title: []const u8, size: @Vector(2, u32), maybe_event_queue: ?*events.Queue) !Window {
        try addRef();
        const nt_title = try alloc.dupeZ(u8, title);
        defer alloc.free(nt_title);
        glfw.windowHint(.client_api, .no_api);
        glfw.windowHint(.visible, true);

        const window = try glfw.createWindow(@intCast(size[0]), @intCast(size[1]), nt_title, null);
        errdefer {
            glfw.destroyWindow(window);
            subRef();
        }

        if (maybe_event_queue) |event_queue| {
            glfw.setWindowUserPointer(window, event_queue);
            _ = glfw.setFramebufferSizeCallback(window, framebufferSizeCallback);
        }

        return .{
            ._window = window,
            .maybe_event_queue = maybe_event_queue,
        };
    }

    pub fn deinit(this: *Window) void {
        glfw.destroyWindow(this._window);
        subRef();
    }

    pub fn setTitle(this: *Window, title: []const u8, alloc: std.mem.Allocator) !void {
        const nt_title = try alloc.dupeZ(u8, title);
        defer alloc.free(nt_title);

        glfw.setWindowTitle(this._window, nt_title);
    }

    pub fn update(this: *Window) void {
        _ = this;
        glfw.pollEvents();
    }

    pub fn shouldClose(this: *Window) bool {
        return glfw.windowShouldClose(this._window);
    }

    pub fn getFramebufferSize(this: *const Window) @Vector(2, u32) {
        var width: c_int = undefined;
        var height: c_int = undefined;

        glfw.getFramebufferSize(this._window, &width, &height);
        return @Vector(2, u32){ @intCast(width), @intCast(height) };
    }

    fn framebufferSizeCallback(window: *glfw.Window, height: c_int, width: c_int) callconv(.c) void {
        const event_queue: *events.Queue = glfw.getWindowUserPointer(window, events.Queue).?;
        event_queue.push(.{ .resize = .{ @intCast(width), @intCast(height) } }) catch @panic("out of memory");
    }
};

pub const vulkan = struct {
    const vk = @import("vulkan");

    pub const Wrapper = struct {
        pub fn init() !@This() {
            try addRef();
            return .{};
        }

        pub fn deinit(this: *@This()) void {
            _ = this;
            subRef();
        }

        pub fn getBaseWrapper(this: *@This()) !vk.BaseWrapper {
            _ = this;
            return vk.BaseWrapper.load(glfw.getInstanceProcAddress);
        }
    };

    pub fn getRequiredInstanceExtensions() ![][*:0]const u8 {
        return try glfw.getRequiredInstanceExtensions();
    }

    pub fn createSurface(window: *Window, instance: vk.InstanceProxy) !vk.SurfaceKHR {
        const vk_alloc: ?*vk.AllocationCallbacks = null;
        var surface: vk.SurfaceKHR = undefined;
        try glfw.createWindowSurface(instance.handle, window._window, vk_alloc, &surface);
        return surface;
    }
};

var refs: u32 = 0;
fn addRef() !void {
    if (refs == 0) {
        _ = glfw.setErrorCallback(&errorCallback);
        try glfw.init();
    }

    refs += 1;
}

fn subRef() void {
    refs -= 1;

    if (refs == 0)
        glfw.terminate();
}

fn errorCallback(code: c_int, description: ?[*:0]const u8) callconv(.c) void {
    std.log.err("glfw error {}: {s}", .{ code, description.? });
}
