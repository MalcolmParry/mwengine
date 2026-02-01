const std = @import("std");
const gpu = @import("../../gpu.zig");
const vk = @import("vulkan");
const Device = @import("Device.zig");
const Window = @import("../../Window.zig");

const Instance = @This();
pub const Handle = *Instance;

const extra_required_extensions: [3][*:0]const u8 = .{
    vk.extensions.khr_get_surface_capabilities_2.name,
    vk.extensions.ext_surface_maintenance_1.name,
    vk.extensions.khr_get_physical_device_properties_2.name,
};

const validation_layer: [1][*:0]const u8 = .{"VK_LAYER_KHRONOS_validation"};
const debug_extensions: [1][*:0]const u8 = .{
    vk.extensions.ext_debug_utils.name,
};

platform_wrapper: Window.vulkan.Wrapper,
instance: vk.InstanceProxy,
maybe_debug_messenger: ?vk.DebugUtilsMessengerEXT,
physical_devices: []Device.Physical,

//  TODO: add app version to paramerers
pub fn init(debug_logging: bool, alloc: std.mem.Allocator) !gpu.Instance {
    const this = try alloc.create(Instance);
    errdefer alloc.destroy(this);

    const vk_alloc: ?*vk.AllocationCallbacks = null;
    this.platform_wrapper = try Window.vulkan.Wrapper.init();
    const vkb = try this.platform_wrapper.getBaseWrapper();

    // TODO: check extention support
    var extensions: std.ArrayList([*:0]const u8) = .empty;
    defer extensions.deinit(alloc);
    try extensions.appendSlice(alloc, try Window.vulkan.getRequiredInstanceExtensions());
    try extensions.appendSlice(alloc, &extra_required_extensions);
    if (debug_logging) try extensions.appendSlice(alloc, &debug_extensions);

    const layers: []const [*:0]const u8 = if (debug_logging) &validation_layer else &.{};

    const instance_handle = try vkb.createInstance(&.{
        .p_application_info = &.{
            .p_application_name = "placeholder",
            .application_version = 0,
            .p_engine_name = "placeholder",
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
    instance_wrapper.* = .load(instance_handle, vkb.dispatch.vkGetInstanceProcAddr orelse return error.CantLoadVulkan);
    this.instance = .init(instance_handle, instance_wrapper);
    errdefer this.instance.destroyInstance(vk_alloc);

    this.maybe_debug_messenger = if (debug_logging) blk: {
        break :blk try this.instance.createDebugUtilsMessengerEXT(&.{
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

    errdefer if (this.maybe_debug_messenger) |debug_messenger|
        this.instance.destroyDebugUtilsMessengerEXT(debug_messenger, vk_alloc);

    const native_phyical_devices = try this.instance.enumeratePhysicalDevicesAlloc(alloc);
    defer alloc.free(native_phyical_devices);
    this.physical_devices = try alloc.alloc(Device.Physical, native_phyical_devices.len);
    errdefer alloc.free(this.physical_devices);

    for (this.physical_devices, native_phyical_devices) |*phys_dev, native| {
        phys_dev.* = .{ .device = native };

        const queue_families = try this.instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(native, alloc);
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
    }
    std.debug.print("\n", .{});

    return .{ .vk = this };
}

pub fn deinit(this: gpu.Instance, alloc: std.mem.Allocator) void {
    const vk_alloc: ?*vk.AllocationCallbacks = null;
    alloc.free(this.vk.physical_devices);
    if (this.vk.maybe_debug_messenger) |debug_messenger|
        this.vk.instance.destroyDebugUtilsMessengerEXT(debug_messenger, vk_alloc);
    this.vk.instance.destroyInstance(vk_alloc);
    alloc.destroy(this.vk.instance.wrapper);
    this.vk.platform_wrapper.deinit();
    alloc.destroy(this.vk);
}

pub fn bestPhysicalDevice(this: gpu.Instance) !gpu.Device.Physical {
    var best_device: ?Device.Physical = null;
    var best_score: i32 = -1;
    for (this.vk.physical_devices) |device| {
        const native = device.device;
        const features = this.vk.instance.getPhysicalDeviceFeatures(native);
        const properties = this.vk.instance.getPhysicalDeviceProperties(native);
        _ = features;

        var score: i32 = 0;

        if (properties.device_type == .discrete_gpu) {
            score += 1000;
        }

        score += @intCast(properties.limits.max_image_dimension_2d);

        std.log.info("Device ({}): {s}", .{ score, properties.device_name });
        std.log.info("Max Image: {}", .{properties.limits.max_image_dimension_2d});
        std.log.info("Max Push Constant Size: {}", .{properties.limits.max_push_constants_size});

        if (score > best_score) {
            best_score = score;
            best_device = device;
        }
    }

    if (best_score == -1) best_device = null;
    const properties = this.vk.instance.getPhysicalDeviceProperties(best_device.?.device);
    std.log.info("{s}\n", .{properties.device_name});
    return .{
        .vk = best_device orelse return error.NoDeviceAvailable,
    };
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
