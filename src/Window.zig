const std = @import("std");
const events = @import("events.zig");
const glfw = @import("glfw");
const Window = @This();

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
        _ = glfw.setKeyCallback(window, keyCallback);
        _ = glfw.setMouseButtonCallback(window, mouseButtonCallback);
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

pub fn isKeyDown(this: *const Window, key: events.Keycode) bool {
    return glfw.getKey(this._window, keycodeToGlfw(key)) == .press;
}

pub fn isMouseDown(this: *const Window, button: events.MouseButton) bool {
    return glfw.getMouseButton(this._window, mouseButtonToGlfw(button)) == .press;
}

pub fn getCursorPos(this: *const Window) @Vector(2, f32) {
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

pub fn setCursorMode(this: *Window, mode: CursorMode) !void {
    try glfw.setInputMode(this._window, .cursor, switch (mode) {
        .normal => .normal,
        .hidden => .hidden,
        .disabled => .disabled,
        .captured => .captured,
    });
    try glfw.setInputMode(this._window, .raw_mouse_motion, true);
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

fn keyCallback(window: *glfw.Window, glfw_kc: glfw.Key, scancode: c_int, action: glfw.Action, mods: glfw.Mods) callconv(.c) void {
    _ = scancode;
    _ = mods;

    const event_queue: *events.Queue = glfw.getWindowUserPointer(window, events.Queue).?;
    const keycode = keycodeFromGlfw(glfw_kc);
    event_queue.push(switch (action) {
        .press => .{ .key_down = keycode },
        .release => .{ .key_up = keycode },
        .repeat => .{ .key_repeat = keycode },
    }) catch @panic("out of memory");
}

fn mouseButtonCallback(window: *glfw.Window, glfw_button: glfw.MouseButton, action: glfw.Action, mods: glfw.Mods) callconv(.c) void {
    _ = mods;

    const event_queue: *events.Queue = glfw.getWindowUserPointer(window, events.Queue).?;
    const button = mouseButtonFromGlfw(glfw_button);
    event_queue.push(switch (action) {
        .press => .{ .mouse_down = button },
        .release => .{ .mouse_up = button },
        .repeat => unreachable,
    }) catch @panic("out of memory");
}

fn keycodeFromGlfw(glfw_kc: glfw.Key) events.Keycode {
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

fn keycodeToGlfw(kc: events.Keycode) glfw.Key {
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

fn mouseButtonToGlfw(button: events.MouseButton) glfw.MouseButton {
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

fn mouseButtonFromGlfw(button: glfw.MouseButton) events.MouseButton {
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
    const gpu = @import("gpu.zig");
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
