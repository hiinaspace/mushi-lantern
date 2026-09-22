shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, blend_mix;

uniform sampler2D state_texture : filter_nearest, repeat_disable;
uniform float interpolation_alpha : hint_range(0.0, 1.0) = 1.0;
uniform float energy_neutral : hint_range(0.2, 0.65) = 0.45;
uniform float population_variation : hint_range(0.0, 1.0) = 0.0;
uniform float glyph_render_scale : hint_range(0.25, 2.0) = 1.0;
uniform bool face_camera = false;
uniform bool animate_vertices = true;
uniform float glow_strength : hint_range(0.0, 3.0) = 0.72;

varying flat float glyph_type;
varying flat float glyph_seed;
varying vec4 glyph_color;

vec3 rgb_to_hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv_to_rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

vec3 energy_color(float arousal, float subtype) {
	float e = clamp(arousal, 0.0, 1.0);
	float middle = clamp(energy_neutral, 0.2, 0.65);
	vec3 blue = vec3(0.157, 0.490, 0.910);
	vec3 green = vec3(0.220, 0.847, 0.482);
	vec3 yellow = vec3(0.949, 0.800, 0.196);
	vec3 orange = vec3(0.961, 0.361, 0.125);
	vec3 color = e <= middle
		? mix(blue, green, smoothstep(0.0, middle, e))
		: (e <= 0.75
			? mix(green, yellow, smoothstep(middle, 0.75, e))
			: mix(yellow, orange, smoothstep(0.75, 1.0, e)));
	vec3 hsv = rgb_to_hsv(color);
	hsv.x = fract(hsv.x + (subtype - 1.0) * 0.04 * population_variation + 1.0);
	return hsv_to_rgb(hsv);
}

void vertex() {
	int agent = INSTANCE_ID;
	vec4 previous = texelFetch(state_texture, ivec2(agent, 0), 0);
	vec4 current = texelFetch(state_texture, ivec2(agent, 1), 0);
	vec3 center = mix(previous.xyz, current.xyz, interpolation_alpha);
	float arousal = mix(previous.w, current.w, interpolation_alpha);
	glyph_type = floor(INSTANCE_CUSTOM.x * 2.0 + 0.5);
	glyph_seed = INSTANCE_CUSTOM.y;
	glyph_color = vec4(mix(energy_color(arousal, glyph_type), energy_color(arousal, glyph_type) * COLOR.rgb, 0.18), current.w < 0.0 ? 0.0 : 1.0);

	vec2 local = VERTEX.xy;
	float flutter = animate_vertices ? sin(TIME * (1.7 + glyph_seed) + glyph_seed * 19.0) * 0.055 : 0.0;
	local.x += sin(local.y * 3.2 + TIME * 1.4 + glyph_seed * 11.0) * flutter;
	float half_size = clamp(0.175 * INSTANCE_CUSTOM.z, 0.12, 0.25) * glyph_render_scale;
	local *= half_size;

	// Row 2 carries the last useful heading through rest and vertical travel.
	vec3 forward = texelFetch(state_texture, ivec2(agent, 2), 0).xyz;
	if (dot(forward, forward) < 0.0001) {
		forward = vec3(cos(glyph_seed * 6.2831853), 0.0, sin(glyph_seed * 6.2831853));
	}
	forward = normalize(forward);
	vec3 right;
	vec3 up;
	if (face_camera) {
		right = normalize(INV_VIEW_MATRIX[0].xyz);
		up = normalize(INV_VIEW_MATRIX[1].xyz);
		vec2 screen_heading = vec2(dot(forward, right), dot(forward, up));
		float angle = length(screen_heading) > 0.0001 ? atan(-screen_heading.x, screen_heading.y) : 0.0;
		local = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle))) * local;
	} else {
		vec3 sideways = cross(forward, vec3(0.0, 1.0, 0.0));
		vec3 fallback = vec3(cos(glyph_seed * 6.2831853), 0.0, sin(glyph_seed * 6.2831853));
		fallback -= forward * dot(fallback, forward);
		if (dot(fallback, fallback) < 0.0001) {
			fallback = vec3(0.0, 0.0, 1.0);
		}
		fallback = normalize(fallback);
		if (dot(sideways, fallback) < 0.0) {
			fallback = -fallback;
		}
		vec3 normal = normalize(mix(fallback, normalize(sideways + vec3(0.000001)), smoothstep(0.02, 0.12, length(sideways))));
		right = normalize(cross(forward, normal));
		up = forward;
	}
	vec3 world = center + right * local.x + up * local.y;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

float circle_sdf(vec2 p, float radius) {
	return length(p) - radius;
}

float ellipse_sdf(vec2 p, vec2 radii) {
	return (length(p / radii) - 1.0) * min(radii.x, radii.y);
}

float glyph_sdf(vec2 p, float kind, float seed) {
	if (kind < 0.5) {
		return circle_sdf(p, 0.62);
	}
	if (kind < 1.5) {
		float angle = atan(p.y, p.x);
		float wobble = sin(angle * 3.0 + seed * 9.0) * 0.065 + sin(angle * 5.0 - seed * 13.0) * 0.035;
		return length(p) - (0.58 + wobble);
	}
	float head = circle_sdf(p - vec2(0.0, 0.27), 0.43);
	vec2 tail_p = p + vec2(0.0, 0.30);
	float tail = ellipse_sdf(tail_p, vec2(0.22, 0.58));
	return min(head, tail);
}

void fragment() {
	if (glyph_color.a <= 0.001) {
		discard;
	}
	vec2 p = (UV - vec2(0.5)) * vec2(2.0, -2.0);
	float sdf = glyph_sdf(p, glyph_type, glyph_seed);
	float edge = max(fwidth(sdf), 0.012);
	float inside = 1.0 - smoothstep(-edge, edge, sdf);
	float ring = 1.0 - smoothstep(edge * 1.1, edge * 3.7, abs(sdf));
	float alpha = max(inside * 0.28, ring);
	if (alpha < 0.025) {
		discard;
	}
	vec3 color = glyph_color.rgb;
	ALBEDO = color * (0.72 + ring * 0.38);
	EMISSION = color * glow_strength * (0.35 + ring * 0.95);
	ALPHA = alpha * glyph_color.a;
}
