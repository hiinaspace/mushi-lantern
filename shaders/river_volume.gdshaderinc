// Shared eye-ray river evaluator. Opaque receivers retain normal depth.
uniform sampler2D river_path_map : filter_linear, repeat_disable;
uniform float river_size = 640.0;
uniform float river_length = 600.0;
uniform float river_plane_y = -30.0;
uniform vec2 river_goal_xz = vec2(0.0);
uniform float river_night_vision = 0.0;
uniform float river_mote_motion = 1.0;
uniform float river_tube_enabled = 1.0;

float river_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float river_spark(vec2 uv, float threshold, vec2 dx, vec2 dy) {
	vec2 cell = floor(uv);
	float seed = river_hash(cell);
	vec2 center = vec2(0.5) + vec2(river_hash(cell + vec2(19.0, 3.0)), river_hash(cell + vec2(7.0, 23.0))) * 0.36 - 0.18;
	// Invert the local UV-to-pixel Jacobian so a mote stays a tiny round dot.
	// A near-singular UV projection already places the point offscreen; do not
	// erase neighboring dots with a separate determinant threshold.
	float determinant = dx.x * dy.y - dy.x * dx.y;
	vec2 delta = fract(uv) - center;
	vec2 pixel_delta = vec2((dy.y * delta.x - dy.x * delta.y),
		(-dx.y * delta.x + dx.x * delta.y)) / max(abs(determinant), 0.0005);
	float radius = mix(0.82, 1.35, river_hash(cell + vec2(41.0, 11.0)));
	float point = 1.0 - smoothstep(radius - 0.35, radius + 0.35, length(pixel_delta));
	return smoothstep(threshold, threshold + 0.09, seed) * point;
}

float river_center_y(vec2 offset) {
	float unit = offset.x / 28.0;
	float shoulder = max(1.0 - unit * unit, 0.0);
	return river_plane_y + 14.0 * shoulder * shoulder * shoulder;
}

float river_center_slope(float x) {
	float unit = x / 28.0;
	float shoulder = max(1.0 - unit * unit, 0.0);
	return -3.0 * unit * shoulder * shoulder;
}

float river_center_curvature(float x) {
	float unit = x / 28.0;
	float shoulder = max(1.0 - unit * unit, 0.0);
	return -0.10714286 * (shoulder * shoulder - 4.0 * unit * unit * shoulder);
}

float river_radius(float x) {
	// Slow traveling lobes and waists change the silhouette independently of
	// the much faster motes. All chords sample this same continuous function.
	float crest = 1.0 - smoothstep(5.0, 34.0, abs(x));
	return 3.9 - 1.5 * crest + 0.55 * sin(x * 0.14 - TIME * 0.36)
		+ 0.22 * sin(x * 0.33 + TIME * 0.20);
}

// Beyond the texture, the nearly straight arms continue analytically.
vec4 river_route(vec2 hit) {
	vec2 offset = hit - river_goal_xz;
	float endpoint = river_size * 0.45;
	if (abs(offset.x) > endpoint) {
		float extra = abs(offset.x) - endpoint;
		float z_center = -2.0;
		float lateral = offset.y - z_center;
		float progress = offset.x < 0.0 ? -extra / river_length : 1.0 + extra / river_length;
		return vec4(progress, lateral, 0.0, abs(lateral));
	}
	return texture(river_path_map, (hit + vec2(river_size * 0.5)) / river_size);
}

// Beyond the local grove, project a faint continuation onto the opaque
// country itself. This carries the last arm up the silhouetted ridge toward
// the skyline while the close tube still supplies the actual depth/parallax.
vec3 river_horizon_tail(vec3 receiver_world) {
	float vision = smoothstep(0.56, 0.94, river_night_vision);
	float arm_x = abs(receiver_world.x - river_goal_xz.x);
	if (vision < 0.001 || arm_x < river_size * 0.06) { return vec3(0.0); }
	vec4 route = river_route(receiver_world.xz);
	float band = 1.0 - smoothstep(1.3, 4.0, route.w);
	float start = smoothstep(river_size * 0.06, river_size * 0.12, arm_x);
	float end = 1.0 - smoothstep(2300.0, 3000.0, arm_x);
	vec2 uv = vec2(route.x * river_length * 1.7 - TIME * river_mote_motion * 0.56, route.y * 2.6);
	vec2 dx = dFdx(uv);
	vec2 dy = dFdy(uv);
	float footprint = max(length(vec2(dx.x, dy.x)), length(vec2(dx.y, dy.y)));
	float dots = river_spark(uv, 0.77, dx, dy) * (1.0 - smoothstep(0.28, 0.85, footprint));
	return vec3(0.949, 0.800, 0.196) * vision * band * start * end * (0.065 + 0.32 * dots);
}


