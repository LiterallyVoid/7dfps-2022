#include "stdlib.glsl"

layout (location = 0) out vec4 frag_color;

in vec4 v_color;
in vec2 v_uv1;
in vec2 v_uv2;

uniform sampler2D u_texture;

void main() {
	frag_color = texture(u_texture, v_uv1).a * v_color;
}
