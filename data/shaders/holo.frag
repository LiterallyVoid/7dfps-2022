#include "stdlib.glsl"

layout (location = 0) out vec4 frag_color;

in vec3 v_camera_position;
in vec3 v_normal;
in vec2 v_uv;

uniform sampler2D u_texture;

void main() {
	float fresnel = clamp(dot(-v_normal, normalize(v_camera_position)), 0.0, 1.0);

	fresnel = pow(1.0 - fresnel, 3.0) * 0.7 + 0.3;

	frag_color = vec4(fresnel);

	frag_color.rgb *= vec3(0.4, 0.8, 1.2);

	frag_color.a = 0.0;
}
