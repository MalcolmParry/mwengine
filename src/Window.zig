const std = @import("std");
const input = @import("input.zig");
const Keycode = input.Keycode;
const MouseButton = input.MouseButton;
const glfw = @import("glfw");
const Window = @This();

alloc: std.mem.Allocator,
_window: *glfw.Window,
event_queue: []Event,
queue_start: usize,
queue_len: usize,

pub const Event = union(enum) {
    close,
    resize: @Vector(2, u32),
    key_down: Keycode,
    key_up: Keycode,
    key_repeat: Keycode,
    mouse_down: MouseButton,
    mouse_up: MouseButton,
};

pub fn init(alloc: std.mem.Allocator, title: []const u8, size: [2]u32) !*Window {
    try addRef();
    errdefer subRef();

    const nt_title = try alloc.dupeZ(u8, title);
    defer alloc.free(nt_title);
    glfw.windowHint(.client_api, .no_api);
    glfw.windowHint(.visible, true);

    const glfw_window = try glfw.createWindow(@intCast(size[0]), @intCast(size[1]), nt_title, null, null);
    errdefer glfw.destroyWindow(glfw_window);

    _ = glfw.setFramebufferSizeCallback(glfw_window, framebufferSizeCallback);
    _ = glfw.setKeyCallback(glfw_window, keyCallback);
    _ = glfw.setMouseButtonCallback(glfw_window, mouseButtonCallback);

    const window = try alloc.create(Window);
    window.* = .{
        .alloc = alloc,
        ._window = glfw_window,
        .event_queue = try alloc.alloc(Event, 16),
        .queue_start = 0,
        .queue_len = 0,
    };

    glfw.setWindowUserPointer(glfw_window, window);
    return window;
}

pub fn deinit(window: *Window) void {
    window.alloc.free(window.event_queue);
    glfw.destroyWindow(window._window);
    window.alloc.destroy(window);
    subRef();
}

pub fn peekEvent(window: Window) ?Event {
    if (window.queue_len == 0) return null;
    return window.event_queue[window.queue_start];
}

pub fn popEvent(window: *Window) ?Event {
    const event = window.peekEvent() orelse return null;
    window.queue_start = (window.queue_start + 1) % window.event_queue.len;
    window.queue_len -= 1;
    return event;
}

pub fn pendingEvent(window: Window) bool {
    return window.queue_len != 0;
}

pub fn pushEvent(window: *Window, event: Event) !void {
    if (window.queue_len == window.event_queue.len) {
        const old = window.event_queue;

        // 1.5x
        const new_len = @max(old.len + old.len / 2, old.len + 1);
        const new = try window.alloc.alloc(Event, new_len);

        const first_len = @min(window.queue_len, old.len - window.queue_start);
        const last_len = window.queue_len - first_len;

        @memcpy(new[0..first_len], old[window.queue_start..][0..first_len]);
        if (last_len != 0)
            @memcpy(new[first_len..][0..last_len], old[0..last_len]);

        window.alloc.free(window.event_queue);
        window.event_queue = new;
        window.queue_start = 0;
    }

    const i = (window.queue_start + window.queue_len) % window.event_queue.len;
    window.event_queue[i] = event;
    window.queue_len += 1;
}

pub fn setTitle(window: Window, title: []const u8) !void {
    const nt_title = try window.alloc.dupeZ(u8, title);
    defer window.alloc.free(nt_title);

    glfw.setWindowTitle(window._window, nt_title);
}

pub fn update(_: Window) void {
    glfw.pollEvents();
}

pub fn shouldClose(window: Window) bool {
    return glfw.windowShouldClose(window._window);
}

pub fn isKeyDown(window: Window, key: Keycode) bool {
    return glfw.getKey(window._window, keycodeToGlfw(key)) == .press;
}

pub fn isMouseDown(window: Window, button: MouseButton) bool {
    return glfw.getMouseButton(window._window, mouseButtonToGlfw(button)) == .press;
}

