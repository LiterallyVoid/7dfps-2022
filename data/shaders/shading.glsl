uniform sampler2D u_texture;
uniform sampler2D u_normalmap;
uniform sampler2D u_reflect;

uniform mat4 u_shadow;

#if SHADOW_QUALITY > 0
uniform sampler2DShadow u_shadowmap;
#endif

vec4 shade(vec3 world, vec3 view_dir, mat3 tbn, vec2 uv) {
	vec3 normal = tbn * (texture(u_normalmap, uv).xyz * 2.0 - 1.0);

	normal = normalize(normal);

	vec3 v = reflect(normalize(view_dir), normal);

	float x = (atan(v.y, v.x) / 3.14159) * 0.5 + 0.5;
	float y = v.z * 0.5 + 0.5;

	float fresnel = pow(1.0 - dot(normalize(view_dir), -normal), 3.0) * 0.7;

	float sundot = dot(normal, normalize(SUN_DIR));

	float shadow = 1.0;
	if (dot(tbn[2], SUN_DIR) < 0.0) {
		shadow = 0.0;
	}

	#if SHADOW_QUALITY > 0
	vec4 shadow_ndc = u_shadow * vec4(world, 1.0);
	shadow_ndc /= shadow_ndc.w;
	shadow_ndc = shadow_ndc * 0.5 + 0.5;
	shadow *= texture(u_shadowmap, shadow_ndc.xyz);
	#endif

	vec3 light = vec3(0.02, 0.08, 0.2) + clamp(sundot, 0.0, 1.0) * vec3(1.2, 1.0, 0.8) * shadow;

	vec3 albedo = texture(u_texture, uv).rgb * light;
	vec3 color = mix(albedo, textureLod(u_reflect, vec2(x, y), 0.0).rgb * (shadow * 0.8 + 0.2), fresnel);

	return vec4(color, 1.0);
}
