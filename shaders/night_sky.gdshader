shader_type sky;

uniform float night_vision : hint_range(0.0, 1.0) = 1.0;
// Negative uses live TIME. A fixed value makes captures directly comparable.
uniform float star_time_override = -1.0;

// The samples lie in 3D direction space, so there are no longitude seams or
// crowded latitude rows at the poles. Each cell holds at most one small star.
vec3 star_hash(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

float cloud_noise(vec3 position) {
	vec3 cell = floor(position);
	vec3 blend = fract(position);
	blend = blend * blend * (3.0 - 2.0 * blend);
	float bottom = mix(
		mix(star_hash(cell).x, star_hash(cell + vec3(1.0, 0.0, 0.0)).x, blend.x),
		mix(star_hash(cell + vec3(0.0, 1.0, 0.0)).x,
			star_hash(cell + vec3(1.0, 1.0, 0.0)).x, blend.x), blend.y);
	float top = mix(
		mix(star_hash(cell + vec3(0.0, 0.0, 1.0)).x,
			star_hash(cell + vec3(1.0, 0.0, 1.0)).x, blend.x),
		mix(star_hash(cell + vec3(0.0, 1.0, 1.0)).x,
			star_hash(cell + vec3(1.0, 1.0, 1.0)).x, blend.x), blend.y);
	return mix(bottom, top, blend.z);
}

float star_disc(vec3 grid_position, vec3 center, float radius,
		float pixel_footprint) {
	float distance_to_star = length(fract(grid_position) - center);
	float soft_edge = clamp(pixel_footprint * 0.4, 0.018, 0.045);
	return 1.0 - smoothstep(radius * 0.4, radius + soft_edge,
		distance_to_star);
}

void sky() {
	// Ambient and reflections use a separate, fixed dim color. The procedural
	// detail is only drawn in the visible background pass.
	if (AT_CUBEMAP_PASS) {
		COLOR = vec3(0.0005, 0.0008, 0.0015);
	} else {
		vec3 direction = normalize(EYEDIR);
		float vision = clamp(night_vision, 0.0, 1.0);
		float star_time = star_time_override >= 0.0 ? star_time_override : TIME;

		// A tilted great-circle band has no projection seam. Two scales of
		// continuous 3D noise give its haze irregular, soft cloud structure.
		vec3 galactic_pole = normalize(vec3(0.48, 0.79, -0.38));
		float latitude = abs(dot(direction, galactic_pole));
		float wide_band = 1.0 - smoothstep(0.075, 0.31, latitude);
		float inner_band = 1.0 - smoothstep(0.018, 0.13, latitude);
		float cloud_shape = mix(cloud_noise(direction * 13.0),
			cloud_noise(direction * 31.0), 0.30);
		float mottling = smoothstep(0.18, 0.82, cloud_shape);
		float galactic_haze = (wide_band * 0.42 + inner_band * 0.58)
			* mix(0.58, 0.95, mottling) * vision * vision;
		// Small fixed screen-pixel dither breaks up Mobile HDR haze steps. It is
		// applied only inside the band, leaving the black sky and stars intact.
		vec2 pixel_size = max(fwidth(SCREEN_UV), vec2(0.000001));
		vec2 screen_pixel = floor(SCREEN_UV / pixel_size);
		float dither = fract(sin(dot(screen_pixel, vec2(12.9898, 78.233)))
			* 43758.5453) - 0.5;
		vec3 haze = vec3(0.013, 0.021, 0.039) * galactic_haze;
		haze = max(haze + vec3(dither * 0.003
			* clamp(galactic_haze * 3.0, 0.0, 1.0)), vec3(0.0));
		vec3 color = vec3(0.0004, 0.0007, 0.0015)
			+ haze;

		// Large, rare anchor stars persist after clear-light adaptation. Their
		// independent phases produce a subtle slow sparkle, never a field-wide blink.
		vec3 anchor_grid = direction * 76.0;
		float anchor_footprint = length(fwidth(anchor_grid));
		vec3 anchor_cell = floor(anchor_grid);
		vec3 anchor_random = star_hash(anchor_cell);
		if (anchor_random.x > 0.994) {
			vec3 anchor_detail = star_hash(anchor_cell + vec3(19.1, 43.7, 81.3));
			vec3 anchor_center = mix(vec3(0.34), vec3(0.66), anchor_detail);
			float anchor_radius = mix(0.23, 0.29, anchor_random.y);
			float anchor_disc = star_disc(anchor_grid, anchor_center,
				anchor_radius, anchor_footprint);
			float twinkle_speed = mix(0.28, 0.48, anchor_detail.z);
			float twinkle = 0.94 + 0.06 * sin(star_time * twinkle_speed
				+ TAU * anchor_random.z);
			float anchor_brightness = mix(1.15, 2.15, anchor_detail.y);
			vec3 anchor_tint = mix(vec3(0.70, 0.84, 1.0),
				vec3(1.0, 0.96, 0.83), anchor_detail.x);
			color += anchor_tint * anchor_disc * anchor_brightness * twinkle;
		}

		// A second, independent scale supplies many dimmer stars. Each candidate
		// has its own reveal threshold, so dark adaptation fills the sky gradually.
		vec3 small_grid = direction * 180.0;
		float small_footprint = length(fwidth(small_grid));
		vec3 small_cell = floor(small_grid);
		vec3 small_random = star_hash(small_cell + vec3(7.3, 29.1, 53.7));
		float density_threshold = mix(0.875, 0.76,
			wide_band * mix(0.35, 1.0, mottling));
		if (small_random.x > density_threshold) {
			vec3 small_detail = star_hash(small_cell + vec3(71.2, 11.5, 103.9));
			vec3 small_center = mix(vec3(0.28), vec3(0.72), small_detail);
			float small_radius = mix(0.13, 0.21, small_random.z);
			float small_disc = star_disc(small_grid, small_center,
				small_radius, small_footprint);
			float reveal_at = 0.14 + 0.75 * small_random.y;
			float revealed = smoothstep(reveal_at - 0.12,
				reveal_at + 0.12, vision);
			float small_brightness = mix(0.10, 0.62,
				small_detail.z * small_detail.z);
			vec3 small_tint = mix(vec3(0.63, 0.79, 1.0),
				vec3(1.0, 0.96, 0.86), small_detail.x);
			color += small_tint * small_disc * small_brightness * revealed;
		}
		COLOR = color;
	}
}
