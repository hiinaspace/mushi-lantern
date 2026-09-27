extends SceneTree

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var local := Lantern.new()
	var peer := Lantern.new()
	root.add_child(local)
	root.add_child(peer)
	local.set_mode(LightField.Mode.BLUE)
	local.set_shutter(0.75)
	peer.set_mode(LightField.Mode.ORANGE)
	peer.set_shutter(0.25)
	_expect(local.mode == LightField.Mode.BLUE and is_equal_approx(local.shutter_openness, 0.75), "local state is independent of peer state")
	_expect(peer.mode == LightField.Mode.ORANGE and is_equal_approx(peer.shutter_openness, 0.25), "peer state is independent of local state")
	_expect(local.spot.light_color != peer.spot.light_color, "spot colors remain distinct")
	_expect(local.spot.light_projector != peer.spot.light_projector, "each shutter owns its projector")
	peer.set_beam_shadows_enabled(false)
	_expect(peer.spot.light_projector == null, "shadowless beam cannot use stale projector matrix")
	peer.set_beam_shadows_enabled(true)
	_expect(peer.spot.light_projector != null, "projector returns with shadow matrix")
	var direction := Vector3(0.3, -0.4, -0.8).normalized()
	peer.global_basis = Basis.looking_at(direction, Vector3.UP)
	_expect(peer.forward_direction().dot(direction) > 0.999, "network aim follows received forward direction")
	var field := LightField.new()
	field.update_transform(peer.global_position, peer.forward_direction())
	field.mode = peer.mode
	field.shutter_openness = peer.shutter_openness
	var packet := MultiplayerLantern.encode(7, field)
	var appended := packet.duplicate()
	appended.append_array(PackedByteArray([11, 22, 33]))
	var sample := MultiplayerLantern.decode(appended, 128)
	_expect(int(sample.get("sequence", -1)) == 7 and int(sample.get("mode", -1)) == LightField.Mode.ORANGE, "lantern prefix survives appended avatar data")
	_expect(absf(float(sample.get("shutter", -1.0)) - 0.25) < 1.0 / 255.0, "shutter survives packet round trip")
	peer.set_mode(LightField.Mode.CLEAR)
	peer.set_shutter(0.0)
	_expect(local.mode == LightField.Mode.BLUE and is_equal_approx(local.shutter_openness, 0.75), "remote updates never mutate local mode or shutter")
	local.free()
	peer.free()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game._multiplayer_role = "host"
	game.lantern.set_mode(LightField.Mode.BLUE)
	game.lantern.set_shutter(0.75)
	var incoming := LightField.new()
	incoming.update_transform(Vector3(5.0, 2.0, 4.0), direction)
	incoming.mode = LightField.Mode.ORANGE
	incoming.shutter_openness = 0.25
	game._on_network_lantern("peer-a", MultiplayerLantern.encode(1, incoming))
	var visual: Lantern = game._peer_lanterns["peer-a"]
	game._limit_remote_lights()
	_expect(visual.spot.visible and not visual.spot.shadow_enabled and visual.spot.light_projector == null,
		"open local lantern reserves the shadow slot while peer beam stays visible")
	_expect(visual.spot.light_color == Color("ed5d49"), "shadowless peer beam retains its filter color")
	game.lantern.set_shutter(0.0)
	game._limit_remote_lights()
	_expect(visual.spot.shadow_enabled and visual.spot.light_projector != null,
		"peer cookie regains its shadow matrix when local shutter closes")
	game.lantern.set_shutter(0.75)
	game._limit_remote_lights()
	_expect(game.lantern.mode == LightField.Mode.BLUE and is_equal_approx(game.lantern.shutter_openness, 0.75), "received peer packet leaves local lamp untouched")
	_expect(visual.mode == LightField.Mode.ORANGE and absf(visual.shutter_openness - 0.25) < 1.0 / 255.0, "received peer packet updates only peer lamp")
	_expect(visual.forward_direction().dot(direction) > 0.999 and visual.global_position.is_equal_approx(incoming.source_position), "received peer packet preserves beam direction and origin")
	game.queue_free()
	await process_frame
	print("MULTIPLAYER_LANTERN_STATE_CHECKS %s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
