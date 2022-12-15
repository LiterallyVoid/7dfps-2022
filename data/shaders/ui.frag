#include "stdlib.glsl"

layout (location = 0) out vec4 frag_color;

in vec2 v_uv;
in vec4 v_color;

uniform sampler2D u_texture;

void main() {
	frag_color = texture(u_texture, v_uv);
	float alpha = (frag_color.r - (127.0 / 255.0)) / (fwidth(v_uv.x) * 1024.0 / 32.0) + 0.5;
	frag_color = v_color * alpha;
}
