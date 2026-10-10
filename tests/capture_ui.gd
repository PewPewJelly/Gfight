extends SceneTree
## Saves screenshots of every screen to .godot/test-output (needs a window, not --headless).

func _initialize() -> void:
	call_deferred("run")

func capture(file_name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	picture.save_png("res://.godot/test-output/%s.png" % file_name)

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://.godot/test-output")
	var main = load("res://main.tscn").instantiate()
	main.fade_seconds = 0.0
	main.result_delay = 0.0
	root.add_child(main)
	var session = root.get_node("Session")
	await capture("s1_menu")
	main._open_join()
	main.address_field.text = "192.168.0.5:27840"
	session.join_error = UiStyle.NOT_FOUND
	session.changed.emit()
	await capture("s1_1_join")
	main._cancel_join()
	session.roster = {1: "Host", 7: "Me", 9: "Third"}
	session.ready_states = {7: true, 9: false}
	session.room_address = "192.168.0.5:27840"
	session.phase = "lobby"
	session.changed.emit()
	await capture("s2_lobby_host")
	session.local_game()
	session.roster = {1: "P1", 2: "P2", 3: "P3", 4: "P4"}
	session.start_game()
	var arena: FightArena = session.arena
	arena.set_physics_process(false)
	arena.fighters[1].is_local = true
	arena.fighters[1].queue_redraw()
	await capture("s3_countdown")
	arena.countdown_left = 0.0
	arena._set_tag_emphasis(false)
	arena.fighters[0].percent = 42.0
	arena.fighters[1].percent = 118.0
	arena.fighters[1].stocks = 1
	arena.fighters[2].ring_out()
	arena.fighters[3].stocks = 1
	arena.fighters[3].ring_out()
	arena.fighters[0].position = Vector2(-60, 200)
	await capture("s3_hud")
	arena.fighters[0].kills = 1
	arena.fighters[0].dealt_percent = 186.0
	arena.fighters[1].kills = 4
	arena.fighters[1].dealt_percent = 412.0
	arena.fighters[2].kills = 2
	arena.fighters[2].dealt_percent = 240.0
	arena.fighters[0].stocks = 0
	arena.fighters[0].eliminated_frame = 10
	arena.fighters[2].stocks = 0
	arena.fighters[2].eliminated_frame = 20
	arena.fighters[3].eliminated_frame = 5
	arena._resolve_result()
	session.confirmed = {1: true, 3: true}
	session.changed.emit()
	await capture("s4_result")
	print("UI captures saved in .godot/test-output")
	quit()
