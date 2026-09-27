shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

void fragment() {
	float radial = clamp(UV.x, 0.0, 1.0);
	float falloff = pow(1.0 - smoothstep(0.0, 1.0, radial), 2.0);
	vec3 warm = vec3(0.54, 0.28, 0.10);
	ALBEDO = warm * 0.24 * falloff;
	EMISSION = warm * 0.24 * falloff;
	ALPHA = falloff;
}
