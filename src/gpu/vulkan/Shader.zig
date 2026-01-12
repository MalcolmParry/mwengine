const std = @import("std");
const gpu = @import("../../gpu.zig");
const vk = @import("vulkan");

const Shader = @This();
pub const Handle = *Shader;

shader_module: vk.ShaderModule,
stage: vk.ShaderStageFlags,

pub fn fromSpirv(device: gpu.Device, stage: gpu.Shader.Stage, spirvByteCode: []const u32, alloc: std.mem.Allocator) !gpu.Shader {
    const this = try alloc.create(Shader);
    errdefer alloc.destroy(this);
    this.stage = switch (stage) {
        .vertex => .{ .vertex_bit = true },
        .pixel => .{ .fragment_bit = true },
    };

    const vk_alloc: ?*vk.AllocationCallbacks = null;
    this.shader_module = try device.vk.device.createShaderModule(&.{
        .code_size = spirvByteCode.len * @sizeOf(u32),
        .p_code = spirvByteCode.ptr,
    }, vk_alloc);

    return .{ .vk = this };
}

pub fn deinit(this: gpu.Shader, device: gpu.Device, alloc: std.mem.Allocator) void {
    const vk_alloc: ?*vk.AllocationCallbacks = null;
    device.vk.device.destroyShaderModule(this.vk.shader_module, vk_alloc);
    alloc.destroy(this.vk);
}

pub const Set = struct {
    pub const Handle = *Set;

    vertex: gpu.Shader,
    pixel: gpu.Shader,
    per_vertex: []const vk.Format,

    pub fn init(_: gpu.Device, vertex: gpu.Shader, pixel: gpu.Shader, per_vertex: []const gpu.Shader.DataType, alloc: std.mem.Allocator) !gpu.Shader.Set {
        std.debug.assert(vertex.vk.stage.vertex_bit);
        std.debug.assert(pixel.vk.stage.fragment_bit);

        const this = try alloc.create(Set);
        errdefer alloc.destroy(this);
        this.per_vertex = try shaderDataTypeToVk(per_vertex, alloc);
        this.vertex = vertex;
        this.pixel = pixel;

        return .{ .vk = this };
    }

    pub fn deinit(this: gpu.Shader.Set, _: gpu.Device, alloc: std.mem.Allocator) void {
        alloc.free(this.vk.per_vertex);
        alloc.destroy(this.vk);
    }
};

fn shaderDataTypeToVk(types: []const gpu.Shader.DataType, alloc: std.mem.Allocator) ![]vk.Format {
    var count: u32 = 0;

    for (types) |x| {
        switch (x) {
            .float32x4x4 => {
                count += 4;
            },
            else => {
                count += 1;
            },
        }
    }

    const vk_types = try alloc.alloc(vk.Format, count);
    var i: u32 = 0;
    for (types) |t| {
        if (t == .float32x4x4) {
            vk_types[i + 0] = .r32g32b32a32_sfloat;
            vk_types[i + 1] = .r32g32b32a32_sfloat;
            vk_types[i + 2] = .r32g32b32a32_sfloat;
            vk_types[i + 3] = .r32g32b32a32_sfloat;
            i += 4;
            continue;
        }

        vk_types[i] = switch (t) {
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

        i += 1;
    }

    return vk_types;
}

pub fn vkTypeSize(t: vk.Format) gpu.Size {
    return switch (t) {
        .r8_uint => 1,
        .r8g8_uint => 2,
        .r8g8b8_uint => 3,
        .r8g8b8a8_uint => 4,
        .r16_uint => 2,
        .r16g16_uint => 4,
        .r16g16b16_uint => 6,
        .r16g16b16a16_uint => 8,
        .r32_uint => 4,
        .r32g32_uint => 8,
        .r32g32b32_uint => 12,
        .r32g32b32a32_uint => 16,
        .r8_sint => 1,
        .r8g8_sint => 2,
        .r8g8b8_sint => 3,
        .r8g8b8a8_sint => 4,
        .r16_sint => 2,
        .r16g16_sint => 4,
        .r16g16b16_sint => 6,
        .r16g16b16a16_sint => 8,
        .r32_sint => 4,
        .r32g32_sint => 8,
        .r32g32b32_sint => 12,
        .r32g32b32a32_sint => 16,
        .r16_sfloat => 2,
        .r16g16_sfloat => 4,
        .r16g16b16_sfloat => 6,
        .r16g16b16a16_sfloat => 8,
        .r32_sfloat => 4,
        .r32g32_sfloat => 8,
        .r32g32b32_sfloat => 12,
        .r32g32b32a32_sfloat => 16,
        else => unreachable,
    };
}
