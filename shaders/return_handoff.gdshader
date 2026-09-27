shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, blend_mix, depth_draw_never, depth_test_disabled;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	float size = length(MODEL_MATRIX[0].xyz);
	vec3 local = (right * VERTEX.x + up * VERTEX.y) * size;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(center + local, 1.0);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p * vec2(0.78, 1.0));
	float core = 1.0 - smoothstep(0.10, 0.72, d);
	float rim = 1.0 - smoothstep(0.52, 0.94, d);
	float beam = exp(-abs(p.x) * 13.0) * (1.0 - smoothstep(0.62, 1.0, abs(p.y)));
	float alpha = max(max(core * 0.50, rim * 0.78), beam * 0.27) * COLOR.a;
	if (alpha < 0.02) discard;
	ALBEDO = vec3(0.96, 0.78, 0.28);
	EMISSION = vec3(1.45, 0.91, 0.25) * (0.45 + rim + beam * 0.75);
	ALPHA = alpha;
}
