shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, blend_mix;

uniform bool face_camera = true;
uniform bool animate_vertices = true;
uniform float glow_strength : hint_range(0.0, 3.0) = 0.72;

varying flat float glyph_type;
varying flat float glyph_seed;
varying vec4 glyph_color;

void vertex() {
	glyph_type = floor(INSTANCE_CUSTOM.x * 2.0 + 0.5);
	glyph_seed = INSTANCE_CUSTOM.y;
	glyph_color = COLOR;
	vec2 local = VERTEX.xy;
	float heading = (INSTANCE_CUSTOM.z - 0.5) * 6.28318530718;
	float flutter = animate_vertices ? sin(TIME * (1.7 + glyph_seed) + glyph_seed * 19.0) * 0.055 : 0.0;
	local.x += sin(local.y * 3.2 + TIME * 1.4 + glyph_seed * 11.0) * flutter;
	mat2 turn = mat2(vec2(cos(heading), sin(heading)), vec2(-sin(heading), cos(heading)));
	local = turn * local * INSTANCE_CUSTOM.w;
	VERTEX.xy = local;
	if (face_camera) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			INV_VIEW_MATRIX[0],
			INV_VIEW_MATRIX[1],
			INV_VIEW_MATRIX[2],
			MODEL_MATRIX[3]
		);
	}
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
	// A rounded head and tapered tail make direction visible at swarm scale.
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
	float core = inside * 0.28;
	float alpha = max(core, ring);
	if (alpha < 0.025) {
		discard;
	}
	vec3 color = glyph_color.rgb;
	ALBEDO = color * (0.72 + ring * 0.38);
	EMISSION = color * glow_strength * (0.35 + ring * 0.95);
	ALPHA = alpha * glyph_color.a;
}
