layout (location = 0) in vec3 a_position;
layout (location = 1) in vec3 a_normal;
layout (location = 2) in vec3 a_tangent;
layout (location = 3) in vec3 a_bitangent;
layout (location = 4) in vec2 a_uv;

#include "stdlib.glsl"
#include "common-vert.glsl"

out vec3 v_normal;
out vec3 v_tangent;
out vec3 v_bitangent;
out vec2 v_uv;
out vec3 v_camera_to_world;
out vec3 v_normal_camera;
out vec3 v_position;

uniform mat4 u_projection;
uniform mat4 u_world_to_camera;
uniform mat4 u_camera_to_world;

void main() {
	gl_Position = u_projection * u_world_to_camera * vec4(a_position, 1.0);
	v_position = a_position;

	v_camera_to_world = a_position - u_camera_to_world[3].xyz;

	v_normal = a_normal;
	v_tangent = normalize(a_tangent);
	v_bitangent = normalize(a_bitangent);

	v_uv = a_uv;

	v_normal_camera = (u_world_to_camera * vec4(v_normal, 0.0)).xyz;
}
