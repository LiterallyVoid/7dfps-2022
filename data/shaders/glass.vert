#include "stdlib.glsl"

layout (location = 0) in vec3 a_position;
layout (location = 1) in vec3 a_normal;
layout (location = 2) in vec2 a_uv;

out vec3 v_normal;
out vec2 v_uv;

uniform mat4 u_projection;
uniform mat4 u_world_to_camera;

void main() {
	gl_Position = u_projection * u_world_to_camera * vec4(a_position, 1.0);

	v_normal = a_normal;
	v_uv = a_uv;
}
