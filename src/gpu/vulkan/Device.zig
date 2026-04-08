const std = @import("std");
const gpu = @import("../gpu.zig");
const vk = @import("vulkan");
const Instance = @import("Instance.zig");
const Buffer = @import("Buffer.zig");
const CommandEncoder = @import("CommandEncoder.zig");

const Device = @This();
pub const Handle = *Device;

pub const required_extensions: [8][*:0]const u8 = .{
    vk.extensions.khr_synchronization_2.name,
    vk.extensions.khr_swapchain.name,
    vk.extensions.khr_maintenance_2.name,
    vk.extensions.khr_multiview.name,
    vk.extensions.khr_create_renderpass_2.name,
    vk.extensions.khr_depth_stencil_resolve.name,
    vk.extensions.khr_dynamic_rendering.name,
    vk.extensions.khr_timeline_semaphore.name,
};

pub const Physical = struct {
    pub const Handle = Physical;

    device: vk.PhysicalDevice,
};

pub const Size = u64;

instance: *Instance,
phys: vk.PhysicalDevice,
device: vk.DeviceProxy,
queue: vk.Queue,
queue_family_index: u32,
command_pool: vk.CommandPool,

pub fn init(instance: gpu.Instance, physical_device: gpu.Device.Physical, alloc: std.mem.Allocator) gpu.Device.InitError!gpu.Device {
    const this = try alloc.create(Device);
    errdefer alloc.destroy(this);
    this.instance = instance.vk;
    this.phys = physical_device.vk.device;

    const vk_alloc: ?*vk.AllocationCallbacks = null;
    const queue_priority: f32 = 1;
    this.queue_family_index = blk: {
        const queue_familes = try instance.vk.instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(this.phys, alloc);
        defer alloc.free(queue_familes);

        for (queue_familes, 0..) |prop, i| {
            if (prop.queue_flags.graphics_bit and prop.queue_flags.transfer_bit)
                break :blk @intCast(i);
        }

        return error.NoSuitableQueue;
    };

    const queue_create_info: vk.DeviceQueueCreateInfo = .{
        .queue_family_index = this.queue_family_index,
        .queue_count = 1,
        .p_queue_priorities = @ptrCast(&queue_priority),
    };

    var timeline_semaphore: vk.PhysicalDeviceTimelineSemaphoreFeatures = .{
        .timeline_semaphore = .true,
    };

    var indexing: vk.PhysicalDeviceDescriptorIndexingFeatures = .{
        .descriptor_binding_partially_bound = .true,
        .p_next = @ptrCast(&timeline_semaphore),
    };

    var dynamic_rendering: vk.PhysicalDeviceDynamicRenderingFeatures = .{
        .dynamic_rendering = .true,
        .p_next = @ptrCast(&indexing),
    };

    var sync2: vk.PhysicalDeviceSynchronization2Features = .{
        .synchronization_2 = .true,
        .p_next = @ptrCast(&dynamic_rendering),
    };

    // TODO: check extention support
    const device_handle = instance.vk.instance.createDevice(this.phys, &.{
        .p_queue_create_infos = @ptrCast(&queue_create_info),
        .queue_create_info_count = 1,
        .enabled_extension_count = required_extensions.len,
        .pp_enabled_extension_names = &required_extensions,
        .p_next = &vk.PhysicalDeviceFeatures2{
            .features = .{
                .sampler_anisotropy = .true,
                .fill_mode_non_solid = .true,
                .shader_int_64 = .true,
            },
            .p_next = &sync2,
        },
    }, vk_alloc) catch |err| return switch (err) {
        error.OutOfHostMemory => error.OutOfMemory,
        error.OutOfDeviceMemory => error.OutOfDeviceMemory,
        error.ExtensionNotPresent, error.FeatureNotPresent => error.NotSupported,
        error.InitializationFailed, error.TooManyObjects, error.DeviceLost => error.InitFailed,
        error.Unknown => error.Unknown,
    };

    const device_wrapper = try alloc.create(vk.DeviceWrapper);
    errdefer alloc.destroy(device_wrapper);
    device_wrapper.* = .load(device_handle, instance.vk.instance.wrapper.dispatch.vkGetDeviceProcAddr orelse return error.Unknown);
    this.device = vk.DeviceProxy.init(device_handle, device_wrapper);
    errdefer this.device.destroyDevice(vk_alloc);

    this.queue = this.device.getDeviceQueue(this.queue_family_index, 0);
    this.command_pool = this.device.createCommandPool(&.{
        .queue_family_index = this.queue_family_index,
        .flags = .{
            .reset_command_buffer_bit = true,
        },
    }, vk_alloc) catch |err| return switch (err) {
        error.OutOfHostMemory => error.OutOfMemory,
        error.OutOfDeviceMemory => error.OutOfDeviceMemory,
        error.Unknown => error.Unknown,
    };

    errdefer this.device.destroyCommandPool(this.command_pool, vk_alloc);

    return .{ .vk = this };
}

pub fn deinit(this: gpu.Device, alloc: std.mem.Allocator) void {
    const vk_alloc: ?*vk.AllocationCallbacks = null;
    this.vk.device.destroyCommandPool(this.vk.command_pool, vk_alloc);
    this.vk.device.destroyDevice(vk_alloc);
    alloc.destroy(this.vk.device.wrapper);
    alloc.destroy(this.vk);
}

