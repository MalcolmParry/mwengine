const std = @import("std");
const gpu = @import("../../gpu.zig");
const vk = @import("vulkan");

const Shader = @This();

_shader_module: vk.ShaderModule,
_stage: vk.ShaderStageFlags,

pub fn fromSpirv(device: gpu.Device, stage: Stage, spirvByteCode: []const u32) !@This() {
    const vk_alloc: ?*vk.AllocationCallbacks = null;
    const shader_module = try device.vk.device.createShaderModule(&.{
        .code_size = spirvByteCode.len * @sizeOf(u32),
        .p_code = spirvByteCode.ptr,
    }, vk_alloc);

    return .{
        ._shader_module = shader_module,
        ._stage = switch (stage) {
            .vertex => .{ .vertex_bit = true },
            .pixel => .{ .fragment_bit = true },
        },
    };
}

pub fn deinit(this: *@This(), device: gpu.Device) void {
    const vk_alloc: ?*vk.AllocationCallbacks = null;
    device.vk.device.destroyShaderModule(this._shader_module, vk_alloc);
}

pub const Stage = enum {
    vertex,
    pixel,
};

pub const StageFlags = packed struct {
    vertex: bool = false,
    pixel: bool = false,
};

pub const Set = struct {
    vertex: Shader,
    pixel: Shader,
    _per_vertex: []const vk.Format,

    pub fn init(vertex: Shader, pixel: Shader, per_vertex: []const DataType, alloc: std.mem.Allocator) !@This() {
        std.debug.assert(vertex._stage.vertex_bit);
        std.debug.assert(pixel._stage.fragment_bit);

        return .{
            .vertex = vertex,
            .pixel = pixel,
            ._per_vertex = try _shaderDataTypeToVk(per_vertex, alloc),
        };
    }

    pub fn deinit(this: *@This(), alloc: std.mem.Allocator) void {
        alloc.free(this._per_vertex);
    }
};

pub const DataType = enum {
    uint8,
    uint8x2,
    uint8x3,
    uint8x4,
    uint16,
    uint16x2,
    uint16x3,
    uint16x4,
    uint32,
    uint32x2,
    uint32x3,
    uint32x4,
    sint8,
    sint8x2,
    sint8x3,
    sint8x4,
    sint16,
    sint16x2,
    sint16x3,
    sint16x4,
    sint32,
    sint32x2,
    sint32x3,
    sint32x4,
    float16,
    float16x2,
    float16x3,
    float16x4,
    float32,
    float32x2,
    float32x3,
    float32x4,
    float32x4x4,

    pub fn size(this: @This()) usize {
        return switch (this) {
            .uint8 => 1,
            .uint8x2 => 2,
            .uint8x3 => 3,
            .uint8x4 => 4,
            .uint16 => 2,
            .uint16x2 => 4,
            .uint16x3 => 6,
            .uint16x4 => 8,
            .uint32 => 4,
            .uint32x2 => 8,
            .uint32x3 => 12,
            .uint32x4 => 16,
            .uint64 => 8,
            .uint64x2 => 16,
            .uint64x3 => 24,
            .uint64x4 => 32,
            .sint8 => 1,
            .sint8x2 => 2,
            .sint8x3 => 3,
            .sint8x4 => 4,
            .sint16 => 2,
            .sint16x2 => 4,
            .sint16x3 => 6,
            .sint16x4 => 8,
            .sint32 => 4,
            .sint32x2 => 8,
            .sint32x3 => 12,
            .sint32x4 => 16,
            .float32 => 4,
            .float32x2 => 8,
            .float32x3 => 12,
            .float32x4 => 16,
            .float32x4x4 => 64,
        };
    }
};

fn _shaderDataTypeToVk(types: []const DataType, alloc: std.mem.Allocator) ![]vk.Format {
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

pub fn _vkTypeSize(t: vk.Format) gpu.Size {
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
