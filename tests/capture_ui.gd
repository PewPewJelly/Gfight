extends SceneTree
## Saves screenshots of every main screen (needs a window, not --headless).
## Default folder: res://.godot/test-output. Another folder: `-- out=/absolute/path`.
## Screen scripts use the Session autoload, so they are only touched through untyped variables.

var out_dir: String = "res://.godot/test-output"
var session: Node
var router: Control

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("out="):
			out_dir = argument.trim_prefix("out=")
	call_deferred("run")

func capture(file_name: String) -> void:
	for index in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	picture.save_png("%s/%s.png" % [out_dir, file_name])

func run() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	session = root.get_node("Session")
	session.local_name = "정우진"
	session.last_address = ""
	router = load("res://main.tscn").instantiate()
	root.add_child(router)
	await capture("01_main_menu")
	router.current.play_button.pressed.emit()
	await process_frame
	var start: Control = router.current
	start.fade.color.a = 0.0
	await capture("02_start_game")
	start._on_real_button_pressed()
	await capture("03_start_game_real")
	start._on_join_room_pressed()
	start.address_field.text = "1.2.3.4:abc"
	start._on_join_confirm_pressed()
	await capture("04_join_popup_error")
	start._on_join_cancel_pressed()
	# Online lobby as the host with two guests (stand-ins: the host's room is filled directly).
	session._open_room(ScreenTypes.RoomMode.ONLINE, "192.168.0.5:27840")
	session.room.name = "금요일 난투"
	var ready_guest: Variant = PlayerData.create(7, "민수", session.catalog.default_character())
	ready_guest.is_ready = true
	session.room.add_player(ready_guest)
	session.room.add_player(PlayerData.create(9, "지현", session.catalog.default_character()))
	router.go_to(ScreenTypes.ScreenId.LOBBY, router._lobby_data(ScreenTypes.RoomMode.ONLINE, ScreenTypes.Role.HOST))
	var lobby: Control = router.current
	session._chat(7, "준비 끝!")
	await capture("05_lobby_host_room")
	lobby._on_info_pressed()
	await capture("06_lobby_info_popover")
	lobby._on_info_pressed()
	lobby._on_tab_pressed(lobby.Tab.CHARACTER)
	await capture("07_lobby_character")
	lobby._on_tab_pressed(lobby.Tab.SETTINGS)
	await capture("08_lobby_settings_room")
	lobby._on_sub_tab_selected(1)
	await capture("09_lobby_settings_personal")
	lobby._on_tab_pressed(lobby.Tab.ROOM)
	lobby._on_player_menu_pressed(9)
	await capture("10_lobby_player_menu")
	lobby._on_player_action(lobby.PlayerAction.PROFILE, 7)
	lobby._on_escape()
	lobby._on_back_pressed()
	await capture("11_lobby_exit_modal")
	lobby._on_modal_cancelled()
	session.leave()
	await process_frame
	# Training: lobby, match with the dummy, result.
	session.start_training()
	router.go_to(ScreenTypes.ScreenId.LOBBY, router._lobby_data(ScreenTypes.RoomMode.TRAINING, ScreenTypes.Role.HOST))
	await capture("12_lobby_training")
	router.current._on_ready_button_pressed()
	await process_frame
	var match_screen: Control = router.current
	match_screen.fade_seconds = 0.0
	match_screen.fade.color.a = 0.0
	match_screen.result_delay = 0.0
	var arena: FightArena = session.arena
	arena.set_physics_process(false)
	for fighter in arena.fighters:
		fighter.set_physics_process(false)
	await capture("13_training_countdown")
	arena.countdown_left = 0.0
	arena._set_tag_emphasis(false)
	var player: Fighter = arena.fighters[0]
	var dummy: Fighter = arena.fighters[1]
	player.reset_round(Vector2(560, 334))
	dummy.reset_round(Vector2(615, 334))
	player.facing = 1.0
	player.simulate(1.0 / 60.0, 16)
	arena._resolve_attacks()
	dummy.percent = 48.0
	await capture("14_training_hit_dummy")
	dummy.stocks = 1
	dummy.ring_out()
	dummy.eliminated_frame = arena.frame
	player.kills = 3
	arena._resolve_result()
	await capture("15_training_result")
	print("UI captures saved in %s" % out_dir)
	session.leave()
	quit()
