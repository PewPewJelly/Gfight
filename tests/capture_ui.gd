extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func capture(file_name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	picture.save_png("res://.godot/test-output/%s.png" % file_name)

func run() -> void:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await capture("menu")
	var session = root.get_node("Session")
	session.local_game()
	await capture("lobby")
	session.start_game()
	await capture("game")
	session.arena.fighters[1].stocks = 0
	session.arena._resolve_result()
	await capture("result")
	print("UI captures saved in .godot/test-output")
	quit()
