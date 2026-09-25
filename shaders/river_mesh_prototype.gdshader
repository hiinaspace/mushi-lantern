shader_type spatial;
render_mode blend_add, depth_draw_never, depth_test_disabled, cull_disabled, unshaded;
stencil_mode read, compare_not_equal, 1;

uniform int shell_index = 0;
uniform float river_night_vision = 1.0;
uniform float path_long_scale = 1.0;
uniform float path_medium_scale = 1.0;
uniform float path_long_speed = 1.0;
uniform float path_medium_speed = 1.0;
uniform float surface_bump_scale = 1.0;
uniform float surface_bump_speed = 1.0;

varying vec2 river_uv;
varying float river_x;

float hash11(float p) {
	return fract(sin(p * 127.1) * 43758.5453);
}

float noise1(float p) {
	float cell = floor(p);
	float fraction = fract(p);
	fraction = fraction * fraction * (3.0 - 2.0 * fraction);
	return mix(hash11(cell), hash11(cell + 1.0), fraction) * 2.0 - 1.0;
}

float center_y(float x) {
	float shoulder = max(1.0 - x * x / 1600.0, 0.0);
	return -30.0 + 25.0 * shoulder * shoulder * shoulder;
}

vec3 centerline(float x) {
	float anchor = smoothstep(0.0, 8.0, abs(x));
	float horizon_straight = 1.0 - smoothstep(320.0, 1700.0, abs(x));
	float drift_y = (1.15 * path_long_scale * noise1(x / 105.0 - TIME * 0.042 * path_long_speed)
		+ 0.48 * path_medium_scale * noise1(x / 43.0 - TIME * 0.085 * path_medium_speed)
		+ 0.26 * noise1(x / 24.0 - TIME * 0.135 * path_medium_speed)) * anchor * horizon_straight;
	float drift_z = (0.92 * path_long_scale * noise1(x / 122.0 - TIME * 0.034 * path_long_speed + 17.0)
		+ 0.43 * path_medium_scale * noise1(x / 47.0 - TIME * 0.075 * path_medium_speed + 31.0)
		+ 0.24 * noise1(x / 26.0 - TIME * 0.120 * path_medium_speed + 53.0)) * anchor * horizon_straight;
	return vec3(x, center_y(x) + drift_y, -2.0 + drift_z);
}

float radius_at(float x, float theta) {
	float medium = 0.78 * surface_bump_scale * noise1(x / 32.0 - TIME * 0.075 * surface_bump_speed + 7.0);
	float fine = 0.30 * surface_bump_scale * noise1(x / 14.0 - TIME * 0.145 * surface_bump_speed + 29.0);
	float turning_bump = 0.30 * surface_bump_scale * noise1(x / 25.0 - TIME * 0.130 * surface_bump_speed
		+ 1.8 * cos(theta - TIME * 0.22 * surface_bump_speed));
	return 2.90 + medium + fine + turning_bump - float(shell_index) * 0.42;
}

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float spark(vec2 p, float threshold) {
	vec2 cell = floor(p);
	float seed = hash21(cell);
	vec2 center = vec2(0.5) + vec2(hash21(cell + vec2(19.0, 3.0)),
		hash21(cell + vec2(7.0, 23.0))) * 0.36 - 0.18;
	vec2 dx = dFdx(p);
	vec2 dy = dFdy(p);
	float determinant = dx.x * dy.y - dy.x * dx.y;
	vec2 delta = fract(p) - center;
	vec2 pixel_delta = vec2(dy.y * delta.x - dy.x * delta.y,
		-dx.y * delta.x + dx.x * delta.y) / max(abs(determinant), 0.0005);
	float footprint = max(length(vec2(dx.x, dy.x)), length(vec2(dx.y, dy.y)));
	float dot_shape = 1.0 - smoothstep(0.67, 1.45, length(pixel_delta));
	return smoothstep(threshold, threshold + 0.09, seed) * dot_shape
		* (1.0 - smoothstep(0.28, 0.85, footprint));
}

void vertex() {
	float x = UV2.x;
	float theta = UV2.y;
	vec3 center = centerline(x);
	vec3 tangent = normalize(centerline(x + 0.35) - centerline(x - 0.35));
	vec3 normal = vec3(0.0, 0.0, 1.0);
	vec3 binormal = normalize(cross(normal, tangent));
	vec3 radial = cos(theta) * normal + sin(theta) * binormal;
	VERTEX = center + radial * radius_at(x, theta);
	NORMAL = radial;
	river_uv = UV;
	river_x = x;
}

void fragment() {
	if (!FRONT_FACING) { discard; }
	float s = river_uv.x;
	float around = river_uv.y;
	float layer = float(shell_index);
	vec2 uv1 = vec2(s * (1.7 + layer * 0.31) - TIME * (3.4 + layer * 0.63),
		(around * 6.2831853 + s * 0.08) * (1.3 + layer * 0.71) + layer * 7.9);
	vec2 uv2 = vec2(s * (4.0 + layer * 0.47) - TIME * (8.0 + layer * 0.86),
		(around * 6.2831853 - s * 0.06) * (2.8 + layer * 0.52) + layer * 13.3);
	float dots = spark(uv1, 0.78) + 0.48 * spark(uv2, 0.88);
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float edge_softness = smoothstep(0.02, 0.78, facing);
	float diffuse = shell_index == 0 ? 0.10 * pow(facing, 0.8) : 0.0;
	float far_fade = 1.0 - smoothstep(2500.0, 3000.0, abs(river_x));
	float reveal = smoothstep(0.56, 0.94, river_night_vision);
	ALBEDO = vec3(0.949, 0.800, 0.196)
		* (diffuse + dots * (0.65 - layer * 0.11)) * edge_softness;
	ALPHA = reveal * far_fade;
}
