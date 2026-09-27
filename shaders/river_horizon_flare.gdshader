shader_type spatial;
render_mode blend_add, depth_draw_never, depth_test_disabled, cull_disabled, unshaded;
stencil_mode read, compare_not_equal, 1;

uniform float river_night_vision = 1.0;
uniform float horizon_flare_strength = 0.15;
uniform float horizon_flare_spread = 0.5;
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
	float reveal = smoothstep(0.72, 1.0, river_night_vision);
	float haze = rise * lower_falloff * horizontal * side_fade;
	// A compact bright center continues the vein as its geometry dissolves.
	// Its height follows the -30 * depth centerline of the distant tube.
	float core = exp(-pow((below - 0.06) / 0.075, 2.0))
		* exp(-pow((UV.x - 0.5) / (0.075 * max(horizon_flare_spread, 0.2)), 2.0))
		* smoothstep(0.0, 0.024, below);
	ALBEDO = vec3(0.949, 0.800, 0.196) * horizon_flare_strength;
	// This is a feature of the submerged world, not an eye-locked glare effect.
	// Gaze gating made it vanish when players glanced above or below the horizon.
	float alpha = (haze * 0.1133 + core * 0.5667) * reveal;
	// The dark gold occupies only a few LDR code values; stable interleaved
	// gradient noise trades broad concentric quantization bands for fine grain.
	float dither = fract(52.9829189 * fract(0.06711056 * FRAGCOORD.x
		+ 0.00583715 * FRAGCOORD.y)) - 0.5;
	ALPHA = clamp(alpha + dither * 0.046 * smoothstep(0.004, 0.025, alpha), 0.0, 1.0);
}
