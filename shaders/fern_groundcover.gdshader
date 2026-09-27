shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D fern_diffuse : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D fern_alpha : filter_linear_mipmap, repeat_disable;
uniform float night_vision : hint_range(0.0, 1.0) = 0.0;
uniform float reveal_start : hint_range(0.0, 1.0) = 0.90;
uniform float reveal_end : hint_range(0.0, 1.0) = 0.99;
uniform float edge_strength : hint_range(0.0, 1.0) = 0.72;

void fragment() {
	float coverage = texture(fern_alpha, UV).r;
	if (coverage < 0.48) {
		discard;
	}
	vec3 leaf = texture(fern_diffuse, UV).rgb;
	ALBEDO = leaf * vec3(0.54, 0.66, 0.56);
	ROUGHNESS = 0.92;
	SPECULAR = 0.08;
	float reveal = smoothstep(reveal_start, reveal_end, night_vision);
	float rim = 1.0 - smoothstep(0.50, 0.83, coverage);
	EMISSION = (vec3(0.012, 0.0045, 0.020) * coverage
		+ vec3(0.12, 0.045, 0.20) * rim * edge_strength) * reveal;
}
