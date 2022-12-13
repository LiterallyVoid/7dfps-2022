#include "stdlib.glsl"

layout (location = 0) out vec4 frag_color;

in vec3 v_normal;
in vec2 v_uv;

uniform sampler2D u_texture;

void main() {
	frag_color = texture(u_texture, v_uv);
	frag_color.rgb *= frag_color.a * 2.5;

	frag_color.a *= 0.4;
	frag_color.a += 0.6;
}
