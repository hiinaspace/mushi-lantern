#[compute]
#version 450

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

// Six vec4 per stable creature ID. Read and write buffers are swapped after
// each fixed step, so every force samples the same previous snapshot.
layout(set = 0, binding = 0, std430) readonly buffer OldState { vec4 old_state[]; };
layout(set = 0, binding = 1, std430) writeonly buffer NewState { vec4 new_state[]; };
layout(set = 0, binding = 2, std430) readonly buffer Params { float p[]; };
layout(set = 0, binding = 3, std430) readonly buffer Traits { vec4 traits[]; };
layout(set = 0, binding = 4, std430) buffer Events { uint events[]; };
layout(set = 0, binding = 5, std430) readonly buffer Sources { vec4 sources[]; };
layout(set = 0, binding = 6, rgba32f) uniform writeonly image2D state_image;
layout(set = 0, binding = 7, std430) buffer CellCounts { uint cell_counts[]; };
layout(set = 0, binding = 8, std430) buffer CellIds { uint cell_ids[]; };
layout(set = 0, binding = 9, std430) buffer FormationChoices { ivec2 formation_choices[]; };
layout(push_constant, std430) uniform Phase { uint phase; } pc;

const int ACTIVE = 0;
const int COMMITTED = 1;
const int ASCENDING = 2;
const int RELEASED = 3;
const float PI = 3.14159265358979323846;
const int MAX_AGENTS = 2048;

float pf(int i) { return p[i]; }
vec3 pos(int i) { return old_state[i * 6].xyz; }
vec3 vel(int i) { return old_state[i * 6 + 1].xyz; }
float energy(int i) { return old_state[i * 6].w; }
int life(int i) { return int(round(old_state[i * 6 + 2].x)); }
vec4 trait0(int i) { return traits[i * 2]; }
vec4 trait1(int i) { return traits[i * 2 + 1]; }
float saturate(float v) { return clamp(v, 0.0, 1.0); }
vec3 limited(vec3 v, float maxlen) { float n = length(v); return n > maxlen && n > 0.0 ? v * maxlen / n : v; }
vec2 limited2(vec2 v, float maxlen) { float n = length(v); return n > maxlen && n > 0.0 ? v * maxlen / n : v; }
vec3 safe_normal(vec3 v) { float n = length(v); return n > 0.000001 ? v / n : vec3(0.0); }
vec2 safe_normal2(vec2 v) { float n = length(v); return n > 0.000001 ? v / n : vec2(0.0); }
float move_towards(float a, float b, float step_size) { return a + clamp(b - a, -step_size, step_size); }
float mobility(float e) { return smoothstep(pf(43), max(pf(43) + 0.001, pf(32)), e); }
float scatter(float e) { return pf(31) > 0.5 ? smoothstep(pf(32), 1.0, e) * saturate(pf(45)) : 0.0; }

ivec2 cell_of(vec3 xyz) { return ivec2(floor(xyz.xz / pf(68))); }

int grid_span() { return int(pf(69)) * 2; }

int cell_key(ivec2 cell) {
    int radius = int(pf(69));
    int span = grid_span();
    ivec2 translated = cell + ivec2(radius);
    if (translated.x < 0 || translated.y < 0 || translated.x >= span || translated.y >= span) return -1;
    return translated.x * span + translated.y;
}

// A cell owns one invocation. Scanning stable IDs in ascending order builds
// the same bucket order as the CPU reference without unordered atomics.
void build_cell(int key) {
    int span = grid_span();
    if (key >= span * span) return;
    int radius = int(pf(69));
    ivec2 cell = ivec2(key / span - radius, key % span - radius);
    uint size = 0u;
    for (int id = 0; id < int(pf(0)); id++) {
        if (life(id) != ACTIVE || cell_of(pos(id)) != cell) continue;
        cell_ids[key * MAX_AGENTS + int(size)] = uint(id);
        size++;
    }
    cell_counts[key] = size;
}

// Float floor-mod matches GDScript posmod for negative grid coordinates on
// the pinned Vulkan compiler; signed integer remainder did not.
int positive_mod(int a, int b) { return int(mod(float(a), float(b))); }

bool valid_partner(int id, int other, int role, float radius) {
    return other >= 0 && other < int(pf(0)) && life(other) == ACTIVE &&
        energy(other) > pf(43) + 0.04 && int(trait0(other).x) == role &&
        dot(pos(id) - pos(other), pos(id) - pos(other)) < radius * radius;
}

