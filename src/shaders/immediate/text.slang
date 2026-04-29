struct PushConstants {
    float2 image_size;
};

struct VSInput {
    [[vk::location(0)]] int4 bounds;
    [[vk::location(1)]] float4 uv_bounds;
    [[vk::location(2)]] float4 color;
    uint vert_id : SV_VulkanVertexID;
};

struct VSOutput {
    float4 position : SV_Position;
    float2 uvs : TEXCOORD0;
    float4 color : TEXCOORD1;
};

static const float2 mask_table[] = {
    { 0, 0 },
    { 1, 0 },
    { 1, 1 },
    { 0, 0 },
    { 1, 1 },
    { 0, 1 },
};

[[vk::push_constant]]
ConstantBuffer<PushConstants> pc;

[[shader("vertex")]]
VSOutput vsMain(VSInput input) {
    var mask = mask_table[input.vert_id];

    float4 bounds = input.bounds;
    float2 pos = lerp(bounds.xy, bounds.zw, mask);
    float2 pos_n = (pos / pc.image_size) * 2 - 1;
    pos_n.y *= -1;

    VSOutput o;
    o.position = float4(pos_n, 0, 1);
    o.uvs = lerp(input.uv_bounds.xy, input.uv_bounds.zw, mask);
    o.color = input.color;
    return o;
}

[[vk::binding(0, 0)]]
Sampler2D sampler;

[[shader("pixel")]]
float4 psMain(VSOutput input) : SV_Target {
    return sampler.Sample(input.uvs) * input.color;
}
