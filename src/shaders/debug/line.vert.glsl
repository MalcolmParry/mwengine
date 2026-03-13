#version 450

layout(location = 0) in vec2 i_pos;
layout(location = 1) in vec2 i_dir;
layout(location = 2) in float i_length;
layout(location = 3) in float i_width;

layout(push_constant) uniform PushConstants {
    mat4 mat;
} pc;

float right_table[6] = {
	-0.5, 0.5, -0.5, 0.5, 0.5, -0.5
};

float end_table[6] = {
	0, 0, 1, 0, 1, 1
};

void main() {
	vec2 right = vec2(
		i_dir.y,
		-i_dir.x
	);
	vec2 pos = i_pos + end_table[gl_VertexIndex] * i_dir * i_length + right_table[gl_VertexIndex] * right * i_width;

	gl_Position = pc.mat * vec4(pos, 0, 1);
}
