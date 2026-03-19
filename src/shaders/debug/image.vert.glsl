#version 450

layout(location = 0) in mat3 i_mat;
layout(location = 3) in uint i_id;

layout(location = 0) out vec2 p_uvs;
layout(location = 1) out flat uint p_id;

layout(push_constant) uniform PushConstants {
    mat4 mat;
} pc;

vec2 pos_table[6] = {
	vec2(0, 0),
	vec2(1, 0),
	vec2(1, 1),
	vec2(0, 0),
	vec2(1, 1),
	vec2(0, 1),
};

void main() {
	vec2 base_pos = pos_table[gl_VertexIndex];

	p_id = i_id;
	p_uvs = base_pos;
	vec3 pos = i_mat * vec3(base_pos, 1);
	gl_Position = pc.mat * vec4(pos.xy, 0, pos.z);
}