// Infrequent matching inspects the full bounded population, independently
// from the approximate boid sampler. Each role proposes at most one neighbor
// on either side. Reciprocal proposals below produce exclusive local slots.
void choose_formation(int id) {
    if (id >= int(pf(0))) return;
    ivec2 choices = ivec2(-1);
    if (life(id) != ACTIVE || energy(id) <= pf(43) + 0.04) {
        formation_choices[id] = choices;
        return;
    }
    int role = int(trait0(id).x);
    vec4 extra = old_state[id * 6 + 4];
    int before = int(round(extra.z)) - 1;
    int after = int(round(extra.w)) - 1;
    if (role > 0 && valid_partner(id, before, role - 1, 4.0)) choices.x = before;
    if (role < 2 && valid_partner(id, after, role + 1, 4.0)) choices.y = after;
    bool keep_before = choices.x >= 0;
    bool keep_after = choices.y >= 0;
    float nearest_before = 3.2 * 3.2;
    float nearest_after = 3.2 * 3.2;
    for (int other = 0; other < int(pf(0)); other++) {
        if (other == id || life(other) != ACTIVE || energy(other) <= pf(43) + 0.04) continue;
        int other_role = int(trait0(other).x);
        if (other_role != role - 1 && other_role != role + 1) continue;
        vec4 other_links = old_state[other * 6 + 4];
        int occupied = int(round(other_role == role - 1 ? other_links.w : other_links.z)) - 1;
        if (occupied >= 0 && occupied != id && valid_partner(other, occupied, role, 4.0)) continue;
        vec3 offset = pos(id) - pos(other);
        float distance_sq = dot(offset, offset);
        if (!keep_before && other_role == role - 1 && distance_sq < nearest_before) {
            nearest_before = distance_sq;
            choices.x = other;
        }
        if (!keep_after && other_role == role + 1 && distance_sq < nearest_after) {
            nearest_after = distance_sq;
            choices.y = other;
        }
    }
    formation_choices[id] = choices;
}

ivec2 linked_partners(int id) {
    if (pf(70) <= 0.0) return ivec2(-1);
    if (pf(73) > 0.5) {
        ivec2 choices = formation_choices[id];
        return ivec2(
            choices.x >= 0 && formation_choices[choices.x].y == id ? choices.x : -1,
            choices.y >= 0 && formation_choices[choices.y].x == id ? choices.y : -1);
    }
    vec4 extra = old_state[id * 6 + 4];
    return ivec2(int(round(extra.z)) - 1, int(round(extra.w)) - 1);
}

// Read the sorted buckets built in phase 0; preserve rotated probe ordinals,
// two sweeps, duplicate suppression, and accumulation order from the CPU.
void candidates_for(int id, out int selected[27]) {
    for (int k = 0; k < 27; k++) selected[k] = -1;
    if (int(pf(0)) <= 64) return;
    ivec2 origin = cell_of(pos(id));
    int bucket_counts[9];
    int probe_ids[27];
    for (int cell = 0; cell < 9; cell++) bucket_counts[cell] = 0;
    for (int probe = 0; probe < 27; probe++) probe_ids[probe] = -1;
    for (int x = -1; x <= 1; x++) {
        for (int z = -1; z <= 1; z++) {
            int cell = (x + 1) * 3 + z + 1;
            int key = cell_key(origin + ivec2(x, z));
            if (key < 0) continue;
            int n = int(cell_counts[key]);
            bucket_counts[cell] = n;
            if (n == 0) continue;
            int first_probes = min(2, n);
            for (int probe = 0; probe < first_probes; probe++) {
                int start = positive_mod(id * 17 + (origin.x + x) * 11 + (origin.y + z) * 31, n);
                int ordinal = (start + probe * max(1, n / first_probes)) % n;
                probe_ids[cell * 3 + probe] = int(cell_ids[key * MAX_AGENTS + ordinal]);
            }
            int start = positive_mod(id * 17 + (origin.x + x) * 11 + (origin.y + z) * 31 + 7, n);
            probe_ids[cell * 3 + 2] = int(cell_ids[key * MAX_AGENTS + start]);
        }
    }
    int selected_count = 0;
    int cap = max(4, int(pf(53)));
    for (int sweep = 0; sweep < 2; sweep++) {
        for (int cell = 0; cell < 9; cell++) {
            int probes = sweep == 0 ? min(2, bucket_counts[cell]) : (bucket_counts[cell] > 0 ? 1 : 0);
            for (int probe = 0; probe < probes; probe++) {
                if (selected_count >= cap) break;
                int other = probe_ids[cell * 3 + (sweep == 0 ? probe : 2)];
                if (other < 0 || other == id) continue;
                bool duplicate = false;
                for (int j = 0; j < selected_count; j++) if (selected[j] == other) duplicate = true;
                if (!duplicate && selected_count < 27) selected[selected_count++] = other;
            }
        }
    }
}

