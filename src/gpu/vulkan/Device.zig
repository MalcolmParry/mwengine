const std = @import("std");
const tracy = @import("tracy");
const vk = @import("vulkan");
const Instance = @import("Instance.zig");
const Display = @import("Display.zig");
const Buffer = @import("Buffer.zig");
const ResourceSet = @import("ResourceSet.zig");
const wait_objects = @import("wait_objects.zig");
const Framebuffer = @import("Framebuffer.zig");
const CommandBuffer = @import("CommandBuffer.zig");

pub const required_extensions: [3][*:0]const u8 = .{
    vk.extensions.khr_swapchain.name,
    vk.extensions.ext_swapchain_maintenance_1.name,
    vk.extensions.ext_index_type_uint_8.name,
};

pub const Physical = struct {
    _device: vk.PhysicalDevice,
};

pub const Size = u64;

instance: *Instance,
_phys: vk.PhysicalDevice,
_device: vk.DeviceProxy,
_queue: vk.Queue,
_queue_family_index: u32,
_command_pool: vk.CommandPool,

pub fn init(instance: *Instance, physical_device: *const Physical, alloc: std.mem.Allocator) !@This() {
    const zone = tracy.Zone.begin(.{
        .src = @src(),
    });
    defer zone.end();

    const vk_alloc: ?*vk.AllocationCallbacks = null;
    const queue_priority: f32 = 1;
    const queue_family_index: u32 = blk: {
        const queue_familes = try instance._instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(physical_device._device, alloc);
        defer alloc.free(queue_familes);

        for (queue_familes, 0..) |prop, i| {
            if (prop.queue_flags.graphics_bit and prop.queue_flags.transfer_bit)
                break :blk @intCast(i);
        }

        return error.NoSuitableQueue;
    };

    const queue_create_info: vk.DeviceQueueCreateInfo = .{
        .queue_family_index = queue_family_index,
        .queue_count = 1,
        .p_queue_priorities = @ptrCast(&queue_priority),
    };

    var index_type_uint8: vk.PhysicalDeviceIndexTypeUint8FeaturesEXT = .{
        .index_type_uint_8 = .true,
    };

    var swapchain_maintenance: vk.PhysicalDeviceSwapchainMaintenance1FeaturesEXT = .{
        .swapchain_maintenance_1 = .true,
        .p_next = @ptrCast(&index_type_uint8),
    };

    // TODO: check extention support
    const device_handle = try instance._instance.createDevice(physical_device._device, &.{
        .p_queue_create_infos = @ptrCast(&queue_create_info),
        .queue_create_info_count = 1,
        .enabled_extension_count = required_extensions.len,
        .pp_enabled_extension_names = &required_extensions,
        .p_next = &vk.PhysicalDeviceFeatures2{
            .features = .{
                .sampler_anisotropy = .true,
            },
            .p_next = &swapchain_maintenance,
        },
    }, vk_alloc);

    const device_wrapper = try alloc.create(vk.DeviceWrapper);
    errdefer alloc.destroy(device_wrapper);
    device_wrapper.* = .load(device_handle, instance._instance.wrapper.dispatch.vkGetDeviceProcAddr orelse return error.CantLoadVulkan);
    const device = vk.DeviceProxy.init(device_handle, device_wrapper);
    errdefer device.destroyDevice(vk_alloc);

    const queue = device.getDeviceQueue(queue_family_index, 0);
    const command_pool = try device.createCommandPool(&.{
        .queue_family_index = queue_family_index,
        .flags = .{
            .reset_command_buffer_bit = true,
        },
    }, vk_alloc);

    return .{
        ._phys = physical_device._device,
        ._device = device,
        ._queue = queue,
        ._queue_family_index = queue_family_index,
        ._command_pool = command_pool,
        .instance = instance,
    };
}

pub fn deinit(this: *@This(), alloc: std.mem.Allocator) void {
    const zone = tracy.Zone.begin(.{
        .src = @src(),
    });
    defer zone.end();

    const vk_alloc: ?*vk.AllocationCallbacks = null;
    this._device.destroyCommandPool(this._command_pool, vk_alloc);
    this._device.destroyDevice(vk_alloc);
    alloc.destroy(this._device.wrapper);
}

pub fn waitUntilIdle(this: *const @This()) !void {
    try this._device.deviceWaitIdle();
}

pub const initDisplay = Display.init;
pub const initBuffer = Buffer.init;
pub const initResouceLayout = ResourceSet.Layout.init;
pub const initResouceSet = ResourceSet.init;
pub const initCommandBuffer = CommandBuffer.init;
pub const initFramebuffer = Framebuffer.init;
pub const initSemaphore = wait_objects.Semaphore.init;
pub const initFence = wait_objects.Fence.init;

pub const _MemoryRegion = struct {
    memory: vk.DeviceMemory,
    offset: Size,
    size: Size,
};

pub fn _allocateMemory(this: *@This(), requirements: vk.MemoryRequirements, properties: vk.MemoryPropertyFlags) !_MemoryRegion {
    const vk_alloc: ?*vk.AllocationCallbacks = null;
    const mem_index: u32 = blk: {
        const mem_properties = this.instance._instance.getPhysicalDeviceMemoryProperties(this._phys);
        for (mem_properties.memory_types[0..mem_properties.memory_type_count], 0..) |mem_type, i| {
            const mem_type_bit = @as(Size, 1) << @intCast(i);
            if (mem_type_bit & requirements.memory_type_bits == 0) continue;
            if (!mem_type.property_flags.contains(properties)) continue;
            break :blk @intCast(i);
        }

        return error.NoSuitableMemoryType;
    };

    const memory = try this._device.allocateMemory(&.{
        .allocation_size = requirements.size,
        .memory_type_index = mem_index,
    }, vk_alloc);

    return .{
        .memory = memory,
        .offset = 0,
        .size = requirements.size,
    };
}

pub fn _freeMemory(this: *@This(), memory_region: _MemoryRegion) void {
    const vk_alloc: ?*vk.AllocationCallbacks = null;
    this._device.freeMemory(memory_region.memory, vk_alloc);
}
