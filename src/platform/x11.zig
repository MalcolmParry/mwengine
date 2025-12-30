const std = @import("std");
const x = @import("x");
const events = @import("../events.zig");

pub const Window = struct {
    maybe_event_queue: ?*events.Queue,
    _should_close: bool,
    _source: x.Source,
    _reader: std.net.Stream.Reader,
    _writer: std.net.Stream.Writer,
    _window: x.Window,

    pub fn init(alloc: std.mem.Allocator, title: []const u8, size: @Vector(2, u32), maybe_event_queue: ?*events.Queue) !Window {
        var this: @This() = undefined;
        this.maybe_event_queue = maybe_event_queue;
        this._should_close = false;

        try x.wsaStartup();

        var read_buffer: [256]u8 = undefined;
        this._reader, const used_auth = try x.draft.connect(&read_buffer);
        errdefer x.disconnect(this._reader.getStream());
        _ = used_auth;

        const setup = try x.readSetupSuccess(this._reader.interface());
        this._source = .initFinishSetup(this._reader.interface(), &setup);
        std.log.info("setup reply {f}", .{setup});
        try this._source.requireReplyAtLeast(setup.required());

        {
            var used = false;
            const fmt = this._source.fmtReplyData(setup.vendor_len, &used);
            x.log.info("vendor '{f}'", .{fmt});
            std.debug.assert(used == true);
        }
        try this._source.replyDiscard(x.pad4Len(@truncate(setup.vendor_len)));

        const screen = blk: {
            var formats_buf: [std.math.maxInt(u8)]x.Format = undefined;
            const formats = formats_buf[0..setup.format_count];
            for (formats, 0..) |*format, i| {
                try this._source.readReply(std.mem.asBytes(format));
                std.log.info(
                    "format[{}] depth={} bpp={} scanlinepad={}",
                    .{ i, format.depth, format.bits_per_pixel, format.scanline_pad },
                );
            }

            var first_screen: ?x.ScreenHeader = null;

            for (0..setup.root_screen_count) |screen_index| {
                try this._source.requireReplyAtLeast(@sizeOf(x.ScreenHeader));
                var screen_header: x.ScreenHeader = undefined;
                try this._source.readReply(std.mem.asBytes(&screen_header));
                std.log.info("screen {} | {}", .{ screen_index, screen_header });
                if (first_screen == null) {
                    first_screen = screen_header;
                }
                try this._source.requireReplyAtLeast(@as(u35, screen_header.allowed_depth_count) * @sizeOf(x.ScreenDepth));
                for (0..screen_header.allowed_depth_count) |depth_index| {
                    var depth: x.ScreenDepth = undefined;
                    try this._source.readReply(std.mem.asBytes(&depth));
                    try this._source.requireReplyAtLeast(@as(u35, depth.visual_type_count) * @sizeOf(x.VisualType));
                    std.log.info("screen {} | depth {} | {}", .{ screen_index, depth_index, depth });
                    for (0..depth.visual_type_count) |visual_index| {
                        var visual: x.VisualType = undefined;
                        try this._source.readReply(std.mem.asBytes(&visual));
                        if (false) std.log.info("screen {} | depth {} | visual {} | {}\n", .{ screen_index, depth_index, visual_index, visual });
                    }
                }
            }

            const remaining = this._source.replyRemainingSize();
            if (remaining != 0) {
                x.log.err("setup reply had an extra {} bytes", .{remaining});
                return error.xProtocol;
            }

            const screen = first_screen orelse {
                std.log.err("no screen?", .{});
                std.process.exit(0xff);
            };

            break :blk screen;
        };

        var write_buffer: [256]u8 = undefined;
        this._writer = x.socketWriter(this._reader.getStream(), &write_buffer);
        var sink: x.RequestSink = .{ .writer = &this._writer.interface };

        this._window = setup.resource_id_base.add(0).window();
        try sink.CreateWindow(.{
            .window_id = this._window,
            .parent_window_id = screen.root,
            .depth = 0,
            .x = 0,
            .y = 0,
            .width = @intCast(size[0]),
            .height = @intCast(size[1]),
            .border_width = 0,
            .class = .input_output,
            .visual_id = screen.root_visual,
        }, .{
            .bg_pixel = 0xffffff,
            .event_mask = .{
                .Exposure = 1,
            },
        });

        try this.setTitle(title, alloc);
        try sink.MapWindow(this._window);
        try sink.writer.flush();

        return this;
    }

    pub fn deinit(this: *Window) void {
        x.disconnect(this._reader.getStream());
    }

    pub fn setTitle(this: *Window, title: []const u8, alloc: std.mem.Allocator) !void {
        _ = alloc;
        var sink: x.RequestSink = .{ .writer = &this._writer.interface };
        try sink.ChangeProperty(.replace, this._window, .WM_NAME, .STRING, u8, .init(title.ptr, @intCast(title.len)));
        try sink.writer.flush();
    }

    pub fn update(this: *Window) !void {
        _ = this;
        // var sink: x.RequestSink = .{ .writer = &this._writer.interface };
        //
        // while (true) {
        //     try sink.writer.flush();
        //     const kind = try this._source.readKind();
        //
        //     switch (kind) {
        //         else => unreachable,
        //     }
        // }
    }

    pub fn shouldClose(this: *Window) bool {
        return this._should_close;
    }

    pub fn getFramebufferSize(this: *const Window) @Vector(2, u32) {
        _ = this;
        return @splat(0);
    }
};

pub const vulkan = struct {
    const vk = @import("vulkan");

    const required_instance_extensions: [2][*:0]const u8 = .{
        vk.extensions.khr_surface.name,
        vk.extensions.khr_xlib_surface.name,
    };

    pub fn getRequiredInstanceExtensions() ![]const [*:0]const u8 {
        return &required_instance_extensions;
    }

    pub fn createSurface(window: *Window, instance: vk.InstanceProxy) !vk.SurfaceKHR {
        const vk_alloc: ?*vk.AllocationCallbacks = null;

        return instance.createXlibSurfaceKHR(&.{
            .dpy = @ptrCast(window._display),
            .window = window._window,
        }, vk_alloc);
    }
};