bool segment_circle(vec2 a, vec2 b, vec2 center, float radius) {
    vec2 segment = b - a;
    float len2 = dot(segment, segment);
    if (len2 <= 0.000001) return dot(a - center, a - center) < radius * radius;
    float t = clamp(dot(center - a, segment) / len2, 0.0, 1.0);
    vec2 d = a + t * segment - center;
    return dot(d, d) < radius * radius;
}

float light_sample(vec3 xyz) {
    if (int(pf(3)) == 0 || pf(13) <= 0.0001) return 0.0;
    vec3 source = vec3(pf(4), pf(5), pf(6));
    vec3 offset = xyz - source;
    float distance = length(offset);
    if (distance <= 0.001 || distance >= pf(7)) return 0.0;
    vec3 direction = normalize(vec3(pf(8), pf(9), pf(10)));
    float half_angle = radians(pf(11));
    float angular = smoothstep(cos(half_angle), cos(half_angle * (1.0 - pf(12))), dot(direction, offset / distance));
    if (angular <= 0.0) return 0.0;
    for (int i = 0; i < int(pf(66)); i++) {
        vec4 obstacle = sources[16 + i];
        if (segment_circle(source.xz, xyz.xz, obstacle.xy, obstacle.z)) return 0.0;
    }
    return saturate(pf(13) * angular * (1.0 - smoothstep(0.18, 1.0, distance / pf(7))));
}

void mushroom_field(vec3 xyz, vec3 velocity, out float exposure, out vec3 force) {
    exposure = 0.0;
    force = vec3(0.0);
    if (pf(31) < 0.5 || pf(36) <= 0.001) return;
    float total = 0.0;
    vec3 weighted = vec3(0.0);
    for (int i = 0; i < int(pf(65)); i++) {
        vec3 cap = vec3(sources[32 + i].x, 0.45, sources[32 + i].y);
        float d = length(xyz - cap);
        if (d >= pf(36)) continue;
        float weight = 1.0 - smoothstep(pf(36) * 0.18, pf(36), d);
        total += weight;
        weighted += cap * weight;
    }
    exposure = saturate(total);
    if (total <= 0.00001) return;
    vec3 to_center = weighted / total - xyz;
    float distance = length(to_center);
    if (distance <= 0.001) force = -velocity * pf(37) * exposure;
    else {
        vec3 desired = to_center / distance * pf(16) * 0.55 * smoothstep(0.0, pf(26) * 1.5, distance);
        force = (desired - velocity) * pf(37) * exposure;
    }
}

