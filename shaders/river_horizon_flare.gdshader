shader_type spatial;
render_mode blend_add, depth_draw_never, depth_test_disabled, cull_disabled, unshaded;
stencil_mode read, compare_not_equal, 1;

uniform float river_night_vision = 1.0;
uniform float horizon_flare_strength = 0.25;
uniform float horizon_flare_spread = 1.0;
uniform float flare_height = 500.0;
varying float below_horizon;

void vertex() {
	below_horizon = 0.5 - VERTEX.y / max(flare_height, 1.0);
}

void fragment() {
	// The plane ends at the true horizon. Both its upper and lower edges fade
	// continuously so the glow reads as submerged haze, not a flat sunset band.
	float below = below_horizon;
	float rise = smoothstep(0.0, 0.09, below);
	float lower_falloff = exp(-pow(max(below - 0.13, 0.0) / 0.50, 2.0));
	float horizontal = exp(-pow((UV.x - 0.5) / (0.28 * max(horizon_flare_spread, 0.2)), 2.0));
	float side_fade = smoothstep(0.0, 0.12, UV.x) * (1.0 - smoothstep(0.88, 1.0, UV.x));
	float reveal = smoothstep(0.64, 0.98, river_night_vision);
	float view_pitch = abs(normalize(INV_VIEW_MATRIX[2].xyz).y);
	float horizon_gaze = 1.0 - smoothstep(0.07, 0.20, view_pitch);
	float haze = rise * lower_falloff * horizontal * side_fade;
	ALBEDO = vec3(0.34, 0.26, 0.065) * horizon_flare_strength;
	float alpha = haze * reveal * horizon_gaze * 0.34;
	// The dark gold occupies only a few LDR code values; stable interleaved
	// gradient noise trades broad concentric quantization bands for fine grain.
	float dither = fract(52.9829189 * fract(0.06711056 * FRAGCOORD.x
		+ 0.00583715 * FRAGCOORD.y)) - 0.5;
	ALPHA = clamp(alpha + dither * 0.046 * smoothstep(0.004, 0.025, alpha), 0.0, 1.0);
}
