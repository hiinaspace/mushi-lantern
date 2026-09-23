class_name HerdPreset
extends Resource

@export var preset_name: String = "Plain boids"
@export var social_enabled: bool = true
@export var arousal_memory: bool = false
@export var separation_weight: float = 2.35
@export var alignment_weight: float = 0.55
@export var cohesion_weight: float = 0.48
@export var wander_weight: float = 0.34
@export var light_weight: float = 3.8
@export var obstacle_weight: float = 8.5
@export var neighbor_radius: float = 3.6
@export var separation_radius: float = 1.15
@export var max_speed: float = 2.55
@export var max_acceleration: float = 6.2
@export var arrival_radius: float = 1.65
@export var goal_repulsion_strength: float = 0.8
@export var goal_repulsion_outer_width: float = 1.8
@export var baseline_arousal: float = 0.32
@export var arousal_response: float = 0.85
@export var energy_dynamics: bool = false
@export var energy_neutral_target: float = 0.45
@export var energy_recovery_rate: float = 0.18
@export var energy_individuality: float = 0.035
@export var energy_individuality_rate: float = 0.42
@export var mushroom_radius: float = 3.4
@export var mushroom_attraction_weight: float = 1.7
@export var mushroom_suppression_rate: float = 1.8
@export var blue_energy_target: float = 0.04
@export var blue_energy_response: float = 0.65
@export var orange_energy_target: float = 0.96
@export var orange_energy_response: float = 8.0
@export var sleep_threshold: float = 0.16
@export var sleep_velocity_damping: float = 7.0
@export_range(0.0, 1.0, 0.01) var arousal_scatter_strength: float = 0.0
@export_range(0.0, 1.0, 0.01) var population_variation: float = 0.0
@export_range(0.0, 1.0, 0.01) var arousal_contagion_strength: float = 0.0
@export var spontaneous_waking_enabled: bool = false
@export var spontaneous_wake_min_seconds: float = 15.0
@export var spontaneous_wake_max_seconds: float = 70.0
@export var spontaneous_wake_duration: float = 4.0
@export_range(0.0, 1.0, 0.01) var spontaneous_wake_energy: float = 0.54
@export_range(4, 96, 1) var max_social_neighbors: int = 32
@export_range(0.0, 3.0, 0.05) var formation_follow_weight: float = 0.0
@export_range(0.0, 3.0, 0.05) var cluster_pressure_weight: float = 0.0
@export_range(1, 12, 1) var cluster_target_neighbors: int = 6

@export_range(2.0, 8.0, 0.1) var flight_max_height: float = 2.8
@export_range(0.25, 2.0, 0.05) var glyph_render_scale: float = 0.65
@export var glyph_billboard: bool = false

func copy_preset() -> HerdPreset:
	var result := HerdPreset.new()
	for property: StringName in [
		"preset_name", "social_enabled", "arousal_memory", "separation_weight",
		"alignment_weight", "cohesion_weight", "wander_weight", "light_weight",
		"obstacle_weight", "neighbor_radius", "separation_radius", "max_speed",
		"max_acceleration", "arrival_radius", "goal_repulsion_strength",
		"goal_repulsion_outer_width", "baseline_arousal", "arousal_response",
		"energy_dynamics", "energy_neutral_target", "energy_recovery_rate",
		"energy_individuality", "energy_individuality_rate", "mushroom_radius",
		"mushroom_attraction_weight", "mushroom_suppression_rate",
		"blue_energy_target", "blue_energy_response", "orange_energy_target",
		"orange_energy_response", "sleep_threshold", "sleep_velocity_damping",
		"arousal_scatter_strength", "population_variation", "arousal_contagion_strength",
		"spontaneous_waking_enabled", "spontaneous_wake_min_seconds",
		"spontaneous_wake_max_seconds", "spontaneous_wake_duration",
		"spontaneous_wake_energy", "max_social_neighbors",
		"formation_follow_weight", "cluster_pressure_weight", "cluster_target_neighbors",
		"flight_max_height", "glyph_render_scale", "glyph_billboard"
	]:
		result.set(property, get(property))
	return result

func to_dict() -> Dictionary:
	return {
		"preset_name": preset_name,
		"social_enabled": social_enabled,
		"arousal_memory": arousal_memory,
		"separation_weight": separation_weight,
		"alignment_weight": alignment_weight,
		"cohesion_weight": cohesion_weight,
		"wander_weight": wander_weight,
		"light_weight": light_weight,
		"obstacle_weight": obstacle_weight,
		"neighbor_radius": neighbor_radius,
		"separation_radius": separation_radius,
		"max_speed": max_speed,
		"max_acceleration": max_acceleration,
		"arrival_radius": arrival_radius,
		"goal_repulsion_strength": goal_repulsion_strength,
		"goal_repulsion_outer_width": goal_repulsion_outer_width,
		"baseline_arousal": baseline_arousal,
		"arousal_response": arousal_response,
		"energy_dynamics": energy_dynamics,
		"energy_neutral_target": energy_neutral_target,
		"energy_recovery_rate": energy_recovery_rate,
		"energy_individuality": energy_individuality,
		"energy_individuality_rate": energy_individuality_rate,
		"mushroom_radius": mushroom_radius,
		"mushroom_attraction_weight": mushroom_attraction_weight,
		"mushroom_suppression_rate": mushroom_suppression_rate,
		"blue_energy_target": blue_energy_target,
		"blue_energy_response": blue_energy_response,
		"orange_energy_target": orange_energy_target,
		"orange_energy_response": orange_energy_response,
		"sleep_threshold": sleep_threshold,
		"sleep_velocity_damping": sleep_velocity_damping,
		"arousal_scatter_strength": arousal_scatter_strength,
		"population_variation": population_variation,
		"arousal_contagion_strength": arousal_contagion_strength,
		"spontaneous_waking_enabled": spontaneous_waking_enabled,
		"spontaneous_wake_min_seconds": spontaneous_wake_min_seconds,
		"spontaneous_wake_max_seconds": spontaneous_wake_max_seconds,
		"spontaneous_wake_duration": spontaneous_wake_duration,
		"spontaneous_wake_energy": spontaneous_wake_energy,
		"max_social_neighbors": max_social_neighbors,
		"formation_follow_weight": formation_follow_weight,
		"cluster_pressure_weight": cluster_pressure_weight,
		"cluster_target_neighbors": cluster_target_neighbors,
		"flight_max_height": flight_max_height,
		"glyph_render_scale": glyph_render_scale,
		"glyph_billboard": glyph_billboard,
	}