vec3 social_force(int id, int selected[27], vec3 xyz, vec3 velocity, float e, out float contagion) {
    vec3 separation = vec3(0.0);
    vec3 alignment = vec3(0.0);
    vec3 center = vec3(0.0);
    float affinity_sum = 0.0;
    float strongest = 0.0;
    int neighbors = 0;
    int crowded_neighbors = 0;
    vec3 crowded_center = vec3(0.0);
    ivec2 links = linked_partners(id);
    int before = links.x;
    int after = links.y;
    int grand_before = before >= 0 ? linked_partners(before).x : -1;
    int grand_after = after >= 0 ? linked_partners(after).y : -1;
    int me_type = int(trait0(id).x);
    float crowd_radius = min(pf(18), pf(19) * 2.0);
    int limit = int(pf(0)) <= 64 ? int(pf(0)) : 27;
    for (int k = 0; k < limit; k++) {
        int other = int(pf(0)) <= 64 ? k : selected[k];
        if (other < 0 || other == id || life(other) != ACTIVE) continue;
        vec3 offset = xyz - pos(other);
        float distance = length(offset);
        if (distance <= 0.0001 || distance > pf(18)) continue;
        float weight = 1.0 - distance / pf(18);
        strongest = max(strongest, max(0.0, energy(other) - pf(32)) * weight);
        if (pf(54) < 0.5) continue;
        int other_type = int(trait0(other).x);
        bool same_trio = other == before || other == after || other == grand_before || other == grand_after;
        if ((pf(70) > 0.0 || pf(71) > 0.0) && distance < crowd_radius && !same_trio) {
            crowded_neighbors++;
            crowded_center += pos(other);
        }
        float affinity = 1.0;
        vec3 desired_offset = vec3(0.0);
        if (pf(46) > 0.0) {
            float full_affinity = other_type == ((me_type + 1) % 3) ? 1.24 : (other_type == me_type ? 1.08 : 0.76);
            affinity = mix(1.0, full_affinity, pf(46));
            if (dot(vel(other), vel(other)) > 0.01)
                desired_offset = -normalize(vel(other)) * float(me_type - 1) * 0.22 * pf(46);
        }
        neighbors++;
        affinity_sum += affinity;
        alignment += vel(other) * affinity;
        center += (pos(other) + desired_offset) * affinity;
        if (distance < pf(19) && !same_trio)
            separation += offset / distance * (1.0 - distance / pf(19));
    }
    contagion = strongest <= 0.00001 ? 0.0 : pf(32) + strongest;
    vec3 cohesion = vec3(0.0);
    if (neighbors > 0) {
        alignment = alignment / affinity_sum - velocity;
        cohesion = limited(center / affinity_sum - xyz, 1.0);
    }
    float retention = 1.0 - scatter(e) * 0.82;
    vec3 formation = vec3(0.0);
    if (pf(70) > 0.0 && before >= 0 && life(before) == ACTIVE) {
        vec3 leader_velocity = vel(before);
        vec3 heading = dot(leader_velocity, leader_velocity) > 0.01 ? normalize(leader_velocity) : vec3(0.0, 0.0, -1.0);
        vec3 target = pos(before) - heading * 0.18;
        formation = limited(target - xyz, 2.0) * 4.0 + (leader_velocity - velocity) * 2.2;
    }
    vec3 pressure = vec3(0.0);
    int target_count = max(1, int(pf(72)));
    if (crowded_neighbors > target_count) {
        vec3 away = xyz - crowded_center / float(crowded_neighbors);
        if (dot(away, away) > 0.0001)
            pressure = normalize(away) * min(float(crowded_neighbors - target_count) / float(target_count), 1.5);
    }
    float broad_cohesion = 1.0 - min(pf(70), 1.0) * 0.75;
    vec3 broad_social = separation * pf(20) + pressure * pf(71) +
        (alignment * pf(21) * trait1(id).x + cohesion * pf(22) * trait0(id).w * broad_cohesion) * retention;
    if (pf(70) > 0.0 && before >= 0) broad_social *= 0.18;
    return broad_social + formation * pf(70);
}

vec3 wander_force(int id, vec3 xyz, float e, vec4 aux, vec4 phases) {
    float s = scatter(e);
    float t = pf(2);
    float phase = phases.y + t * (0.48 + float((id * 17) % 9) * 0.035);
    phase += s * (sin(t * 1.73 + phases.x * 1.31) * 1.05 + sin(t * 0.47 + phases.x * 2.17) * 0.62);
    float vertical_energy = smoothstep(pf(32), 1.0, e);
    float vertical = sin(t * (0.63 + float(id % 5) * 0.08) + phases.z) * 0.62 * mix(0.7, 1.65, vertical_energy);
    float flow = t * 0.16 + xyz.x * 0.035 - xyz.z * 0.027;
    vec3 direction = normalize(vec3(cos(phase) + sin(flow) * 0.38, vertical, sin(phase) + cos(flow * 1.17) * 0.38));
    float wake_boost = aux.w > 0.0 ? 2.6 : 1.0;
    vec4 links = old_state[id * 6 + 4];
    int before = int(round(links.z)) - 1;
    if (pf(73) > 0.5) {
        ivec2 choices = formation_choices[id];
        before = choices.x >= 0 && formation_choices[choices.x].y == id ? choices.x : -1;
    }
    float follower_scale = pf(70) > 0.0 && before >= 0 && life(before) == ACTIVE ? 0.35 : 1.0;
    return direction * pf(23) * pf(15) * mix(0.55, 1.45, e) * (1.0 + s * 3.2) * wake_boost * follower_scale;
}

