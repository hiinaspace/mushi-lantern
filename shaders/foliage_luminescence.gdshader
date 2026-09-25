shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D foliage_mask : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 foliage_color : source_color = vec4(1.0);
uniform float night_vision : hint_range(0.0, 1.0) = 0.0;
uniform float foliage_reveal_start = 0.90;
uniform float foliage_reveal_end = 0.99;
uniform float fleck_frequency = 3.0;
uniform float fleck_strength = 1.0;
uniform float grove_size = 128.0;
#include "res://shaders/river_volume.gdshaderinc"

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
	float activation = smoothstep(foliage_reveal_start, foliage_reveal_end, night_vision);
	vec3 fleck_position = world_position * fleck_frequency;
	float selected = smoothstep(0.90, 0.975, fleck_hash(floor(fleck_position)));
	float distance_from_center = length(fract(fleck_position) - vec3(0.5));
	float round_patch = 1.0 - smoothstep(0.22, 0.48, distance_from_center);
	float outer_grove = smoothstep(grove_size * 0.25, grove_size * 0.44, length(world_position.xz));
	// A restrained violet family stays distinct from the blue sleeping mushi
	// and remains patchy as adaptation reaches its final stage.
	vec3 fleck_color = mix(vec3(0.12, 0.045, 0.20), vec3(0.20, 0.085, 0.28), outer_grove * 0.72);
	EMISSION = fleck_color * activation * selected * round_patch * fleck_strength;

	// Same eye-space volume as the opaque terrain and distant receiver.
	vec3 river_eye = (INV_VIEW_MATRIX * vec4(EYE_OFFSET, 1.0)).xyz;
	vec3 river_ray = normalize(world_position - river_eye);
	vec4 river = river_evaluate(river_eye, river_ray, distance(world_position, river_eye));
	ALBEDO *= 1.0 - river.a * 0.06;
	EMISSION += river.rgb;
}