static func from_dict(data: Dictionary) -> HerdPreset:
	var result := HerdPreset.new()
	for property: String in data.keys():
		if property in result.to_dict():
			result.set(property, data[property])
	return result

static func builtins() -> Array[HerdPreset]:
	var plain := HerdPreset.new()
	plain.preset_name = "Plain boids"

	var memory := plain.copy_preset()
	memory.preset_name = "Arousal memory"
	memory.arousal_memory = true

	var independent := plain.copy_preset()
	independent.preset_name = "Independent seekers"
	independent.social_enabled = false
	independent.separation_weight = 0.0
	independent.alignment_weight = 0.0
	independent.cohesion_weight = 0.0

	var energy := plain.copy_preset()
	energy.preset_name = "Energy recovery"
	energy.energy_dynamics = true
	energy.arousal_memory = true
	energy.baseline_arousal = 0.45
	energy.goal_repulsion_strength = 0.48
	energy.goal_repulsion_outer_width = 4.2
	energy.arousal_scatter_strength = 0.8

	var lingering := energy.copy_preset()
	lingering.preset_name = "Lingering energy"
	lingering.energy_recovery_rate = 0.07

	var living := energy.copy_preset()
	living.preset_name = "Living shoals"
	living.flight_max_height = 4.5
	living.population_variation = 0.65
	living.arousal_contagion_strength = 0.35
	living.spontaneous_waking_enabled = true

	var longer_drift := living.copy_preset()
	longer_drift.preset_name = "Longer drift"
	longer_drift.separation_weight = 2.35
	longer_drift.alignment_weight = 0.55
	longer_drift.cohesion_weight = 0.48
	longer_drift.wander_weight = 0.34
	longer_drift.light_weight = 3.8
	longer_drift.obstacle_weight = 8.5
	longer_drift.neighbor_radius = 3.6
	longer_drift.separation_radius = 1.15
	longer_drift.max_speed = 2.55
	longer_drift.max_acceleration = 6.2
	longer_drift.arrival_radius = 1.65
	longer_drift.goal_repulsion_strength = 0.48
	longer_drift.goal_repulsion_outer_width = 4.2
	longer_drift.baseline_arousal = 0.45
	longer_drift.arousal_response = 0.85
	longer_drift.energy_dynamics = true
	longer_drift.energy_neutral_target = 0.45
	longer_drift.energy_recovery_rate = 0.18
	longer_drift.energy_individuality = 0.035
	longer_drift.energy_individuality_rate = 0.42
	longer_drift.mushroom_radius = 3.4
	longer_drift.mushroom_attraction_weight = 1.0
	longer_drift.mushroom_suppression_rate = 1.8
	longer_drift.blue_energy_target = 0.04
	longer_drift.blue_energy_response = 0.365489697300642
	longer_drift.orange_energy_target = 0.96
	longer_drift.orange_energy_response = 1.457332337338
	longer_drift.sleep_threshold = 0.16
	longer_drift.sleep_velocity_damping = 7.0
	longer_drift.arousal_scatter_strength = 0.4
	longer_drift.population_variation = 0.65
	longer_drift.arousal_contagion_strength = 0.5
	longer_drift.spontaneous_waking_enabled = true
	longer_drift.spontaneous_wake_min_seconds = 15.0
	longer_drift.spontaneous_wake_max_seconds = 70.0
	longer_drift.spontaneous_wake_duration = 4.0
	longer_drift.spontaneous_wake_energy = 0.54
	longer_drift.max_social_neighbors = 32
	longer_drift.flight_max_height = 4.5
	longer_drift.glyph_render_scale = 0.4
	longer_drift.glyph_billboard = false

	var drifting_trains := longer_drift.copy_preset()
	drifting_trains.preset_name = "Drifting trains"
	drifting_trains.formation_follow_weight = 1.35
	drifting_trains.cluster_pressure_weight = 1.0
	drifting_trains.cluster_target_neighbors = 2

	var loose_trains := longer_drift.copy_preset()
	loose_trains.preset_name = "Loose trains"
	loose_trains.formation_follow_weight = 0.55
	loose_trains.cluster_pressure_weight = 1.1
	loose_trains.cluster_target_neighbors = 2
	loose_trains.arousal_contagion_strength = 0.45
	loose_trains.arousal_scatter_strength = 0.65
	loose_trains.glyph_render_scale = 0.6

	return [plain, memory, independent, energy, lingering, living, longer_drift, drifting_trains, loose_trains]
