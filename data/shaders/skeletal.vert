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

out vec3 v_normal;
out vec3 v_tangent;
out vec3 v_bitangent;
out vec2 v_uv;
out vec3 v_camera_to_world;
out vec3 v_normal_camera;
out vec3 v_position;

uniform mat4 u_camera_to_world;

void main() {
	mat4 matrix_bones = get_bones_matrix();

	v_normal = normalize((u_model_to_world * matrix_bones * vec4(a_normal, 0.0)).xyz);
	v_tangent = normalize((u_model_to_world * matrix_bones * vec4(a_tangent, 0.0)).xyz);
	v_bitangent = normalize((u_model_to_world * matrix_bones * vec4(a_bitangent, 0.0)).xyz);

	vec4 world_position = u_model_to_world * matrix_bones * vec4(a_position, 1.0);

	v_position = world_position.xyz;

	gl_Position = u_projection * u_world_to_camera * world_position;
	v_camera_to_world = world_position.xyz - u_camera_to_world[3].xyz;

	v_uv = a_uv;

	v_normal_camera = (u_world_to_camera * vec4(v_normal, 0.0)).xyz;
}
