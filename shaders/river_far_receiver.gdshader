shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, unshaded;

#include "res://shaders/river_volume.gdshaderinc"

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// This is a dark far-country continuation with normal depth testing. It
	// begins at the Terrain3D edge and slopes away toward the skyline.
	float dark_variation = 0.88 + 0.12 * sin(world_position.x * 0.033 + world_position.z * 0.047);
	ALBEDO = vec3(0.006, 0.009, 0.008) * dark_variation;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	vec3 river_eye = (INV_VIEW_MATRIX * vec4(EYE_OFFSET, 1.0)).xyz;
	vec3 river_ray = normalize(world_position - river_eye);
	vec4 river = river_evaluate(river_eye, river_ray, distance(world_position, river_eye));
	ALBEDO *= 1.0 - river.a * 0.06;
	EMISSION = river.rgb;
	EMISSION += river_horizon_tail(world_position);
}
