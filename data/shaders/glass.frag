#include "stdlib.glsl"

layout (location = 0) out vec4 frag_color;

in vec3 v_normal;
in vec2 v_uv;

uniform sampler2D u_texture;

void main() {
	float light = dot(v_normal, normalize(vec3(0.15, 0.4, 1.0))) * 0.5 + 0.5;

	frag_color = texture(u_texture, v_uv);
	frag_color.rgb *= light;

	frag_color *= 0.6;
}
