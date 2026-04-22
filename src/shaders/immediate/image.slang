struct PushConstants {
    float2 image_size;
    float2 pos;
    float2 size;
    float cos;
    float sin;
    float2 pivot;
};

struct VSOutput {
    float4 position : SV_Position;
    float2 uvs : TEXCOORD0;
};

static const uint corner_id_table[6] = {
    0, 1, 2, 1, 3, 2,
};

static const float2 pos_table[] = {
    { 0, 0 },
    { 1, 0 },
    { 1, 1 },
    { 0, 0 },
    { 1, 1 },
    { 0, 1 },
};

[[vk::push_constant]]
ConstantBuffer<PushConstants, Std430DataLayout> pc;

[[shader("vertex")]]
VSOutput vsMain(uint vert_id : SV_VulkanVertexID) {
    var base_pos = pos_table[vert_id];

    var result = base_pos;
    result -= pc.pivot;
    result *= pc.size;
    result = {
        result.x * pc.cos - result.y * pc.sin,
        result.x * pc.sin + result.y * pc.cos,
    };

    result += pc.pos;
    result /= pc.image_size;
    result = result * 2 - 1;
    result.y *= -1;

    VSOutput o;
    o.position = { result, 0, 1 };
    o.uvs = base_pos;
    return o;
}

[[vk::binding(0, 0)]]
Sampler2D sampler;

[[shader("pixel")]]
float4 psMain(VSOutput input) : SV_Target {
    return sampler.Sample(input.uvs);
}
