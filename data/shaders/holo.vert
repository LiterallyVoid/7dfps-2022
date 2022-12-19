#define SKELETAL

layout (location = 0) in vec3 a_position;
layout (location = 1) in vec3 a_normal;
layout (location = 2) in vec3 a_tangent;
layout (location = 3) in vec3 a_bitangent;
layout (location = 4) in vec2 a_uv;
layout (location = 5) in ivec4 a_bone_indices;
layout (location = 6) in vec4 a_bone_weights;

#include "stdlib.glsl"
#include "common-vert.glsl"

out vec3 v_camera_position;
out vec3 v_normal;
out vec2 v_uv;

void main() {
	mat4 matrix_bones = get_bones_matrix();

	v_normal = (u_model_to_world * matrix_bones * vec4(a_normal, 0.0)).xyz;

	vec4 world_position = u_model_to_world * matrix_bones * vec4(a_position, 1.0);

	vec4 camera_position = u_world_to_camera * world_position;
	v_camera_position = camera_position.xyz;
	camera_position.xyz *= 0.1;

	gl_Position = u_projection * camera_position;

	v_uv = a_uv;
}
