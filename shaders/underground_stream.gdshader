shader_type spatial;
render_mode unshaded, blend_add, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, world_vertex_coords;

uniform sampler2D terrain_height : filter_linear, repeat_disable;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform float terrain_size = 128.0;
uniform float night_vision : hint_range(0.0, 1.0) = 0.0;
uniform vec3 stream_color : source_color = vec3(0.36, 0.82, 0.91);

varying vec3 stream_world_position;

void vertex() {
	stream_world_position = VERTEX;
}

void fragment() {
	float height_depth = texture(depth_texture, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, height_depth, 1.0);
	view.xyz /= max(view.w, 0.00001);
	vec3 scene_world = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz;
	vec2 terrain_uv = (scene_world.xz + vec2(terrain_size * 0.5)) / terrain_size;
	float sampled_ground = texture(terrain_height, terrain_uv).r;
	bool on_ground = all(greaterThanEqual(terrain_uv, vec2(0.0))) && all(lessThanEqual(terrain_uv, vec2(1.0))) && abs(scene_world.y - sampled_ground) < 0.22;
	float scene_distance = length(scene_world - CAMERA_POSITION_WORLD);
	float stream_distance = length(stream_world_position - CAMERA_POSITION_WORLD);
	// The terrain surface is the intentional see-through layer. Every other
	// opaque surface still hides the band if it lies between the eye and stream.
	if (!on_ground && scene_distance + 0.22 < stream_distance) {
		discard;
	}
	float vision = smoothstep(0.56, 0.94, night_vision);
	float edge_distance = abs(UV.y - 0.5) * 2.0;
	float edge = 1.0 - smoothstep(0.48, 1.0, edge_distance);
	vec2 particle_grid = UV * vec2(460.0, 5.0) + vec2(TIME * 0.07, 0.0);
	vec2 cell = floor(particle_grid);
	vec2 local = fract(particle_grid);
	vec2 seed = fract(sin(vec2(dot(cell, vec2(127.1, 311.7)), dot(cell, vec2(269.5, 183.3)))) * 43758.5453);
	vec2 particle_delta = abs(local - seed);
	particle_delta = min(particle_delta, 1.0 - particle_delta);
	float speck = 1.0 - smoothstep(0.025, 0.19, length(particle_delta * vec2(1.0, 1.3)));
	float haze = 0.13 + 0.07 * sin(UV.x * 25.0 + TIME * 0.08 + sin(UV.x * 8.0));
	float strength = vision * edge * (haze + speck * 0.72) * COLOR.r;
	ALBEDO = stream_color;
	EMISSION = stream_color * strength * 2.25;
	ALPHA = strength * 0.15;
}
