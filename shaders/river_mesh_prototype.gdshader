shader_type spatial;
render_mode blend_add, depth_draw_never, depth_test_disabled, cull_disabled, unshaded;
stencil_mode read, compare_not_equal, 1;

uniform int shell_index = 0;
uniform float river_animation_rate = 1.0;
uniform float river_night_vision = 1.0;
uniform float river_width = 5.8;
// Scales the entire submerged centerline: both the arms and crest move deeper.
uniform float river_depth = 1.0;
uniform float path_long_scale = 1.0;
uniform float path_medium_scale = 1.0;
uniform float path_long_frequency = 1.0;
uniform float path_medium_frequency = 1.0;
uniform float path_long_speed = 1.0;
uniform float path_medium_speed = 1.0;
uniform float surface_bump_scale = 1.0;
uniform float surface_bump_frequency = 1.0;
uniform float surface_bump_speed = 1.0;
uniform float far_scintillation_blend = 1.0;

varying vec2 river_uv;
varying float river_x;
varying vec3 view_tangent;

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
	float shoulder = max(1.0 - x * x / 784.0, 0.0);
	return (-30.0 + 14.0 * shoulder * shoulder * shoulder) * river_depth;
}

vec3 centerline(float x) {
	float anchor = smoothstep(0.0, 8.0, abs(x));
	float horizon_straight = 1.0 - smoothstep(70.0, 240.0, abs(x));
	float drift_y = (1.15 * path_long_scale * noise1(x * path_long_frequency / 105.0 - (TIME * river_animation_rate) * 0.042 * path_long_speed)
		+ 0.48 * path_medium_scale * noise1(x * path_medium_frequency / 43.0 - (TIME * river_animation_rate) * 0.085 * path_medium_speed)
		+ 0.26 * noise1(x * path_medium_frequency / 24.0 - (TIME * river_animation_rate) * 0.135 * path_medium_speed)) * anchor * horizon_straight;
	float drift_z = (0.92 * path_long_scale * noise1(x * path_long_frequency / 122.0 - (TIME * river_animation_rate) * 0.034 * path_long_speed + 17.0)
		+ 0.43 * path_medium_scale * noise1(x * path_medium_frequency / 47.0 - (TIME * river_animation_rate) * 0.075 * path_medium_speed + 31.0)
		+ 0.24 * noise1(x * path_medium_frequency / 26.0 - (TIME * river_animation_rate) * 0.120 * path_medium_speed + 53.0)) * anchor * horizon_straight;
	// Broad smooth bends carry the medium-field silhouette. Short noise bends
	// make repeated folds when looking axially down the widened additive tube.
	float medium_envelope = smoothstep(35.0, 130.0, abs(x))
		* (1.0 - smoothstep(480.0, 950.0, abs(x)));
	drift_y += 3.0 * path_long_scale * sin(x / 105.0 - TIME * river_animation_rate * 0.025 * path_long_speed) * medium_envelope;
	drift_z += 4.5 * path_long_scale * sin(x / 125.0 - TIME * river_animation_rate * 0.020 * path_long_speed + 1.3) * medium_envelope;
	return vec3(x, center_y(x) + drift_y, -2.0 + drift_z);
}

float radius_at(float x, float theta) {
	float medium = 0.78 * surface_bump_scale * noise1(x * surface_bump_frequency / 32.0 - (TIME * river_animation_rate) * 0.075 * surface_bump_speed + 7.0);
	float fine = 0.30 * surface_bump_scale * noise1(x * surface_bump_frequency / 14.0 - (TIME * river_animation_rate) * 0.145 * surface_bump_speed + 29.0);
	float turning_bump = 0.30 * surface_bump_scale * noise1(x * surface_bump_frequency / 25.0 - (TIME * river_animation_rate) * 0.130 * surface_bump_speed
		+ 1.8 * cos(theta - (TIME * river_animation_rate) * 0.22 * surface_bump_speed));
	float crest = 1.0 - smoothstep(5.0, 34.0, abs(x));
	// The tight upwelling bend cannot carry the same radius as the straight arms
	// without the additive shells folding across each other.
	float width_here = mix(min(river_width, 1.6), river_width, smoothstep(12.0, 70.0, abs(x)));
	float distant_stillness = 1.0 - smoothstep(40.0, 180.0, abs(x));
	return max(1.0, 4.05 - 1.65 * crest + (medium + fine + turning_bump) * distant_stillness - float(shell_index) * 0.54) * width_here;
}

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec2 spark(vec2 p, float threshold) {
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
	float unresolved = smoothstep(0.18, 0.65, footprint);
	return vec2(smoothstep(threshold, threshold + 0.09, seed) * dot_shape
		* (1.0 - unresolved), unresolved);
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
	view_tangent = normalize((MODELVIEW_MATRIX * vec4(tangent, 0.0)).xyz);
	river_uv = UV;
	river_x = x;
}

void fragment() {
	if (!FRONT_FACING) { discard; }
	float s = river_uv.x;
	float around = river_uv.y;
	float layer = float(shell_index);
	vec2 uv1 = vec2(s * (1.7 + layer * 0.31) - (TIME * river_animation_rate) * (3.4 + layer * 0.63),
		(around * 6.2831853 + s * 0.08) * (1.3 + layer * 0.71) + layer * 7.9);
	vec2 uv2 = vec2(s * (4.0 + layer * 0.47) - (TIME * river_animation_rate) * (8.0 + layer * 0.86),
		(around * 6.2831853 - s * 0.06) * (2.8 + layer * 0.52) + layer * 13.3);
	vec2 fine = spark(uv1, 0.78);
	vec2 finer = spark(uv2, 0.88);
	float distance_along = abs(river_x);
	float merge = smoothstep(35.0, 240.0, distance_along) * clamp(far_scintillation_blend, 0.0, 1.0);
	float dots = (fine.x + 0.48 * finer.x) * (1.0 - merge);
	// Remove the axial foreshortening before measuring the tube's silhouette.
	// Otherwise a soft cross section disappears when looking along the vein.
	vec3 sight = normalize(VIEW);
	vec3 tangent = normalize(view_tangent);
	float transverse = length(sight - tangent * dot(sight, tangent));
	float facing = clamp(abs(dot(normalize(NORMAL), sight)) / max(transverse, 0.0001), 0.0, 1.0);
	float soft_profile = pow(facing, 3.0);
	// All shells retain a small diffuse contribution as individual sparks become
	// subpixel. The medium-field haze is already present before sparks retire.
	float unresolved = (fine.y + 0.48 * finer.y) / 1.48;
	float diffuse = shell_index == 0 ? mix(0.030, 0.060, merge) : 0.0;
	diffuse += 0.009 * unresolved * (1.0 - merge);
	float far_fade = 1.0 - smoothstep(450.0, 1800.0, distance_along);
	// This input is the late adaptation envelope. Reveal the crest, then arms,
	// then horizon flares; each front remains broad enough to avoid a wipe line.
	float distance_delay = smoothstep(16.0, 1100.0, distance_along);
	float reveal = smoothstep(0.04 + 0.50 * distance_delay,
		0.48 + 0.40 * distance_delay, river_night_vision);
	ALBEDO = vec3(0.949, 0.800, 0.196)
		* (diffuse * soft_profile + dots * (0.34 - layer * 0.07) * soft_profile);
	ALPHA = reveal * far_fade;
}
