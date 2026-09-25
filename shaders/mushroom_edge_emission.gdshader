shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// Mushroom fruit use their own per-instance reveal so several readable caps
// show a violet adaptation cue without creating a continuous neon ring.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D edge_mask : filter_linear_mipmap, repeat_disable;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform vec3 edge_color : source_color = vec3(0.65, 0.39, 0.86);
uniform float edge_strength = 1.8;
uniform float silhouette_strength = 0.72;
uniform float alpha_cutoff = 0.5;
uniform float night_vision = 0.0;
uniform float foliage_reveal_start = 0.90;
uniform float foliage_reveal_end = 0.99;
uniform vec2 patch_seed = vec2(0.0);

varying flat float fruit_seed;

void vertex() {
	fruit_seed = fract(sin(float(INSTANCE_ID) * 127.1 + dot(patch_seed, vec2(311.7, 74.7))) * 43758.5453);
}

void fragment() {
	vec4 fruit = texture(albedo_tex, UV) * albedo_tint;
	ALBEDO = fruit.rgb;
	ALPHA = fruit.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
	ROUGHNESS = 0.92;
	SPECULAR = 0.16;

	float texture_edge = texture(edge_mask, UV).r;
	float view_edge = pow(clamp(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 5.0);
	float edge = max(texture_edge * 0.72, view_edge * silhouette_strength);
	float selected = smoothstep(0.48, 0.93, fruit_seed);
	float stagger = fract(sin(fruit_seed * 91.7 + 19.7) * 43758.5453);
	float onset = mix(foliage_reveal_start, foliage_reveal_end, stagger);
	float fade_width = max(0.01, (foliage_reveal_end - foliage_reveal_start) * 0.3);
	float reveal = smoothstep(onset - fade_width, onset + fade_width, night_vision);
	EMISSION = edge_color * edge_strength * edge * selected * reveal;
}
