shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform float adaptation : hint_range(0.0, 1.0) = 0.0;
uniform float return_pulse : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float radial = 1.0 - abs(UV.y * 2.0 - 1.0);
	radial = smoothstep(0.0, 0.85, radial);
	float angle = UV.x * 6.2831853;
	float variation = 0.86 + 0.09 * sin(angle * 7.0 + TIME * 0.65)
		+ 0.05 * sin(angle * 19.0 - TIME * 0.38);
	float slow_pulse = 0.94 + 0.06 * sin(TIME * 1.25);
	float intensity = (0.34 + adaptation * 0.16 + return_pulse * 0.42) * variation * slow_pulse;
	vec3 gold = vec3(1.0, 0.67, 0.27);
	ALBEDO = gold * intensity;
	EMISSION = gold * intensity * 1.35;
	ALPHA = radial * (0.46 + return_pulse * 0.22);
}
