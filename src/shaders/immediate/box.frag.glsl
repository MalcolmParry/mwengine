#version 450

layout(location = 0) out vec4 o_color;
layout(location = 0) in vec4 p_color;

void main() {
	o_color = p_color;
}