vec3 lantern_force(vec3 xyz, vec3 velocity, float stimulus) {
    if (stimulus <= 0.0001 || int(pf(3)) == 0) return vec3(0.0);
    vec3 source = vec3(pf(4), pf(5), pf(6));
    vec3 target = source + vec3(pf(8), pf(9), pf(10)) * 3.0;
    target.y = clamp(target.y, pf(57), pf(58));
    if (int(pf(3)) == 2) target = source;
    vec3 to_target = target - xyz;
    float distance = length(to_target);
    if (distance <= 0.001) return -velocity * 0.8;
    vec3 direction = to_target / distance;
    if (int(pf(3)) == 2) {
        vec3 desired = -direction * pf(16);
        desired.y *= 0.35;
        return (desired - velocity) * pf(24) * stimulus * 0.62;
    }
    float speed = pf(16) * smoothstep(0.0, pf(26) * 2.2, distance);
    if (distance >= pf(26)) speed = max(speed, 1.05);
    return (direction * speed - velocity) * pf(24) * stimulus;
}

vec3 obstacle_force(vec3 xyz, vec3 velocity) {
    vec3 result = vec3(0.0);
    vec2 ahead = xyz.xz + velocity.xz * 0.75;
    for (int i = 0; i < int(pf(64)); i++) {
        vec4 obs = sources[i];
        vec2 offset = xyz.xz - obs.xy;
        float distance = length(offset);
        float safe_radius = obs.z + 0.8;
        if (distance < safe_radius && distance > 0.001) {
            float urgency = 1.0 - distance / safe_radius;
            result.xz += offset / distance * pf(25) * urgency * urgency;
        }
        vec2 ahead_offset = ahead - obs.xy;
        float ahead_distance = length(ahead_offset);
        if (ahead_distance < obs.z + 0.4 && ahead_distance > 0.001)
            result.xz += ahead_offset / ahead_distance * pf(25) * 0.75;
    }
    return result;
}

vec3 boundary_force(vec3 xyz) {
    vec3 result = vec3(0.0);
    float margin = pf(56) - 1.6;
    if (abs(xyz.x) > margin) result.x = -sign(xyz.x) * (abs(xyz.x) - margin) * 3.2;
    if (abs(xyz.z) > margin) result.z = -sign(xyz.z) * (abs(xyz.z) - margin) * 3.2;
    if (xyz.y < pf(57) + 0.45) result.y += (pf(57) + 0.45 - xyz.y) * 2.4;
    else if (xyz.y > pf(58) - 0.45) result.y -= (xyz.y - (pf(58) - 0.45)) * 2.4;
    return result;
}

vec3 flight_band_force(vec3 xyz, float e, float vertical_phase) {
    if (pf(31) > 0.5 && mobility(e) < 0.08) return vec3(0.0);
    float player_height = clamp(1.5, pf(57) + 0.35, pf(58) - 0.35);
    float vertical_energy = smoothstep(pf(32), 1.0, e);
    float headroom = max(0.0, pf(58) - player_height - 0.25);
    float excursion = headroom * mix(0.08, 0.82, vertical_energy);
    float orbit = sin(pf(2) * mix(0.18, 0.34, vertical_energy) + vertical_phase);
    float preferred = player_height + excursion * (0.25 + orbit * 0.75);
    return vec3(0.0, clamp((preferred - xyz.y) * mix(0.48, 0.72, vertical_energy), -1.25, 1.25), 0.0);
}

vec3 goal_resistance(vec3 xyz) {
    vec2 offset = xyz.xz - vec2(pf(59), pf(60));
    float distance = length(offset);
    float outer = max(0.0, pf(28));
    if (distance < 0.001 || distance >= pf(61) + outer || outer <= 0.001) return vec3(0.0);
    float strength = smoothstep(pf(61) - 0.8, pf(61), distance) * (1.0 - smoothstep(pf(61), pf(61) + outer, distance)) * pf(27);
    return vec3(offset.x / distance * strength, 0.0, offset.y / distance * strength);
}

