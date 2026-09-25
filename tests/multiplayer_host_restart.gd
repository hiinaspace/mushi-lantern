extends SceneTree

## Run with MUSHI_ROOM_SECRET and --host; a normal --join process can observe
## the reliable epoch reset without ending the private session.
func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.friend_menu.set_open(false)
	for _frame: int in 720:
		await process_frame
	if game._multiplayer_role != "host" or game._joined_peers.is_empty():
		printerr("MULTIPLAYER_RESTART_TEST no joined peer")
		game.queue_free()
		quit(1)
		return
	var previous_epoch: int = game._multiplayer_epoch
	game._on_friend_new_game()
	if game._multiplayer_epoch != previous_epoch + 1 or game._joined_peers.is_empty():
		printerr("MULTIPLAYER_RESTART_TEST host epoch/session failed")
		game.queue_free()
		quit(1)
		return
	for _frame: int in 180:
		await process_frame
	print("MULTIPLAYER_RESTART_TEST PASS epoch=%d peers=%d" % [game._multiplayer_epoch, game._joined_peers.size()])
	game.queue_free()
	await process_frame
	quit(0)
