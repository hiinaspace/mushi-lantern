shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D foliage_diffuse : source_color, filter_linear_mipmap, repeat_disable;
uniform float night_vision : hint_range(0.0, 1.0) = 0.0;
uniform float foliage_reveal_start : hint_range(0.0, 1.0) = 0.90;
uniform float foliage_reveal_end : hint_range(0.0, 1.0) = 0.99;
uniform float grove_size = 128.0;
uniform float edge_strength = 0.65;
#include "res://shaders/river_volume.gdshaderinc"

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 leaf = texture(foliage_diffuse, UV);
	if (leaf.a < 0.5) {
		discard;
	}
	ALBEDO = leaf.rgb * vec3(0.62, 0.68, 0.64);
	ROUGHNESS = 0.92;
	SPECULAR = 0.08;
	float reveal = smoothstep(foliage_reveal_start, foliage_reveal_end, night_vision);
	float rim = 1.0 - smoothstep(0.50, 0.82, leaf.a);
	float outer_grove = smoothstep(grove_size * 0.25, grove_size * 0.44, length(world_position.xz));
	vec3 violet = mix(vec3(0.12, 0.045, 0.20), vec3(0.20, 0.085, 0.28), outer_grove * 0.72);
	EMISSION = violet * rim * reveal * edge_strength;
	vec3 river_eye = (INV_VIEW_MATRIX * vec4(EYE_OFFSET, 1.0)).xyz;
	vec3 river_ray = normalize(world_position - river_eye);
	vec4 river = river_evaluate(river_eye, river_ray, distance(world_position, river_eye));
	ALBEDO *= 1.0 - river.a * 0.06;
	EMISSION += river.rgb;
}
