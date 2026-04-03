#version 450

layout(location = 0) in vec4 i_uv_bounds;
layout(location = 1) in ivec4 i_bounds;

layout(location = 0) out vec2 p_uvs;

layout(push_constant) uniform PushConstants {
    mat4 mat;
} pc;

vec2 masks[6] = {
    vec2(0, 0),
    vec2(1, 0),
    vec2(0, 1),
    vec2(1, 0),
    vec2(1, 1),
    vec2(0, 1),
};

void main() {
    vec2 tl = vec2(i_bounds.xy);
    vec2 br = vec2(i_bounds.zw);

    vec2 pos = mix(tl, br, masks[gl_VertexIndex]);
    gl_Position = pc.mat * vec4(pos, 0, 1);

    vec2 uv_tl = vec2(i_uv_bounds.xy);
    vec2 uv_br = vec2(i_uv_bounds.zw);

    p_uvs = mix(uv_tl, uv_br, masks[gl_VertexIndex]);
}

