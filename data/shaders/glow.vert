#include "stdlib.glsl"
#include "common-vert.glsl"

out vec3 v_normal;
out vec2 v_uv;

void main() {
	mat4 matrix_bones = get_bones_matrix();

	v_normal = (u_model_to_world * matrix_bones * vec4(a_normal, 0.0)).xyz;

	vec4 world_position = u_model_to_world * matrix_bones * vec4(a_position, 1.0);

	gl_Position = u_projection * u_world_to_camera * world_position;

	v_uv = a_uv;
}