pub fn getCursorPos(this: Window) @Vector(2, f32) {
    var x: f64 = 0;
    var y: f64 = 0;
    glfw.getCursorPos(this._window, &x, &y);
    return .{ @floatCast(x), @floatCast(y) };
}

pub const CursorMode = enum {
    normal,
    hidden,
    disabled,
    captured,
};

pub fn setCursorMode(this: Window, mode: CursorMode) !void {
    try glfw.setInputMode(this._window, .cursor, switch (mode) {
        .normal => .normal,
        .hidden => .hidden,
        .disabled => .disabled,
        .captured => .captured,
    });
    try glfw.setInputMode(this._window, .raw_mouse_motion, true);
}

pub fn getFramebufferSize(this: Window) @Vector(2, u32) {
    var width: c_int = undefined;
    var height: c_int = undefined;

    glfw.getFramebufferSize(this._window, &width, &height);
    return @Vector(2, u32){ @intCast(width), @intCast(height) };
}

fn framebufferSizeCallback(glfw_window: *glfw.Window, width: c_int, height: c_int) callconv(.c) void {
    const window: *Window = glfw.getWindowUserPointer(glfw_window, Window).?;
    window.pushEvent(.{ .resize = .{ @intCast(width), @intCast(height) } }) catch @panic("out of memory");
}

fn keyCallback(glfw_window: *glfw.Window, glfw_kc: glfw.Key, scancode: c_int, action: glfw.Action, mods: glfw.Mods) callconv(.c) void {
    _ = scancode;
    _ = mods;

    const window: *Window = glfw.getWindowUserPointer(glfw_window, Window).?;
    const keycode = keycodeFromGlfw(glfw_kc);
    window.pushEvent(switch (action) {
        .press => .{ .key_down = keycode },
        .release => .{ .key_up = keycode },
        .repeat => .{ .key_repeat = keycode },
    }) catch @panic("out of memory");
}

fn mouseButtonCallback(glfw_window: *glfw.Window, glfw_button: glfw.MouseButton, action: glfw.Action, mods: glfw.Mods) callconv(.c) void {
    _ = mods;

    const window: *Window = glfw.getWindowUserPointer(glfw_window, Window).?;
    const button = mouseButtonFromGlfw(glfw_button);
    window.pushEvent(switch (action) {
        .press => .{ .mouse_down = button },
        .release => .{ .mouse_up = button },
        .repeat => unreachable,
    }) catch @panic("out of memory");
}

