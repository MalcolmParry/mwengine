#version 450
#extension GL_GOOGLE_include_directive : require

#include "core.hglsl"

layout(location = 0) toPixel vec3 pColor;

#ifdef _VERTEX

layout(location=0) in vec2 iPos;
layout(location=1) in vec3 iColor;

layout(binding = 0) uniform UniformBufferObject {
    mat4 mvp;
} ubo;

void main() {
    gl_Position = ubo.mvp * vec4(iPos, 0, 1);
    pColor = iColor;
}

#endif

#ifdef _PIXEL

layout(location = 0) out vec4 oColor;

void main() {
     oColor = vec4(pColor, 1);
}

#endif
