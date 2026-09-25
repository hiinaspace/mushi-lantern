class_name MushiStaffGrabPoint
extends XRToolsGrabPointHand

## XR Tools uses an old aim-pose correction (+10 cm local Z) both for the
## physical grab transform and the snapped hand target. This staff uses grip
## poses; cancel the legacy offset in both frames so the shaft, rendered hand,
## controller rope attachment and grip point stay coincident.
func get_palm_transform(global: bool = false) -> Transform3D:
	var pose := super.get_palm_transform(global)
	pose.origin -= pose.basis.z * 0.10
	return pose
