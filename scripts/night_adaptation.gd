class_name NightAdaptation
extends RefCounted

## A deliberately small visual-only dark adaptation state. It never changes
## LightField stimulus or the GPU simulation.
const LIGHT_TIME_SECONDS := 1.5
const DARK_TIME_SECONDS := 6.0

var night_vision: float = 1.0

func target(mode: LightField.Mode, openness: float, viewer_exposure: float = 1.0) -> float:
	# A parked lamp can remain open and affect mushi after the viewer walks away.
	# This authored exposure factor only changes the viewer's visual adaptation.
	var open := clampf(openness, 0.0, 1.0) * clampf(viewer_exposure, 0.0, 1.0)
	if mode == LightField.Mode.CLEAR:
		return 1.0 - open
	return 1.0 - open * 0.25

func advance(delta: float, mode: LightField.Mode, openness: float, viewer_exposure: float = 1.0) -> float:
	if delta <= 0.0:
		return night_vision
	var destination := target(mode, openness, viewer_exposure)
	var seconds := DARK_TIME_SECONDS if destination > night_vision else LIGHT_TIME_SECONDS
	night_vision = clampf(lerpf(night_vision, destination, 1.0 - exp(-delta / seconds)), 0.0, 1.0)
	return night_vision

func lantern_gain() -> float:
	return 1.0 + 0.7 * night_vision


static func multiplayer_target(local_field: LightField, peer_fields: Array[LightField], viewer_position: Vector3) -> float:
	"""Compute viewer adaptation from nearby lanterns, independent of beam aim.

	Clear sources add as illuminance; filtered sources are capped at the strongest
	single filtered lamp. This is visual-only and intentionally ignores cone and
	occlusion so standing beside a lantern affects adaptation even outside its beam.
	"""
	var clear_remaining := 1.0
	var strongest_filtered := 0.0
	if local_field != null:
		var accumulated := _accumulate_exposure(local_field, viewer_position, clear_remaining, strongest_filtered)
		clear_remaining = accumulated.x
		strongest_filtered = accumulated.y
	for field: LightField in peer_fields:
		if field != null:
			var accumulated := _accumulate_exposure(field, viewer_position, clear_remaining, strongest_filtered)
			clear_remaining = accumulated.x
			strongest_filtered = accumulated.y
	var clear_exposure := 1.0 - clear_remaining
	var combined := 1.0 - (1.0 - clear_exposure) * (1.0 - strongest_filtered)
	return 1.0 - clampf(combined, 0.0, 1.0)


static func _accumulate_exposure(field: LightField, viewer_position: Vector3,
		clear_remaining: float, strongest_filtered: float) -> Vector2:
	# An open colored lamp must suppress the stream throughout the useful
	# nearby beam. A wide plateau also avoids partial stream reveal when the
	# viewer moves around within that light. Clear keeps its existing falloff.
	var radial := 1.0 - smoothstep(3.0 if field.mode == LightField.Mode.CLEAR else 8.0,
		14.0, viewer_position.distance_to(field.source_position))
	var exposure := clampf(field.shutter_openness * field.mode_strength * radial, 0.0, 1.0)
	if field.mode == LightField.Mode.CLEAR:
		clear_remaining *= 1.0 - exposure
	else:
		strongest_filtered = maxf(strongest_filtered, exposure)
	return Vector2(clear_remaining, strongest_filtered)