fn keycodeFromGlfw(glfw_kc: glfw.Key) Keycode {
    return switch (glfw_kc) {
        .space => .space,
        .apostrophe => .apostrophe,
        .comma => .comma,
        .minus => .minus,
        .period => .period,
        .slash => .slash,
        .zero => .zero,
        .one => .one,
        .two => .two,
        .three => .three,
        .four => .four,
        .five => .five,
        .six => .six,
        .seven => .seven,
        .eight => .eight,
        .nine => .nine,
        .semicolon => .semicolon,
        .equal => .equal,
        .a => .a,
        .b => .b,
        .c => .c,
        .d => .d,
        .e => .e,
        .f => .f,
        .g => .g,
        .h => .h,
        .i => .i,
        .j => .j,
        .k => .k,
        .l => .l,
        .m => .m,
        .n => .n,
        .o => .o,
        .p => .p,
        .q => .q,
        .r => .r,
        .s => .s,
        .t => .t,
        .u => .u,
        .v => .v,
        .w => .w,
        .x => .x,
        .y => .y,
        .z => .z,
        .left_bracket => .left_bracket,
        .backslash => .backslash,
        .right_bracket => .right_bracket,
        .grave_accent => .grave_accent,
        .world_1 => .world_1,
        .world_2 => .world_2,

        .escape => .escape,
        .enter => .enter,
        .tab => .tab,
        .backspace => .backspace,
        .insert => .insert,
        .delete => .delete,
        .right => .right,
        .left => .left,
        .down => .down,
        .up => .up,
        .page_up => .page_down,
        .page_down => .page_up,
        .home => .home,
        .end => .end,
        .caps_lock => .caps_lock,
        .scroll_lock => .scroll_lock,
        .num_lock => .num_lock,
        .print_screen => .print_screen,
        .pause => .pause,
        .F1 => .F1,
        .F2 => .F2,
        .F3 => .F3,
        .F4 => .F4,
        .F5 => .F5,
        .F6 => .F6,
        .F7 => .F7,
        .F8 => .F8,
        .F9 => .F9,
        .F10 => .F10,
        .F11 => .F11,
        .F12 => .F12,
        .F13 => .F13,
        .F14 => .F14,
        .F15 => .F15,
        .F16 => .F16,
        .F17 => .F17,
        .F18 => .F18,
        .F19 => .F19,
        .F20 => .F20,
        .F21 => .F21,
        .F22 => .F22,
        .F23 => .F23,
        .F24 => .F24,
        .F25 => .F25,
        .kp_0 => .kp_0,
        .kp_1 => .kp_1,
        .kp_2 => .kp_2,
        .kp_3 => .kp_3,
        .kp_4 => .kp_4,
        .kp_5 => .kp_5,
        .kp_6 => .kp_6,
        .kp_7 => .kp_7,
        .kp_8 => .kp_8,
        .kp_9 => .kp_9,
        .kp_decimal => .kp_decimal,
        .kp_divide => .kp_divide,
        .kp_multiply => .kp_multiply,
        .kp_subtract => .kp_subtract,
        .kp_add => .kp_add,
        .kp_enter => .kp_enter,
        .kp_equal => .kp_equal,
        .left_shift => .left_shift,
        .left_control => .left_control,
        .left_alt => .left_alt,
        .left_super => .left_super,
        .right_shift => .right_shift,
        .right_control => .right_control,
        .right_alt => .right_alt,
        .right_super => .right_super,
        .menu => .menu,
        else => .unknown,
    };
}

fn keycodeToGlfw(kc: Keycode) glfw.Key {
    return switch (kc) {
        .space => .space,
        .apostrophe => .apostrophe,
        .comma => .comma,
        .minus => .minus,
        .period => .period,
        .slash => .slash,
        .zero => .zero,
        .one => .one,
        .two => .two,
        .three => .three,
        .four => .four,
        .five => .five,
        .six => .six,
        .seven => .seven,
        .eight => .eight,
        .nine => .nine,
        .semicolon => .semicolon,
        .equal => .equal,
        .a => .a,
        .b => .b,
        .c => .c,
        .d => .d,
        .e => .e,
        .f => .f,
        .g => .g,
        .h => .h,
        .i => .i,
        .j => .j,
        .k => .k,
        .l => .l,
        .m => .m,
        .n => .n,
        .o => .o,
        .p => .p,
        .q => .q,
        .r => .r,
        .s => .s,
        .t => .t,
        .u => .u,
        .v => .v,
        .w => .w,
        .x => .x,
        .y => .y,
        .z => .z,
        .left_bracket => .left_bracket,
        .backslash => .backslash,
        .right_bracket => .right_bracket,
        .grave_accent => .grave_accent,
        .world_1 => .world_1,
        .world_2 => .world_2,

        .escape => .escape,
        .enter => .enter,
        .tab => .tab,
        .backspace => .backspace,
        .insert => .insert,
        .delete => .delete,
        .right => .right,
        .left => .left,
        .down => .down,
        .up => .up,
        .page_up => .page_down,
        .page_down => .page_up,
        .home => .home,
        .end => .end,
        .caps_lock => .caps_lock,
        .scroll_lock => .scroll_lock,
        .num_lock => .num_lock,
        .print_screen => .print_screen,
        .pause => .pause,
        .F1 => .F1,
        .F2 => .F2,
        .F3 => .F3,
        .F4 => .F4,
        .F5 => .F5,
        .F6 => .F6,
        .F7 => .F7,
        .F8 => .F8,
        .F9 => .F9,
        .F10 => .F10,
        .F11 => .F11,
        .F12 => .F12,
        .F13 => .F13,
        .F14 => .F14,
        .F15 => .F15,
        .F16 => .F16,
        .F17 => .F17,
        .F18 => .F18,
        .F19 => .F19,
        .F20 => .F20,
        .F21 => .F21,
        .F22 => .F22,
        .F23 => .F23,
        .F24 => .F24,
        .F25 => .F25,
        .kp_0 => .kp_0,
        .kp_1 => .kp_1,
        .kp_2 => .kp_2,
        .kp_3 => .kp_3,
        .kp_4 => .kp_4,
        .kp_5 => .kp_5,
        .kp_6 => .kp_6,
        .kp_7 => .kp_7,
        .kp_8 => .kp_8,
        .kp_9 => .kp_9,
        .kp_decimal => .kp_decimal,
        .kp_divide => .kp_divide,
        .kp_multiply => .kp_multiply,
        .kp_subtract => .kp_subtract,
        .kp_add => .kp_add,
        .kp_enter => .kp_enter,
        .kp_equal => .kp_equal,
        .left_shift => .left_shift,
        .left_control => .left_control,
        .left_alt => .left_alt,
        .left_super => .left_super,
        .right_shift => .right_shift,
        .right_control => .right_control,
        .right_alt => .right_alt,
        .right_super => .right_super,
        .menu => .menu,
        else => .unknown,
    };
}

