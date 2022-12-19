#include "stdlib.glsl"

#include "shading.glsl"

layout (location = 0) out vec4 frag_color;
layout (location = 1) out vec3 frag_normal;

in vec3 v_position;
in vec3 v_camera_to_world;
in vec3 v_normal;
in vec3 v_tangent;
in vec3 v_bitangent;
in vec2 v_uv;
in vec3 v_normal_camera;

void main() {
	frag_color = shade(v_position, v_camera_to_world, mat3(v_tangent, v_bitangent, v_normal), v_uv);
	frag_normal = v_normal_camera * 0.5 + 0.5;
}
