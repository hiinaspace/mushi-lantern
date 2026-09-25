shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// The offline mask follows the leaf texture's alpha silhouette. Runtime
// variation picks small groups of leaves to reveal at different adaptation
// levels, so the entire crown never lights up at once.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D edge_mask : filter_linear_mipmap, repeat_disable;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform vec3 edge_color : source_color = vec3(0.66, 0.42, 0.84);
uniform float edge_strength = 0.16;
uniform float alpha_cutoff = 0.5;
uniform float night_vision = 0.0;
uniform float foliage_reveal_start = 0.90;
uniform float foliage_reveal_end = 0.99;

// Smooth value noise keeps the per-branch reveal continuous across texels.
// A hash of interpolated world position caused rapid shimmer because its
// large sine multiplier amplified tiny per-pixel position changes.
float reveal_hash(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}

float reveal_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = reveal_hash(cell);
	float b = reveal_hash(cell + vec2(1.0, 0.0));
	float c = reveal_hash(cell + vec2(0.0, 1.0));
	float d = reveal_hash(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec4 leaf = texture(albedo_tex, UV) * albedo_tint;
	ALBEDO = leaf.rgb;
	ALPHA = leaf.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
	ROUGHNESS = 0.92;
	SPECULAR = 0.16;

	float edge = texture(edge_mask, UV).r;
	// UV space makes each branch's reveal independent of the world grid. Smooth
	// interpolation avoids hard cell edges; derivatives fade the pattern out
	// before its 28-cell frequency becomes subpixel.
	vec2 reveal_uv = UV * 28.0;
	float footprint = max(fwidth(reveal_uv.x), fwidth(reveal_uv.y));
	float distant_filter = smoothstep(0.35, 0.85, footprint);
	float selected_noise = reveal_noise(reveal_uv);
	float selected = smoothstep(0.60, 0.90, selected_noise);
	selected = mix(selected, 0.065, distant_filter);
	float stagger = reveal_noise(reveal_uv + vec2(13.7, 5.3));
	stagger = mix(stagger, 0.5, distant_filter);
	float onset = mix(foliage_reveal_start, foliage_reveal_end, stagger);
	float fade_width = max(0.01, (foliage_reveal_end - foliage_reveal_start) * 0.3);
	float reveal = smoothstep(onset - fade_width, onset + fade_width, night_vision);
	EMISSION = edge_color * edge_strength * edge * selected * reveal;
}
