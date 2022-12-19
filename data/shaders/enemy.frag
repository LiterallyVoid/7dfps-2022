#include "stdlib.glsl"

layout (location = 0) out vec4 frag_color;
layout (location = 1) out vec3 frag_normal;

in vec3 v_normal;
in vec2 v_uv;
in vec3 v_normal_camera;

uniform sampler2D u_texture;

void main() {
	float light = dot(v_normal, normalize(SUN_DIR));

	frag_color = mix(vec4(1.0, 1.0, 1.0, 1.0), vec4(1.0, 0.0, 0.0, 1.0), v_uv.x);
	frag_normal = v_normal_camera * 0.5 + 0.5;
}
