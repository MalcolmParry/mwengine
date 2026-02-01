const std = @import("std");
const gpu = @import("../../gpu.zig");
const vk = @import("vulkan");

const Shader = @This();
pub const Handle = *Shader;

shader_module: vk.ShaderModule,
stage: vk.ShaderStageFlags,

pub fn fromSpirv(device: gpu.Device, stage: gpu.Shader.Stage, spirv_byte_code: []const u32, alloc: std.mem.Allocator) !gpu.Shader {
    const this = try alloc.create(Shader);
    errdefer alloc.destroy(this);
    this.stage = switch (stage) {
        .vertex => .{ .vertex_bit = true },
        .pixel => .{ .fragment_bit = true },
    };

    const vk_alloc: ?*vk.AllocationCallbacks = null;
    this.shader_module = try device.vk.device.createShaderModule(&.{
        .code_size = spirv_byte_code.len * @sizeOf(u32),
        .p_code = spirv_byte_code.ptr,
    }, vk_alloc);

    return .{ .vk = this };
}

pub fn deinit(this: gpu.Shader, device: gpu.Device, alloc: std.mem.Allocator) void {
    const vk_alloc: ?*vk.AllocationCallbacks = null;
    device.vk.device.destroyShaderModule(this.vk.shader_module, vk_alloc);
    alloc.destroy(this.vk);
}

pub fn dataTypeToNative(t: gpu.Shader.DataType) vk.Format {
    return switch (t) {
        .uint8 => .r8_uint,
        .uint8x2 => .r8g8_uint,
        .uint8x3 => .r8g8b8_uint,
        .uint8x4 => .r8g8b8a8_uint,
        .uint16 => .r16_uint,
        .uint16x2 => .r16g16_uint,
        .uint16x3 => .r16g16b16_uint,
        .uint16x4 => .r16g16b16a16_uint,
        .uint32 => .r32_uint,
        .uint32x2 => .r32g32_uint,
        .uint32x3 => .r32g32b32_uint,
        .uint32x4 => .r32g32b32a32_uint,
        .uint64 => .r64_uint,
        .uint64x2 => .r64g64_uint,
        .uint64x3 => .r64g64b64_uint,
        .uint64x4 => .r64g64b64a64_uint,
        .sint8 => .r8_sint,
        .sint8x2 => .r8g8_sint,
        .sint8x3 => .r8g8b8_sint,
        .sint8x4 => .r8g8b8a8_sint,
        .sint16 => .r16_sint,
        .sint16x2 => .r16g16_sint,
        .sint16x3 => .r16g16b16_sint,
        .sint16x4 => .r16g16b16a16_sint,
        .sint32 => .r32_sint,
        .sint32x2 => .r32g32_sint,
        .sint32x3 => .r32g32b32_sint,
        .sint32x4 => .r32g32b32a32_sint,
        .float16 => .r16_sfloat,
        .float16x2 => .r16g16_sfloat,
        .float16x3 => .r16g16b16_sfloat,
        .float16x4 => .r16g16b16a16_sfloat,
        .float32 => .r32_sfloat,
        .float32x2 => .r32g32_sfloat,
        .float32x3 => .r32g32b32_sfloat,
        .float32x4 => .r32g32b32a32_sfloat,
        .float32x4x4 => unreachable,
    };
}