void constrain_motion(vec3 start, inout vec3 velocity, inout vec3 position) {
    // Rocks and trunks are coarse cues; the jam scene tolerates small clips.
    // Push out only when the proposed new center is inside a proxy cylinder.
    position = start + velocity * pf(1);
    for (int i = 0; i < int(pf(64)); i++) {
        vec4 obs = sources[i];
        vec2 offset = position.xz - obs.xy;
        float distance = length(offset);
        float radius = obs.z + 0.10;
        if (distance < radius && distance > 0.001) {
            vec2 normal = offset / distance;
            position.xz = obs.xy + normal * radius;
            velocity.xz -= normal * min(dot(velocity.xz, normal), 0.0);
        }
    }
    float horizontal_limit = pf(56) - 0.10;
    vec2 bounded = clamp(position.xz, vec2(-horizontal_limit), vec2(horizontal_limit));
    if (bounded.x != position.x) velocity.x = 0.0;
    if (bounded.y != position.z) velocity.z = 0.0;
    position.xz = bounded;
    float height = clamp(position.y, pf(57), pf(58));
    if (height != position.y) velocity.y = 0.0;
    position.y = height;
}

void main() {
    int id = int(gl_GlobalInvocationID.x);
    if (pc.phase == 0u) { build_cell(id); return; }
    if (pc.phase == 1u) { choose_formation(id); return; }
    if (id >= int(pf(0))) return;
    vec4 old_p = old_state[id * 6];
    vec4 old_v = old_state[id * 6 + 1];
    vec4 aux = old_state[id * 6 + 2];
    vec4 phases = old_state[id * 6 + 3];
    vec4 extra = old_state[id * 6 + 4];
    if (pf(70) <= 0.0) extra.zw = vec2(0.0);
    if (pf(73) > 0.5) {
        ivec2 choices = formation_choices[id];
        extra.z = float(choices.x >= 0 && formation_choices[choices.x].y == id ? choices.x + 1 : 0);
        extra.w = float(choices.y >= 0 && formation_choices[choices.y].x == id ? choices.y + 1 : 0);
    }
    vec4 heading = old_state[id * 6 + 5];
    vec3 xyz = old_p.xyz;
    vec3 velocity = old_v.xyz;
    float e = old_p.w;
    float dt = pf(1);
    int lifecycle = int(round(aux.x));
    vec3 pre_update_wander = wander_force(id, xyz, e, aux, phases);
    aux.z += dt;
    vec3 next_pos = xyz;
    vec3 next_vel = velocity;

    if (lifecycle == COMMITTED) {
        vec3 target = vec3(pf(59), xyz.y, pf(60));
        next_pos = mix(xyz, target, 1.0 - exp(-dt * 4.0));
        next_vel = vec3(0.0);
        if (aux.z >= 0.22) { aux.x = float(ASCENDING); aux.z = 0.0; }
    } else if (lifecycle == ASCENDING) {
        vec3 target = vec3(pf(59), pf(58) + 1.0, pf(60));
        next_pos = mix(xyz, target, 1.0 - exp(-dt * 2.2));
        next_vel = vec3(0.0, 1.0, 0.0);
        if (aux.z >= 2.35) { aux.x = float(RELEASED); aux.z = 0.0; }
    } else if (lifecycle == ACTIVE) {
        int selected[27];
        candidates_for(id, selected);
        float contagion = 0.0;
        vec3 social = social_force(id, selected, xyz, velocity, e, contagion) * pf(14);
        float stimulus = light_sample(xyz);
        old_v.w = move_towards(pf(67) > 0.5 ? 0.0 : old_v.w, stimulus, dt * 4.0);
        float mushroom_exposure;
        vec3 mushroom_force;
        mushroom_field(xyz, velocity, mushroom_exposure, mushroom_force);
        extra.y = mushroom_exposure;

        if (pf(31) > 0.5) {
            float neutral = saturate(pf(32) + sin(pf(2) * pf(35) + phases.x) * pf(34) + trait1(id).w);
            float rate = max(0.0, pf(33));
            float weighted = rate * neutral;
            float mushroom_rate = max(0.0, pf(38)) * mushroom_exposure * trait1(id).z;
            rate += mushroom_rate;
            weighted += mushroom_rate * pf(39);
            if (int(pf(3)) == 1) {
                float blue_rate = max(0.0, pf(40)) * old_v.w * trait1(id).y;
                rate += blue_rate; weighted += blue_rate * pf(39);
            } else if (int(pf(3)) == 2) {
                float orange_rate = max(0.0, pf(42)) * old_v.w * trait1(id).y;
                rate += orange_rate; weighted += orange_rate * pf(41);
            }
            if (contagion > neutral) {
                float contagion_rate = pf(47) * smoothstep(neutral, 1.0, contagion) * 1.35;
                rate += contagion_rate; weighted += contagion_rate * min(0.78, contagion);
            }
            if (pf(48) > 0.5) {
                if (aux.w > 0.0) aux.w = max(0.0, aux.w - dt);
                else if (mushroom_exposure >= 0.35 && e <= pf(43) + 0.04) {
                    phases.w -= dt;
                    if (phases.w <= 0.0) {
                        aux.w = pf(51);
                        extra.x += 1.0;
                        float wake_phase = sin(pf(63) + float(id) * 7919.0 + extra.x * 104729.0) * 0.5 + 0.5;
                        phases.w = pf(49) + max(0.0, pf(50) - pf(49)) * wake_phase;
                    }
                }
            } else aux.w = 0.0;
            if (aux.w > 0.0) { rate += 2.2; weighted += 2.2 * pf(52); }
            if (rate > 0.00001) e = mix(e, weighted / rate, 1.0 - exp(-dt * rate));
            e = saturate(e);
        } else if (pf(55) < 0.5) e = pf(29);
        else {
            float target = pf(29);
            if (int(pf(3)) == 1) target = mix(target, 0.08, old_v.w);
            else if (int(pf(3)) == 2) target = mix(target, 0.92, old_v.w);
            float rate = old_v.w > 0.02 ? pf(30) : pf(30) * 0.32;
            e = mix(e, target, 1.0 - exp(-dt * rate));
        }

        int leader = int(round(extra.z)) - 1;
        bool coupled = pf(70) > 0.0 && leader >= 0 && life(leader) == ACTIVE;
        float follower_scale = coupled ? 0.5 : 1.0;
        vec3 force = pre_update_wander + social + lantern_force(xyz, velocity, old_v.w) * follower_scale;
        if (pf(31) > 0.5) {
            mushroom_force *= trait1(id).z;
            if (int(pf(3)) == 2) mushroom_force *= 1.0 - old_v.w * 0.85;
            if (aux.w > 0.0) mushroom_force *= 0.05;
            force += mushroom_force * follower_scale;
        }
        force += boundary_force(xyz) + flight_band_force(xyz, e, phases.z) + goal_resistance(xyz);
        vec3 avoidance = limited(obstacle_force(xyz, velocity), pf(17));
        force = avoidance + limited(force, max(0.0, pf(17) - length(avoidance)));
        if (pf(31) > 0.5) {
            float m = mobility(e);
            float sleeping = 1.0 - m;
            next_vel = velocity * exp(-dt * pf(44) * sleeping) + force * m * dt;
            next_vel.y -= sleeping * 1.25 * dt;
            float speed_cap = pf(16) * trait0(id).z * mix(0.06, mix(0.88, 1.18, e), m);
            if (coupled && m > 0.35)
                speed_cap = min(max(speed_cap, length(vel(leader)) + 0.35), pf(16) * 1.45 * 1.18 + 0.7);
            next_vel = limited(next_vel, speed_cap);
        } else next_vel = limited(velocity + force * dt, pf(16) * trait0(id).z * mix(0.88, 1.18, e));
        constrain_motion(xyz, next_vel, next_pos);
        if (distance(next_pos.xz, vec2(pf(59), pf(60))) <= pf(61)) {
            aux.y += dt;
            if (aux.y >= pf(62)) {
                aux.x = float(COMMITTED);
                aux.z = 0.0;
                events[id] = 1u;
            }
        } else aux.y = max(0.0, aux.y - dt * 2.0);
    }
    new_state[id * 6] = vec4(next_pos, e);
    new_state[id * 6 + 1] = vec4(next_vel, old_v.w);
    new_state[id * 6 + 2] = aux;
    new_state[id * 6 + 3] = phases;
    new_state[id * 6 + 4] = extra;
    if (dot(next_vel, next_vel) > 0.0025)
        heading.xyz = normalize(next_vel);
    new_state[id * 6 + 5] = heading;
    imageStore(state_image, ivec2(id, 0), vec4(xyz, lifecycle == RELEASED ? -1.0 : old_p.w));
    imageStore(state_image, ivec2(id, 1), vec4(next_pos, int(round(aux.x)) == RELEASED ? -1.0 : e));
    imageStore(state_image, ivec2(id, 2), heading);
}