pub fn waitUntilIdle(this: gpu.Device) gpu.Device.WaitIdleError!void {
    this.vk.device.deviceWaitIdle() catch |err| return switch (err) {
        error.DeviceLost => error.DeviceLost,
        error.OutOfHostMemory => error.OutOfMemory,
        error.OutOfDeviceMemory => error.OutOfDeviceMemory,
        error.Unknown => error.Unknown,
    };
}

fn getNativeSemaphoreSubmitInfos(
    buffer: []vk.SemaphoreSubmitInfo,
    timeline_points: []const gpu.Timeline.Point,
    display_image_syncs: []const gpu.Device.CommandSubmitInfo.DisplayImageSync,
    kind: enum { wait, signal },
) void {
    std.debug.assert(timeline_points.len + display_image_syncs.len <= buffer.len);

    for (timeline_points, 0..) |point, i| {
        buffer[i] = .{
            .semaphore = point.timeline.vk.semaphore,
            .value = point.value,
            .stage_mask = CommandEncoder.stageToNative(point.stages),
            .device_index = 0,
        };
    }

    for (display_image_syncs, timeline_points.len..) |sync, i| {
        buffer[i] = .{
            .semaphore = switch (kind) {
                .wait => sync.image.vk.available_semaphore,
                .signal => sync.display.vk.presentable_semaphores[sync.image.vk.index],
            },
            .value = 0,
            .stage_mask = CommandEncoder.stageToNative(sync.stages),
            .device_index = 0,
        };
    }
}

// TODO: update to new submit format
pub fn submitCommands(this: gpu.Device, info: gpu.Device.CommandSubmitInfo) gpu.Device.SubmitError!void {
    const max_semaphores = 16;

    const wait_count = info.waits.len + info.display_acquire_waits.len;
    var native_waits: [max_semaphores]vk.SemaphoreSubmitInfo = undefined;
    getNativeSemaphoreSubmitInfos(&native_waits, info.waits, info.display_acquire_waits, .wait);

    const signal_count = info.signals.len + info.display_present_signals.len;
    var native_signals: [max_semaphores]vk.SemaphoreSubmitInfo = undefined;
    getNativeSemaphoreSubmitInfos(&native_signals, info.signals, info.display_present_signals, .signal);

    const command_buffer_info: vk.CommandBufferSubmitInfo = .{
        .command_buffer = info.encoder.vk.command_buffer,
        .device_mask = 1,
    };

    const submit_info: vk.SubmitInfo2 = .{
        .command_buffer_info_count = 1,
        .p_command_buffer_infos = @ptrCast(&command_buffer_info),
        .wait_semaphore_info_count = @intCast(wait_count),
        .p_wait_semaphore_infos = @ptrCast(&native_waits),
        .signal_semaphore_info_count = @intCast(signal_count),
        .p_signal_semaphore_infos = @ptrCast(&native_signals),
    };

    this.vk.device.queueSubmit2KHR(this.vk.queue, 1, @ptrCast(&submit_info), .null_handle) catch |err| return switch (err) {
        error.DeviceLost => error.DeviceLost,
        error.OutOfHostMemory => error.OutOfMemory,
        error.OutOfDeviceMemory => error.OutOfDeviceMemory,
        error.Unknown => error.Unknown,
    };
}

pub const MemoryRegion = struct {
    memory: vk.DeviceMemory,
    offset: Size,
    size: Size,
};

pub fn allocateMemory(this: *Device, requirements: vk.MemoryRequirements, properties: vk.MemoryPropertyFlags) !MemoryRegion {
    const vk_alloc: ?*vk.AllocationCallbacks = null;
    const mem_index: u32 = blk: {
        const mem_properties = this.instance.instance.getPhysicalDeviceMemoryProperties(this.phys);
        for (mem_properties.memory_types[0..mem_properties.memory_type_count], 0..) |mem_type, i| {
            const mem_type_bit = @as(Size, 1) << @intCast(i);
            if (mem_type_bit & requirements.memory_type_bits == 0) continue;
            if (!mem_type.property_flags.contains(properties)) continue;
            break :blk @intCast(i);
        }

        return error.NoSuitableMemoryType;
    };

    const memory = this.device.allocateMemory(&.{
        .allocation_size = requirements.size,
        .memory_type_index = mem_index,
    }, vk_alloc) catch |err| return switch (err) {
        error.OutOfHostMemory => error.OutOfMemory,
        error.OutOfDeviceMemory => error.OutOfDeviceMemory,
        // only happens with buffer device address
        error.InvalidOpaqueCaptureAddressKHR => unreachable,
        // only happens with extensions in pnext
        error.InvalidExternalHandle => unreachable,
        error.Unknown => error.Unknown,
    };

    return .{
        .memory = memory,
        .offset = 0,
        .size = requirements.size,
    };
}

pub fn freeMemory(this: *Device, memory_region: MemoryRegion) void {
    const vk_alloc: ?*vk.AllocationCallbacks = null;
    this.device.freeMemory(memory_region.memory, vk_alloc);
}