// Returns (entry distance, coordinate along segment).
// Overlapping finite side tests catch silhouette rays without relying on a
// center-sheet crossing.
vec2 river_segment_hit(vec3 eye, vec3 ray, float receiver_t,
        vec3 a, vec3 b, float shell_offset) {
    vec3 axis = b - a;
    float length_m = length(axis);
    vec3 tangent = axis / max(length_m, 0.0001);
    vec3 origin = eye - a;
    float along_eye = dot(origin, tangent);
    float along_ray = dot(ray, tangent);
    vec3 radial = origin - tangent * along_eye;
    vec3 radial_ray = ray - tangent * along_ray;
    float aa = dot(radial_ray, radial_ray);
    float bb = dot(radial, radial_ray);
    float best_t = 4000.0;
    float best_u = 0.0;
    float local_x = a.x - river_goal_xz.x;
    if (aa > 0.000001) {
        float closest_t = max(-bb / aa, receiver_t + 0.03);
        local_x += along_eye * tangent.x + along_ray * closest_t * tangent.x;
    }
    float radius = max(river_radius(local_x) - shell_offset, 0.2);
    if (aa > 0.000001) {
        float discriminant = bb * bb - aa * (dot(radial, radial) - radius * radius);
        if (discriminant >= 0.0) {
            float root = sqrt(discriminant);
            float near_t = (-bb - root) / aa;
            float far_t = (-bb + root) / aa;
            float near_u = along_eye + along_ray * near_t;
            float far_u = along_eye + along_ray * far_t;
            if (near_t > receiver_t + 0.03 && near_u >= -0.55 && near_u <= length_m + 0.55) {
                best_t = near_t;
                best_u = clamp(near_u, 0.0, length_m);
            } else if (far_t > receiver_t + 0.03 && far_u >= -0.55 && far_u <= length_m + 0.55) {
                best_t = far_t;
                best_u = clamp(far_u, 0.0, length_m);
            }
        }
    }
    return vec2(best_t, best_u);
}

float river_box_entry(vec3 eye, vec3 ray, vec3 minimum, vec3 maximum, float receiver_t) {
    float enter = receiver_t + 0.03;
    float leave = 4000.0;
    for (int axis = 0; axis < 3; axis++) {
        if (abs(ray[axis]) < 0.000001) {
            if (eye[axis] < minimum[axis] || eye[axis] > maximum[axis]) { return 4000.0; }
        } else {
            float a = (minimum[axis] - eye[axis]) / ray[axis];
            float b = (maximum[axis] - eye[axis]) / ray[axis];
            enter = max(enter, min(a, b));
            leave = min(leave, max(a, b));
        }
    }
    return leave >= enter ? enter : 4000.0;
}

float river_axis_q(vec3 surface, float seed_x) {
    float q = seed_x - river_goal_xz.x;
    float px = surface.x - river_goal_xz.x;
    for (int step = 0; step < 3; step++) {
        float height_error = river_center_y(vec2(q, 0.0)) - surface.y;
        float slope = river_center_slope(q);
        float curvature = river_center_curvature(q);
        float numerator = q - px + height_error * slope;
        float denominator = max(1.0 + slope * slope + height_error * curvature, 0.25);
        q -= clamp(numerator / denominator, -3.0, 3.0);
    }
    return q;
}

float river_angle_at(vec3 surface, float q) {
    vec3 axis = vec3(river_goal_xz.x + q, river_center_y(vec2(q, 0.0)),
        river_goal_xz.y - 2.0);
    vec3 tangent = normalize(vec3(1.0, river_center_slope(q), 0.0));
    vec3 binormal = normalize(cross(vec3(0.0, 0.0, 1.0), tangent));
    vec3 radial = surface - axis;
    return atan(dot(radial, binormal), radial.z);
}

float river_goal_beam(vec3 eye, vec3 ray, float receiver_t) {
    float beam = 0.0;
    float top_t = (0.0 - eye.y) / ray.y;
	float bottom_t = (river_plane_y + 13.0 - eye.y) / ray.y;
    float start_t = max(receiver_t + 0.02, top_t);
    if (bottom_t > start_t) {
        vec2 center = river_goal_xz + vec2(0.0, -1.0);
        float speed = dot(ray.xz, ray.xz);
        float closest_t = 0.5 * (start_t + bottom_t);
        if (speed > 0.00001) { closest_t = dot(center - eye.xz, ray.xz) / speed; }
        float beam_t = clamp(closest_t, start_t, bottom_t);
        float beam_y = eye.y + ray.y * beam_t;
		float down = clamp(-beam_y / 17.0, 0.0, 1.0);
        float width = mix(2.15, 4.25, down);
        float distance_m = length(eye.xz + ray.xz * beam_t - center);
        float softness = 1.0 - smoothstep(0.0, width, distance_m);
        float phase = fract(TIME / 5.4);
        float envelope = pow(sin(PI * phase), 2.0);
        float pulse = exp(-pow((down - phase) / 0.19, 2.0)) * envelope;
        beam = softness * smoothstep(0.0, 0.16, down)
            * (1.0 - smoothstep(0.86, 1.0, down)) * (0.065 + 0.12 * pulse);
    }
    return beam;
}

