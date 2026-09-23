shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D foliage_mask : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 foliage_color : source_color = vec4(1.0);
uniform float night_vision : hint_range(0.0, 1.0) = 0.0;
uniform float fleck_frequency = 3.0;

varying vec3 world_position;

float fleck_hash(vec3 cell) {
	return fract(sin(dot(cell, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Explicit cutout keeps cards and opaque crowns in the depth-writing pass.
	if (texture(foliage_mask, UV).a < 0.5) {
		discard;
	}
	ALBEDO = foliage_color.rgb;
	ROUGHNESS = 0.95;
	SPECULAR = 0.15;
	float activation = smoothstep(0.90, 0.99, night_vision);
	vec3 fleck_position = world_position * fleck_frequency;
	float selected = smoothstep(0.90, 0.975, fleck_hash(floor(fleck_position)));
	float distance_from_center = length(fract(fleck_position) - vec3(0.5));
	float round_patch = 1.0 - smoothstep(0.22, 0.48, distance_from_center);
	EMISSION = vec3(0.045, 0.20, 0.11) * activation * selected * round_patch;
}
