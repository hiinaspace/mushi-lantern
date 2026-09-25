class_name MushiVoice
extends Node

## Voice is routed over MushiNetwork's unreliable encrypted channel. A remote
## stream belongs to its speaker's head so body and voice remain co-located.
var network: Node
var sender: Node
var visemes: Node
var players: Dictionary = {}
var transmitting := false
var input_gain_db := 0.0
var gate_threshold_db := -38.0
var listener_camera: Camera3D
var receive_gain := 1.0
var receive_gain_db := 0.0
var near_radius := 3.0
var far_radius := 18.0
var _diag_clock := 0.0
var _session_active := false


func setup(session: Node, _old_transmit_default: bool) -> void:
	network = session
	# A connected room always starts receive-only unless a local test explicitly
	# opts in. Keep the old parameter while main's setup call is migrated.
	var default_unmuted := OS.get_environment("MUSHI_VOICE_UNMUTED") == "1" or OS.get_environment("MUSHI_VOICE_TRANSMIT") == "1"
	if not ClassDB.class_exists("NetworkAudioSender"):
		push_error("Voice codec is unavailable")
		return
	sender = ClassDB.instantiate("NetworkAudioSender")
	sender.name = "VoiceSender"
	sender.capture_on_worker = true
	sender.set_input_gain_db(input_gain_db)
	sender.set_gate_threshold_db(gate_threshold_db)
	sender.set_transmit_enabled(false)
	add_child(sender)
	sender.stop_capture()
	sender.encoder_error.connect(func(message: String):
		push_warning("Microphone: " + message)
		set_transmit(false))
	if ClassDB.class_exists("MushiVisemes"):
		visemes = ClassDB.instantiate("MushiVisemes")
		visemes.name = "Visemes"
		add_child(visemes)
		visemes.attach_local(sender)
	set_muted(not default_unmuted)


func session_ready() -> void:
	_session_active = true
	if network != null and sender != null:
		network.attach_voice_sender(sender)
		# Capture locally for the pre-gate meter even while network-muted.
		sender.start_capture()


func peer_joined(peer_id: String, head: Node3D) -> void:
	if _session_active and sender != null and not sender.is_capturing():
		sender.start_capture()
	if network == null or players.has(peer_id):
		return
	var stream: AudioStream = network.receive_voice_stream(peer_id)
	if stream == null:
		return
	var steam := ClassDB.class_exists("SteamAudioPlayer")
	var player: AudioStreamPlayer3D = ClassDB.instantiate("SteamAudioPlayer") if steam else AudioStreamPlayer3D.new()
	player.name = "RemoteVoice"
	player.bus = "Master"
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	if steam:
		player.set("point_source_binaural", true)
		player.set("ambisonics", true)
		player.set("distance_attenuation", false)
		player.set("occlusion", false)
		player.set("air_absorption", false)
		player.set("attenuation_filter_db", 0.0)
		player.set("panning_strength", 0.0)
	head.add_child(player)
	if steam:
		player.call("play_stream", stream)
	else:
		player.stream = stream
		player.play()
	players[peer_id] = player
	if visemes != null:
		visemes.attach_remote(peer_id, stream)


func peer_left(peer_id: String) -> void:
	var player: AudioStreamPlayer3D = players.get(peer_id)
	if player != null and is_instance_valid(player):
		player.stop()
		player.queue_free()
	players.erase(peer_id)
	if visemes != null:
		visemes.remove_source(peer_id)


func stop_session() -> void:
	_session_active = false
	if sender != null:
		sender.stop_capture()
	if visemes != null:
		visemes.reset_source("local")
	for peer_id in players.keys():
		peer_left(peer_id)


func set_transmit(enabled: bool) -> void:
	set_muted(not enabled)


func set_muted(muted: bool) -> void:
	var enabled := not muted
	transmitting = enabled
	if sender == null:
		return
	sender.set_transmit_enabled(enabled)
	if _session_active:
		sender.start_capture()
	else:
		sender.stop_capture()
	if not enabled and visemes != null:
		visemes.reset_source("local")