vec4 river_evaluate(vec3 eye, vec3 ray, float receiver_t) {
    float vision = smoothstep(0.56, 0.94, river_night_vision);
    float beam_vision = smoothstep(0.08, 0.52, river_night_vision);
    if (beam_vision < 0.001 || ray.y >= -0.0005) { return vec4(0.0); }
    if (river_tube_enabled < 0.5) {
        float beam_only = river_goal_beam(eye, ray, receiver_t);
        return vec4(vec3(0.949, 0.800, 0.196) * beam_vision * 0.44 * beam_only,
            beam_only);
    }
    float best_t = 4000.0;
    float best_u = 0.0;
    vec3 best_a = vec3(0.0);
    vec3 best_b = vec3(1.0, 0.0, 0.0);
    float best_valid = 0.0;
    // Straight arms take two constant-cost intersections.
    for (int arm = 0; arm < 2; arm++) {
        float x0 = arm == 0 ? -3000.0 : 40.0;
        float x1 = arm == 0 ? -40.0 : 3000.0;
        vec3 a = vec3(river_goal_xz.x + x0, river_plane_y, river_goal_xz.y - 2.0);
        vec3 b = vec3(river_goal_xz.x + x1, river_plane_y, river_goal_xz.y - 2.0);
        vec2 hit = river_segment_hit(eye, ray, receiver_t, a, b, 0.0);
        if (hit.x < best_t) {
            best_t = hit.x;
            best_u = hit.y;
            best_a = a;
            best_b = b;
            best_valid = 1.0;
        }
    }
    // Eight broad-phase boxes cover 32 short chords of the compact crest.
    // Most rays skip all boxes; a typical crest ray tests only one group.
    for (int group = 0; group < 8; group++) {
        float x0 = -40.0 + float(group) * 10.0;
        float x1 = x0 + 10.0;
        float y0 = river_center_y(vec2(x0, 0.0));
        float y1 = river_center_y(vec2(x1, 0.0));
        float top = max(y0, y1);
        if (x0 <= 0.0 && x1 >= 0.0) { top = river_plane_y + 25.0; }
        vec3 minimum = vec3(river_goal_xz.x + x0 - 3.8, min(y0, y1) - 3.8,
            river_goal_xz.y - 5.8);
        vec3 maximum = vec3(river_goal_xz.x + x1 + 3.8, top + 3.8,
            river_goal_xz.y + 1.8);
        if (river_box_entry(eye, ray, minimum, maximum, receiver_t) >= best_t) { continue; }
        for (int chord = 0; chord < 4; chord++) {
            float xa = x0 + float(chord) * 2.5;
            float xb = xa + 2.5;
            vec3 a = vec3(river_goal_xz.x + xa, river_center_y(vec2(xa, 0.0)),
                river_goal_xz.y - 2.0);
            vec3 b = vec3(river_goal_xz.x + xb, river_center_y(vec2(xb, 0.0)),
                river_goal_xz.y - 2.0);
            vec2 hit = river_segment_hit(eye, ray, receiver_t, a, b, 0.0);
            if (hit.x < best_t) {
                best_t = hit.x;
                best_u = hit.y;
                best_a = a;
                best_b = b;
                best_valid = 1.0;
            }
        }
    }
    float shell = 0.0;
    float stars = 0.0;
    float along = 0.0;
    float angle = 0.0;
    float inner_along = 0.0;
    float inner_angle = 0.0;
    float inner_valid = 0.0;
    float middle_along = 0.0;
    float middle_angle = 0.0;
    float middle_valid = 0.0;
    if (best_valid > 0.5) {
        vec3 tangent = normalize(best_b - best_a);
        vec3 axis_point = best_a + tangent * best_u;
        vec3 surface = eye + ray * best_t;
        float q = river_axis_q(surface, axis_point.x);
        angle = river_angle_at(surface, q);
        along = river_route(vec2(river_goal_xz.x + q, river_goal_xz.y - 2.0)).x * river_length;
        vec3 smooth_axis = vec3(river_goal_xz.x + q, river_center_y(vec2(q, 0.0)),
            river_goal_xz.y - 2.0);
        vec3 smooth_tangent = normalize(vec3(1.0, river_center_slope(q), 0.0));
        vec3 smooth_origin = eye - smooth_axis;
        smooth_origin -= smooth_tangent * dot(smooth_origin, smooth_tangent);
        vec3 smooth_ray = ray - smooth_tangent * dot(ray, smooth_tangent);
        float smooth_ray_sq = max(dot(smooth_ray, smooth_ray), 0.000001);
        float smooth_nearest_t = -dot(smooth_origin, smooth_ray) / smooth_ray_sq;
        float smooth_impact = length(smooth_origin + smooth_ray * smooth_nearest_t);
        float smooth_radius = river_radius(q);
        float body = 1.0 - smoothstep(smooth_radius * 0.16, smooth_radius, smooth_impact);
        float far_fade = 1.0 - smoothstep(2500.0, 3000.0,
            abs(q));
        shell = body * far_fade;
        // Distinct near, middle, and inner mote surfaces share the same
        // finite segment, but have their own animated UV lattices.
        vec2 middle_hit = river_segment_hit(eye, ray, receiver_t, best_a, best_b, 0.43);
        if (middle_hit.x < 4000.0) {
            vec3 middle_surface = eye + ray * middle_hit.x;
            float middle_q = river_axis_q(middle_surface, best_a.x + tangent.x * middle_hit.y);
            middle_angle = river_angle_at(middle_surface, middle_q);
            middle_along = river_route(vec2(river_goal_xz.x + middle_q,
                river_goal_xz.y - 2.0)).x * river_length;
            middle_valid = 1.0;
        }
        vec2 inner_hit = river_segment_hit(eye, ray, receiver_t, best_a, best_b, 0.88);
        if (inner_hit.x < 4000.0) {
            vec3 inner_surface = eye + ray * inner_hit.x;
            float inner_q = river_axis_q(inner_surface, best_a.x + tangent.x * inner_hit.y);
            inner_angle = river_angle_at(inner_surface, inner_q);
            inner_along = river_route(vec2(river_goal_xz.x + inner_q,
                river_goal_xz.y - 2.0)).x * river_length;
            inner_valid = 1.0;
        }
    }
    float motion = TIME * river_mote_motion;
    vec2 uv1 = vec2(inner_along * 1.7 - motion * 3.4,
        (inner_angle + inner_along * 0.08) * 1.25);
    vec2 uv2 = vec2(along * 3.7 - motion * 7.4,
        (angle + along * 0.08) * 2.4);
    vec2 uv3 = vec2(along * 7.3 - motion * 13.1,
        (angle + along * 0.08) * 4.0);
    vec2 uv4 = vec2(middle_along * 2.65 - motion * 5.3 + 13.7,
        (middle_angle - middle_along * 0.06) * 3.2 + 7.1);
    vec2 dx1 = dFdx(uv1), dy1 = dFdy(uv1);
    vec2 dx2 = dFdx(uv2), dy2 = dFdy(uv2);
    vec2 dx3 = dFdx(uv3), dy3 = dFdy(uv3);
    vec2 dx4 = dFdx(uv4), dy4 = dFdy(uv4);
    if (shell > 0.001) {
        float footprint1 = max(length(vec2(dx1.x, dy1.x)), length(vec2(dx1.y, dy1.y)));
        float footprint2 = max(length(vec2(dx2.x, dy2.x)), length(vec2(dx2.y, dy2.y)));
        float footprint3 = max(length(vec2(dx3.x, dy3.x)), length(vec2(dx3.y, dy3.y)));
        float footprint4 = max(length(vec2(dx4.x, dy4.x)), length(vec2(dx4.y, dy4.y)));
        float points = inner_valid * river_spark(uv1, 0.65, dx1, dy1)
            * (1.0 - smoothstep(0.28, 0.85, footprint1));
        points += 0.72 * river_spark(uv2, 0.75, dx2, dy2)
            * (1.0 - smoothstep(0.28, 0.85, footprint2));
        points += 0.48 * river_spark(uv3, 0.84, dx3, dy3)
            * (1.0 - smoothstep(0.28, 0.85, footprint3));
        points += 0.66 * middle_valid * river_spark(uv4, 0.72, dx4, dy4)
            * (1.0 - smoothstep(0.28, 0.85, footprint4));
        stars = shell * points;
    }
    float beam = river_goal_beam(eye, ray, receiver_t);
    vec3 gold = vec3(0.949, 0.800, 0.196);
    vec3 glow = gold * (vision * (0.075 * shell + 1.45 * stars) + beam_vision * 0.44 * beam);
    return vec4(glow, max(shell, beam));
}
