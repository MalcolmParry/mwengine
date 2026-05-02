struct PushConstants {
    float2 image_size;
};

struct VSInput {
    [[vk::location(0)]] int4 bounds;
    [[vk::location(1)]] float4 uv_bounds;
    [[vk::location(2)]] float4 color;
    [[vk::location(3)]] float4 outline_color;
    // 5.3 fractional pixels
    [[vk::location(4)]] uint outline_width;
    uint vert_id : SV_VulkanVertexID;
};

struct VSOutput {
    float4 position : SV_Position;
    float2 uvs : TEXCOORD0;
    nointerpolation float4 color : TEXCOORD1;
    nointerpolation float4 outline_color: TEXCOORD2;
    nointerpolation float outline_width: TEXCOORD3;
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
    o.outline_color = input.outline_color;
    o.outline_width = input.outline_width;
    return o;
}

[[vk::binding(0, 0)]]
Sampler2D sampler;

[[shader("pixel")]]
float4 psMain(VSOutput input) : SV_Target {
    float spread = 16;
    float fill_bias = 0;
    float4 fill_color = input.color;
    float4 outline_color = input.outline_color;

    float raw = sampler.Sample(input.uvs).r;
    float sd = raw * 2 - 1;
    float sd_px = sd * spread;
    float aa = max(fwidth(sd_px), 1e-5);
    float outline_width = float(input.outline_width) / (1 << 3);

    float fill_alpha = smoothstep(-aa - fill_bias, aa - fill_bias, sd_px);
    float outline_alpha = smoothstep(-outline_width - aa, -outline_width + aa, sd_px);
    float ring_alpha = saturate(outline_alpha - fill_alpha);

    float3 color = fill_color.rgb * fill_alpha + outline_color.rgb * ring_alpha;
    float alpha = saturate(fill_alpha * fill_color.a + ring_alpha * outline_color.a);

    return float4(color, alpha);
}
