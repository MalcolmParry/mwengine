#version 450

layout(location = 0) in ivec4 i_pos_size;
layout(location = 1) in vec4 i_cos_sin_pivot;
layout(location = 2) in vec4 i_color;

layout(location = 0) out vec4 p_color;

layout(push_constant) uniform PushConstants {
    vec2 image_size;
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
	vec2 pivot = i_cos_sin_pivot.zw / 2 + 0.5;
	vec2 pos = vec2(i_pos_size.xy);
	vec2 size = vec2(i_pos_size.zw);
	float cos = i_cos_sin_pivot.x;
	float sin = i_cos_sin_pivot.y;
	
	vec2 result = pos_table[gl_VertexIndex];
	result -= pivot;
	result *= size;
	result = vec2(
		result.x * cos - result.y * sin,
		result.x * sin + result.y * cos
	);

	result += pos;
	result /= pc.image_size;
	result = result * 2 - 1;
	result.y *= -1;

	gl_Position = vec4(result, 0, 1);
	p_color = i_color;
}
