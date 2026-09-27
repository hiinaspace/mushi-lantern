shader_type spatial;
render_mode unshaded, blend_mix, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled;

uniform float opacity : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 edge = min(UV, vec2(1.0) - UV);
	float fade = smoothstep(0.0, 0.095, edge.x) * smoothstep(0.0, 0.14, edge.y);
	ALBEDO = vec3(0.025, 0.055, 0.065);
	ALPHA = 0.75 * opacity * fade;
}
