extends Node3D

func _ready() -> void:
	var point := MushiStaffGrabPoint.new()
	point.hand = XRToolsGrabPointHand.Hand.RIGHT
	add_child(point)
	point.position = Vector3(0, -0.18, 0)
	var physical := point.get_palm_transform(false)
	var visual := point.get_palm_transform(true)
	assert(is_zero_approx(physical.origin.z))
	assert(is_zero_approx(visual.origin.z))
	assert(is_equal_approx(visual.origin.y, -0.23))
	print("PASS staff shaft grip and snapped palm coincide at controller rope anchor")
	get_tree().quit()
