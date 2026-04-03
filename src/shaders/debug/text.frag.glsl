#version 450

layout(binding = 0) uniform sampler2D u_sampler;
layout(location = 0) in vec2 p_uvs;
layout(location = 0) out vec4 o_color;

void main() {
    o_color = texture(u_sampler, p_uvs);
    // o_color = vec4(0, 0, 0, 1);
}
