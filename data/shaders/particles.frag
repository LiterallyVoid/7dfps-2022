#include "stdlib.glsl"

layout (location = 0) out vec4 frag_color;
layout (location = 1) out vec4 frag_normal;

in vec4 v_color;
in vec2 v_uv1;
in vec2 v_uv2;

uniform sampler2D u_texture;

void main() {
	frag_color = texture(u_texture, v_uv1).a * v_color;
	frag_normal = vec4(0.0, 0.0, 0.0, 0.0);
	if (frag_color.a > 0.5) {
		frag_normal = vec4(0.5, 0.5, 0.5, 1.0);
	}
}
