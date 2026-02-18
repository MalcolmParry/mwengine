const std = @import("std");
const vk = @import("vulkan");
const gpu = @import("../../gpu.zig");
pub const Handle = @This();

sampler: vk.Sampler,

pub fn init(device: gpu.Device, info: gpu.Sampler.InitInfo) !gpu.Sampler {
    const vk_alloc: ?*vk.AllocationCallbacks = null;
    var sampler: gpu.Sampler = undefined;

    sampler.vk.sampler = try device.vk.device.createSampler(&.{
        .min_filter = filterToNative(info.min_filter),
        .mag_filter = filterToNative(info.mag_filter),
        .address_mode_u = addrModeToNative(info.address_mode_u),
        .address_mode_v = addrModeToNative(info.address_mode_v),
        .address_mode_w = addrModeToNative(info.address_mode_w),
        .border_color = .int_opaque_black,
        .anisotropy_enable = .false,
        .max_anisotropy = 0,
        .unnormalized_coordinates = .false,
        .compare_enable = .false,
        .compare_op = .always,
        .mipmap_mode = .linear,
        .mip_lod_bias = info.lod_bias,
        .min_lod = info.min_lod,
        .max_lod = if (info.max_lod) |x| x else vk.LOD_CLAMP_NONE,
    }, vk_alloc);

    return sampler;
}

pub fn deinit(sampler: gpu.Sampler, device: gpu.Device, alloc: std.mem.Allocator) void {
    _ = alloc;
    const vk_alloc: ?*vk.AllocationCallbacks = null;
    device.vk.device.destroySampler(sampler.vk.sampler, vk_alloc);
}

pub fn filterToNative(filter: gpu.Sampler.Filter) vk.Filter {
    return switch (filter) {
        .linear => .linear,
        .nearest => .nearest,
    };
}

fn addrModeToNative(addr_mode: gpu.Sampler.AddressMode) vk.SamplerAddressMode {
    return switch (addr_mode) {
        .repeat => .repeat,
        .mirror_repeat => .mirrored_repeat,
        .clamp_to_edge => .clamp_to_edge,
        .mirror_clamp_to_edge => .mirror_clamp_to_edge,
    };
}
