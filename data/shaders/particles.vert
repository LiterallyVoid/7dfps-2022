
layout (location = 0) in vec3 a_position;
layout (location = 1) in vec4 a_color;
layout (location = 2) in vec2 a_uv1;
layout (location = 3) in vec2 a_uv2;

#include "stdlib.glsl"
#include "common-vert.glsl"

out vec4 v_color;
out vec2 v_uv1;
out vec2 v_uv2;

uniform mat4 u_projection;
uniform mat4 u_world_to_camera;

void main() {
	gl_Position = u_projection * u_world_to_camera * vec4(a_position, 1.0);

	v_color = a_color;
	v_uv1 = a_uv1;
	v_uv2 = a_uv2;
}