func is_muted() -> bool:
	return not transmitting


func get_input_devices() -> PackedStringArray:
	return AudioServer.get_input_device_list()


func get_input_device() -> String:
	return AudioServer.input_device


func set_input_device(device: String) -> void:
	if device.is_empty() or not get_input_devices().has(device):
		return
	var was_capturing: bool = sender != null and sender.is_capturing()
	if sender != null:
		sender.stop_capture()
	AudioServer.input_device = device
	if was_capturing and sender != null:
		sender.start_capture()


func set_input_gain_db(db: float) -> void:
	if not is_finite(db):
		return
	input_gain_db = clampf(db, -30.0, 24.0)
	if sender != null:
		sender.set_input_gain_db(input_gain_db)


func get_input_gain_db() -> float:
	return input_gain_db


func set_gate_threshold_db(db: float) -> void:
	if not is_finite(db):
		return
	gate_threshold_db = clampf(db, -60.0, -20.0)
	if sender != null:
		sender.set_gate_threshold_db(gate_threshold_db)


func get_gate_threshold_db() -> float:
	return gate_threshold_db


func get_input_meter_db() -> float:
	if sender == null or not sender.is_capturing():
		return -80.0
	return clampf(float(sender.get_input_rms_db()), -80.0, 0.0)


func get_input_meter_level() -> float:
	return clampf((get_input_meter_db() + 60.0) / 60.0, 0.0, 1.0)


func set_receive_gain_db(db: float) -> void:
	if not is_finite(db):
		return
	receive_gain_db = clampf(db, -30.0, 12.0)
	receive_gain = db_to_linear(receive_gain_db)


func get_receive_gain_db() -> float:
	return receive_gain_db


func get_peer_level(peer_id: String) -> float:
	return clampf(float(network.get_voice_level(peer_id)), 0.0, 1.0) if network != null else 0.0


func get_local_level() -> float:
	if not transmitting or sender == null or not sender.is_capturing():
		return 0.0
	return clampf(db_to_linear(float(sender.get_gated_rms_db())) * 5.0, 0.0, 1.0)


func get_peer_visemes(peer_id: String) -> PackedFloat32Array:
	if visemes != null and visemes.get_status() == "ready":
		return visemes.get_weights(peer_id)
	return _mouth_weights(get_peer_level(peer_id))


func get_local_visemes() -> PackedFloat32Array:
	if not transmitting:
		return _mouth_weights(0.0)
	if visemes != null and visemes.get_status() == "ready":
		return visemes.get_weights("local")
	return _mouth_weights(get_local_level())


func set_listener_camera(camera: Camera3D) -> void:
	listener_camera = camera


func _process(delta: float) -> void:
	if OS.get_environment("MUSHI_VOICE_DIAG") == "1":
		_diag_clock += delta
		if _diag_clock >= 1.0:
			_diag_clock = 0.0
			var remote_levels := {}
			for peer_id in players.keys():
				remote_levels[peer_id] = snappedf(get_peer_level(peer_id), 0.01)
			print("MUSHI_VOICE_DIAG capture=%s local=%.2f remote=%s" % [
				sender != null and sender.is_capturing(), get_local_level(), remote_levels])
	if listener_camera == null or not is_instance_valid(listener_camera):
		return
	for value in players.values():
		var player := value as AudioStreamPlayer3D
		if not is_instance_valid(player):
			continue
		var distance := player.global_position.distance_to(listener_camera.global_position)
		var falloff := clampf((far_radius - distance) / maxf(0.01, far_radius - near_radius), 0.0, 1.0)
		player.volume_linear = receive_gain * falloff


static func _mouth_weights(level: float) -> PackedFloat32Array:
	# OpenLipSync's 15-position order. Until the Prim ONNX recognizer is ported,
	# decoded speech energy drives a conservative AA mouth opening.
	var weights := PackedFloat32Array()
	weights.resize(15)
	weights[0] = 1.0 - level
	weights[10] = level * 0.65
	return weights


func _exit_tree() -> void:
	stop_session()
