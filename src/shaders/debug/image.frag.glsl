#version 450

layout(binding = 0) uniform sampler2DArray u_sampler;
layout(location = 0) in vec2 p_uvs;
layout(location = 1) in flat uint p_id;
layout(location = 0) out vec4 o_color;

void main() {
    o_color = texture(u_sampler, vec3(p_uvs, p_id));
}
