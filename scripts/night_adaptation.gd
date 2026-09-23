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
