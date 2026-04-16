struct PushConstants {
    float2 image_size;
};

struct VSInput {
    [[vk::location(0)]] int4 packed_pos_size;
    [[vk::location(1)]] float4 packed_cos_sin_pivot;
    [[vk::location(2)]] float4 color;
    uint vert_id : SV_VulkanVertexID;
};

struct VSOutput {
    float4 position : SV_Position;
    float4 color : TEXCOORD0;
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
ConstantBuffer<PushConstants> pc;

[[shader("vertex")]]
VSOutput vsMain(VSInput input) {
    var pivot = input.packed_cos_sin_pivot.zw / 2 + 0.5;
    var pos = input.packed_pos_size.xy;
    var size = input.packed_pos_size.zw;
    var cos = input.packed_cos_sin_pivot.x;
    var sin = input.packed_cos_sin_pivot.y;

    var result = pos_table[input.vert_id];
    result -= pivot;
    result *= size;
    result = {
        result.x * cos - result.y * sin,
        result.x * sin + result.y * cos,
    };

    result += pos;
    result /= pc.image_size;
    result = result * 2 - 1;
    result.y *= -1;

    VSOutput o;
    o.position = { result, 0, 1 };
    o.color = input.color;
    return o;
}

[[shader("pixel")]]
float4 psMain(VSOutput input) : SV_Target {
    return input.color;
}
