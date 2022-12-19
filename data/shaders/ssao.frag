#include "stdlib.glsl"

in vec2 v_uv;

uniform sampler2D u_screen;
uniform sampler2D u_screen_normal;
uniform sampler2D u_screen_depth;
uniform float u_time;

uniform mat4 u_projection;
uniform mat4 u_projection_inverse;

layout (location = 0) out vec4 frag_color;

float get_depth(vec2 uv) {
	float depth = texture(u_screen_depth, uv).r * 2.0 - 1.0;

    return linearize(depth);
}

#if AO_QUALITY == 0
#define AO_SAMPLES 16
#define AO_DISTANCE 0.5
#elif AO_QUALITY == 1
#define AO_SAMPLES 32
#define AO_DISTANCE 0.5
#elif AO_QUALITY == 2
#define AO_SAMPLES 32
#define AO_DISTANCE 1.0
#elif AO_QUALITY == 3
#define AO_SAMPLES 64
#define AO_DISTANCE 1.5
#elif AO_QUALITY == 4
#define AO_SAMPLES 64
#define AO_DISTANCE 1.5
#endif

void main() {
	vec3 poisson_disc[64] = vec3[](
		vec3(-0.6975636,-0.4048062,0.16254061),
		vec3(0.41754109,0.20384377,0.62003819),
		vec3(0.70156887,-0.6840237,-0.0348925),
		vec3(0.19053619,-0.4927282,0.76319698),
		vec3(0.42010080,-0.0685366,0.35565605),
		vec3(0.47510998,0.61136032,0.19386318),
		vec3(0.37230569,-0.3492081,-0.4046139),
		vec3(0.55334856,-0.3248289,0.69072138),
		vec3(-0.3167496,-0.1897020,-0.6219943),
		vec3(0.44621770,-0.7095237,-0.3146971),
		vec3(-0.4010611,0.26365902,-0.6617037),
		vec3(-0.3811297,-0.3657282,-0.2835585),
		vec3(-0.2824533,0.02570637,0.30769133),
		vec3(0.63310508,0.45065987,-0.5118606),
		vec3(-0.4714019,-0.5264197,-0.7005896),
		vec3(-0.1976644,0.45692430,0.46138576),
		vec3(-0.0551493,-0.2842667,-0.8812444),
		vec3(-0.4037397,0.05519278,-0.3460732),
		vec3(-0.6161474,0.38722883,0.14916683),
		vec3(-0.2725766,0.31443294,-0.1033542),
		vec3(0.59084480,0.25365440,0.24883785),
		vec3(-0.0027429,-0.5450359,-0.6111376),
		vec3(0.20382743,-0.8668490,0.39054834),
		vec3(0.14556533,0.59475389,0.37864615),
		vec3(0.51211806,0.81768241,-0.2582207),
		vec3(-0.3229209,-0.7778316,0.13010003),
		vec3(-0.0440015,-0.0564915,0.93149176),
		vec3(-0.0972205,-0.2829001,-0.0475825),
		vec3(-0.7810022,-0.2593105,0.50148300),
		vec3(-0.4429019,0.20105272,0.60242584),
		vec3(0.81102043,-0.0846309,0.47914132),
		vec3(0.87748604,0.22149640,0.00212887),
		vec3(0.09215217,-0.0413142,-0.6289937),
		vec3(0.06535180,-0.9182020,-0.3293219),
		vec3(-0.0066664,0.15329068,-0.3194781),
		vec3(-0.2224449,0.68752103,-0.0651573),
		vec3(0.25584399,-0.4905191,0.39075289),
		vec3(0.10382004,0.48257737,-0.4994467),
		vec3(0.15935444,0.85904859,-0.1270028),
		vec3(0.03263031,0.48552975,-0.8709623),
		vec3(0.76106179,-0.0613113,-0.6409014),
		vec3(-0.6695525,-0.6490566,-0.1271891),
		vec3(-0.5599123,0.75802236,0.09343263),
		vec3(-0.0493569,0.28371507,0.76384274),
		vec3(0.66871900,0.03688347,-0.2862758),
		vec3(-0.7128947,0.02746731,-0.1300151),
		vec3(0.11495829,0.32594624,0.01751497),
		vec3(0.63791513,-0.4071939,0.33130911),
		vec3(0.32365316,-0.0840703,-0.9260240),
		vec3(-0.1666910,0.83479995,0.46915667),
		vec3(-0.1299076,0.89426215,-0.3690365),
		vec3(-0.4374679,0.54247368,-0.3581193),
		vec3(0.07942294,-0.0050715,0.20081998),
		vec3(-0.7169013,0.29171625,-0.4118779),
		vec3(-0.0891953,-0.5995304,0.53019363),
		vec3(0.35916135,0.24581201,-0.3493373),
		vec3(0.27267727,-0.5405842,0.01178201),
		vec3(0.23168554,-0.1243813,0.67951865),
		vec3(-0.2407736,-0.7145713,-0.2344069),
		vec3(-0.7571343,-0.3348916,-0.3210699),
		vec3(-0.2030228,-0.1855749,0.61124752),
		vec3(0.31093762,-0.1740477,-0.0734664),
		vec3(-0.5272558,-0.2826550,0.78162467),
		vec3(0.94560209,-0.2554508,0.16970190)
	);

	float center_depth = get_depth(v_uv);
	vec4 point_vec = u_projection_inverse * vec4(v_uv * 2.0 - 1.0, 2.0, 1.0);
	vec3 point = (point_vec.xyz / point_vec.z) * center_depth;

	float total_ssao = 0.0;

	vec3 normal_sampled = texture(u_screen_normal, v_uv).xyz;
	vec3 normal = normal_sampled * 2.0 - 1.0;

	float r = rand(v_uv) * 3.1415 * 2.0;

	mat3 rot = mat3(
		vec3(sin(r), cos(r), 0.0),
		vec3(cos(r), -sin(r), 0.0),
		vec3(0.0, 0.0, 1.0)
	);

	for (int i = 0; i < AO_SAMPLES; i++) {
		vec3 point_offset = poisson_disc[i] * AO_DISTANCE * clamp(center_depth / 3.0, 0.0, 1.0);

		point_offset *= rot;

		if (dot(point_offset, normal) > 0.0) {
			point_offset *= -1;
		}

		vec3 new_point = point + point_offset;

		vec4 new_point_project = u_projection * vec4(new_point, 1.0);
		new_point_project /= new_point_project.w;

		if (abs(new_point_project.x) > 1.0 || abs(new_point_project.y) > 1.0) {
			total_ssao += 1;
			continue;
		}

		float new_depth = get_depth(new_point_project.xy * 0.5 + 0.5);

		float offset = new_depth - new_point.z;

		total_ssao += mix(smoothstep(-0.1, 0.0, offset), 1.0, smoothstep(0.8, 4.0, abs(offset)));
	}

	total_ssao = mix(total_ssao / float(AO_SAMPLES), 1.0, smoothstep(0.1, 0.0, length(normal)));

	frag_color = vec4(pow(total_ssao, 1.5), mod(center_depth, 2.0) / 2.0, 0.0, 1.0);
}
