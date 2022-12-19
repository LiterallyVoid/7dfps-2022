#include "stdlib.glsl"

in vec2 v_uv;

uniform sampler2D u_screen;
uniform sampler2D u_screen_normal;
uniform sampler2D u_screen_depth;
uniform sampler2D u_screen_ssao;
uniform float u_time;

layout (location = 0) out vec4 frag_color;

void main() {
	frag_color = texture(u_screen, v_uv);

#if AO_QUALITY > 0
	frag_color.rgb *= texture(u_screen_ssao, v_uv).r;
#endif
}
