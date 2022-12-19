const vec3 SUN_DIR = vec3(0.15, 0.4, 1.0);
const float znear = 0.1;
const float zfar = 100.0;

float linearize(float w) {
    return (2.0 * znear * zfar) / (zfar + znear - w * (zfar - znear));
}

float rand(vec2 co) {
	return fract(sin(dot(co.xy ,vec2(12.9898,78.233))) * 43758.5453);
}
