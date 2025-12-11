const std = @import("std");
const tracy = @import("tracy");
const vk = @import("vulkan");
const Device = @import("Device.zig");
const platform = @import("../../platform.zig");

const extra_required_extensions: [3][*:0]const u8 = .{
    vk.extensions.khr_get_surface_capabilities_2.name,
    vk.extensions.ext_surface_maintenance_1.name,
    vk.extensions.khr_get_physical_device_properties_2.name,
};

const validation_layer: [1][*:0]const u8 = .{"VK_LAYER_KHRONOS_validation"};
const debug_extensions: [1][*:0]const u8 = .{
    vk.extensions.ext_debug_utils.name,
};

_platform_wrapper: platform.vulkan.Wrapper,
_instance: vk.InstanceProxy,
_maybe_debug_messenger: ?vk.DebugUtilsMessengerEXT,
_physical_devices: []Device.Physical,

const Error = error{
    CantLoadVulkan,
};

//  TODO: add app version to paramerers
pub fn init(debug_logging: bool, alloc: std.mem.Allocator) !@This() {
    const zone = tracy.Zone.begin(.{
        .src = @src(),
    });
    defer zone.end();

    const vk_alloc: ?*vk.AllocationCallbacks = null;
    var platform_wrapper = try platform.vulkan.Wrapper.init();
    const vkb = try platform_wrapper.getBaseWrapper();

    // TODO: check extention support
    var extensions: std.ArrayList([*:0]const u8) = .empty;
    defer extensions.deinit(alloc);
    try extensions.appendSlice(alloc, try platform.vulkan.getRequiredInstanceExtensions());
    try extensions.appendSlice(alloc, &extra_required_extensions);
    if (debug_logging) try extensions.appendSlice(alloc, &debug_extensions);

    const layers: []const [*:0]const u8 = if (debug_logging) &validation_layer else &.{};

    const instance_handle = try vkb.createInstance(&.{
        .p_application_info = &.{
            .p_application_name = "placeholder",
            .application_version = 0,
            .p_engine_name = "mwengine",
            .engine_version = 0, // TODO: fill in
            .api_version = @bitCast(vk.API_VERSION_1_0),
        },
        .enabled_extension_count = @intCast(extensions.items.len),
        .pp_enabled_extension_names = extensions.items.ptr,
        .enabled_layer_count = @intCast(layers.len),
        .pp_enabled_layer_names = layers.ptr,
        .flags = .{},
    }, vk_alloc);

    const instance_wrapper = try alloc.create(vk.InstanceWrapper);
    errdefer alloc.destroy(instance_wrapper);
    instance_wrapper.* = .load(instance_handle, vkb.dispatch.vkGetInstanceProcAddr orelse return Error.CantLoadVulkan);
    const instance: vk.InstanceProxy = .init(instance_handle, instance_wrapper);
    errdefer instance.destroyInstance(vk_alloc);

    const maybe_debug_messenger = if (debug_logging) blk: {
        break :blk try instance.createDebugUtilsMessengerEXT(&.{
            .message_severity = .{
                .verbose_bit_ext = true,
                .warning_bit_ext = true,
                .error_bit_ext = true,
            },
            .message_type = .{
                .general_bit_ext = true,
                .validation_bit_ext = true,
                .performance_bit_ext = true,
            },
            .pfn_user_callback = debugMessengerCallback,
            .p_user_data = null,
        }, vk_alloc);
    } else null;

    errdefer if (maybe_debug_messenger) |debug_messenger|
        instance.destroyDebugUtilsMessengerEXT(debug_messenger, vk_alloc);

    const native_phyical_devices = try instance.enumeratePhysicalDevicesAlloc(alloc);
    defer alloc.free(native_phyical_devices);
    const physical_devices = try alloc.alloc(Device.Physical, native_phyical_devices.len);
    errdefer alloc.free(physical_devices);

    for (physical_devices, native_phyical_devices) |*phys_dev, native| {
        phys_dev.* = .{ ._device = native };

        const queue_families = try instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(native, alloc);
        defer alloc.free(queue_families);

        std.debug.print("\n", .{});
        for (queue_families) |prop| {
            std.debug.print("queue family {}: ", .{prop.queue_count});

            if (prop.queue_flags.graphics_bit) {
                std.debug.print("graphics ", .{});
            }

            if (prop.queue_flags.compute_bit) {
                std.debug.print("compute ", .{});
            }

            if (prop.queue_flags.transfer_bit) {
                std.debug.print("transfer ", .{});
            }

            std.debug.print("\n", .{});
        }

        std.debug.print("\n", .{});
    }

    return .{
        ._platform_wrapper = platform_wrapper,
        ._instance = instance,
        ._maybe_debug_messenger = maybe_debug_messenger,
        ._physical_devices = physical_devices,
    };
}

pub fn deinit(this: *@This(), alloc: std.mem.Allocator) void {
    const zone = tracy.Zone.begin(.{
        .src = @src(),
    });
    defer zone.end();

    const vk_alloc: ?*vk.AllocationCallbacks = null;
    alloc.free(this._physical_devices);
    if (this._maybe_debug_messenger) |debug_messenger|
        this._instance.destroyDebugUtilsMessengerEXT(debug_messenger, vk_alloc);
    this._instance.destroyInstance(vk_alloc);
    alloc.destroy(this._instance.wrapper);
    this._platform_wrapper.deinit();
}

pub const initDevice = Device.init;

pub fn bestPhysicalDevice(this: *const @This(), alloc: std.mem.Allocator) !Device.Physical {
    const zone = tracy.Zone.begin(.{
        .src = @src(),
    });
    defer zone.end();

    _ = alloc;

    var best_device: ?Device.Physical = null;
    var best_score: i32 = -1;
    for (this._physical_devices) |device| {
        const native = device._device;
        const features = this._instance.getPhysicalDeviceFeatures(native);
        const properties = this._instance.getPhysicalDeviceProperties(native);
        _ = features;

        var score: i32 = 0;

        if (properties.device_type == .discrete_gpu) {
            score += 1000;
        }

        score += @intCast(properties.limits.max_image_dimension_2d);

        std.log.info("Device ({}): {s}", .{ score, properties.device_name });
        std.log.info("Max Image: {}", .{properties.limits.max_image_dimension_2d});
        if (score > best_score) {
            best_score = score;
            best_device = device;
        }
    }

    if (best_score == -1) best_device = null;
    const properties = this._instance.getPhysicalDeviceProperties(best_device.?._device);
    std.log.info("{s}\n", .{properties.device_name});
    return best_device orelse error.NoDeviceAvailable;
}

fn debugMessengerCallback(message_severity: vk.DebugUtilsMessageSeverityFlagsEXT, message_type: vk.DebugUtilsMessageTypeFlagsEXT, callback_data: ?*const vk.DebugUtilsMessengerCallbackDataEXT, context: ?*anyopaque) callconv(.c) vk.Bool32 {
    _ = message_type;
    _ = context;
    const message = callback_data.?.p_message.?;

    if (message_severity.error_bit_ext) {
        std.log.err("VULKAN ERROR: {s}\n", .{message});
    } else if (message_severity.warning_bit_ext) {
        std.log.warn("VULKAN WARN: {s}\n", .{message});
    } else if (message_severity.info_bit_ext) {
        std.log.info("VULKAN INFO: {s}\n", .{message});
    } else {
        std.log.info("VULKAN: {s}\n", .{message});
    }

    return .false;
}
