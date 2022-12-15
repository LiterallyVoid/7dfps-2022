layout (location = 0) in vec4 a_position;
layout (location = 1) in vec2 a_uv;
layout (location = 2) in vec4 a_color;

#include "stdlib.glsl"
#include "common-vert.glsl"

out vec2 v_uv;
out vec4 v_color;

void main() {
	gl_Position = a_position;

	v_uv = a_uv;
	v_color = a_color;
}
