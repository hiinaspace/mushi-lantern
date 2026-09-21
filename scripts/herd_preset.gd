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
@export var baseline_arousal: float = 0.32
@export var arousal_response: float = 0.85

func copy_preset() -> HerdPreset:
	var result := HerdPreset.new()
	for property: StringName in [
		"preset_name", "social_enabled", "arousal_memory", "separation_weight",
		"alignment_weight", "cohesion_weight", "wander_weight", "light_weight",
		"obstacle_weight", "neighbor_radius", "separation_radius", "max_speed",
		"max_acceleration", "arrival_radius", "goal_repulsion_strength", "baseline_arousal", "arousal_response"
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
		"baseline_arousal": baseline_arousal,
		"arousal_response": arousal_response,
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

	return [plain, memory, independent]
