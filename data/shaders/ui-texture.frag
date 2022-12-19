#include "stdlib.glsl"

layout (location = 0) out vec4 frag_color;

in vec2 v_uv;
in vec4 v_color;

uniform sampler2D u_texture;

void main() {
	frag_color = texture(u_texture, v_uv) * v_color;
}
