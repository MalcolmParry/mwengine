const std = @import("std");
const gpu = @import("../../gpu.zig");
const vk = @import("vulkan");
const Instance = @import("Instance.zig");
const Buffer = @import("Buffer.zig");
const CommandEncoder = @import("CommandEncoder.zig");
const Semaphore = @import("wait_objects.zig").Semaphore;

const Device = @This();
pub const Handle = *Device;

pub const required_extensions: [8][*:0]const u8 = .{
    vk.extensions.khr_synchronization_2.name,
    vk.extensions.khr_swapchain.name,
    vk.extensions.ext_swapchain_maintenance_1.name,
    vk.extensions.khr_maintenance_2.name,
    vk.extensions.khr_multiview.name,
    vk.extensions.khr_create_renderpass_2.name,
    vk.extensions.khr_depth_stencil_resolve.name,
    vk.extensions.khr_dynamic_rendering.name,
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

    var swapchain_maintenance: vk.PhysicalDeviceSwapchainMaintenance1FeaturesEXT = .{
        .swapchain_maintenance_1 = .true,
    };

    var dynamic_rendering: vk.PhysicalDeviceDynamicRenderingFeatures = .{
        .dynamic_rendering = .true,
        .p_next = @ptrCast(&swapchain_maintenance),
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

pub fn waitUntilIdle(this: gpu.Device) void {
    this.vk.device.deviceWaitIdle() catch @panic("failed to wait for device");
}

pub fn submitCommands(this: gpu.Device, info: gpu.Device.CommandSubmitInfo) gpu.Device.SubmitError!void {
    std.debug.assert(info.wait_semaphores.len == info.wait_dst_stages.len);
    var wait_dst_stage_mask_buffer: [8]vk.PipelineStageFlags = undefined;
    var wait_dst_stage_masks: std.ArrayList(vk.PipelineStageFlags) = .initBuffer(&wait_dst_stage_mask_buffer);
    for (info.wait_dst_stages) |stage| {
        wait_dst_stage_masks.appendAssumeCapacity(CommandEncoder.stageToNative(stage));
    }

    const native_fence: vk.Fence = if (info.signal_fence) |fence| fence.vk.fence else .null_handle;
    const submit_info: vk.SubmitInfo = .{
        .command_buffer_count = 1,
        .p_command_buffers = @ptrCast(&info.encoder.vk.command_buffer),
        .wait_semaphore_count = @intCast(info.wait_semaphores.len),
        .p_wait_semaphores = Semaphore.nativesFromSlice(info.wait_semaphores),
        .p_wait_dst_stage_mask = @ptrCast(wait_dst_stage_masks.items),
        .signal_semaphore_count = @intCast(info.signal_semaphores.len),
        .p_signal_semaphores = Semaphore.nativesFromSlice(info.signal_semaphores),
    };

    this.vk.device.queueSubmit(this.vk.queue, 1, @ptrCast(&submit_info), native_fence) catch |err| return switch (err) {
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

    const memory = try this.device.allocateMemory(&.{
        .allocation_size = requirements.size,
        .memory_type_index = mem_index,
    }, vk_alloc);

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