fn mouseButtonToGlfw(button: MouseButton) glfw.MouseButton {
    return switch (button) {
        .left => .left,
        .right => .right,
        .middle => .middle,
        .four => .four,
        .five => .five,
        .six => .six,
        .seven => .seven,
        .eight => .eight,
    };
}

fn mouseButtonFromGlfw(button: glfw.MouseButton) MouseButton {
    return switch (button) {
        .left => .left,
        .right => .right,
        .middle => .middle,
        .four => .four,
        .five => .five,
        .six => .six,
        .seven => .seven,
        .eight => .eight,
    };
}

pub const vulkan = struct {
    const gpu = @import("gpu/gpu.zig");
    const vk = @import("vulkan");

    const Error = gpu.Instance.InitError;
    fn glfwErrorToInstanceInit(err: glfw.Error) Error {
        return switch (err) {
            error.OutOfMemory => Error.OutOfMemory,
            error.APIUnavailable,
            error.VersionUnavailable,
            error.FeatureUnimplemented,
            error.FeatureUnavailable,
            error.PlatformError,
            error.PlatformUnavailable,
            => Error.NotSupported,
            else => Error.Unknown,
        };
    }

    pub const Wrapper = struct {
        pub fn init() !@This() {
            addRef() catch |err| return glfwErrorToInstanceInit(err);
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
        return glfw.getRequiredInstanceExtensions() catch |err| return glfwErrorToInstanceInit(err);
    }

    pub fn createSurface(window: *Window, instance: vk.InstanceProxy) gpu.Display.InitError!vk.SurfaceKHR {
        const vk_alloc: ?*vk.AllocationCallbacks = null;
        var surface: vk.SurfaceKHR = undefined;
        glfw.createWindowSurface(instance.handle, window._window, vk_alloc, &surface) catch |err| return switch (err) {
            error.OutOfMemory => Error.OutOfMemory,
            error.APIUnavailable,
            error.VersionUnavailable,
            error.FeatureUnimplemented,
            error.FeatureUnavailable,
            error.PlatformError,
            error.PlatformUnavailable,
            => Error.NotSupported,
            else => Error.Unknown,
        };
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
