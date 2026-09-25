class_name EnergyVisual
extends RefCounted

# Readable state colors, independent of the current lantern filter.
static func color_for(energy: float, neutral: float = 0.45) -> Color:
	var e := clampf(energy, 0.0, 1.0)
	var middle := clampf(neutral, 0.2, 0.65)
	var blue := Color("2d64d2")
	var green := Color("4cd3aa")
	var yellow := Color("f2cc32")
	var orange := Color("e03818")
	if e <= middle:
		return blue.lerp(green, smoothstep(0.0, middle, e))
	if e <= 0.68:
		return green.lerp(yellow, smoothstep(middle, 0.68, e))
	return yellow.lerp(orange, smoothstep(0.68, 1.0, e))

static func state_name(energy: float, sleep_threshold: float) -> String:
	if energy <= sleep_threshold:
		return "DORMANT"
	if energy < 0.3:
		return "DROWSY"
	if energy < 0.65:
		return "WANDERING"
	return "AROUSED"
