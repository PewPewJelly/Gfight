class_name ScreenRouter
extends Control
## Root of main.tscn (Docs/00 §4.2): keeps exactly one screen as a child and swaps it when
## the screen emits exit_requested(result). Screens never open other screens themselves.

const SCREEN_SCENES: Dictionary = {
	ScreenTypes.ScreenId.MAIN_MENU: preload("res://scenes/ui/main_menu_screen.tscn"),
	ScreenTypes.ScreenId.START_GAME: preload("res://scenes/ui/start_game_screen.tscn"),
	ScreenTypes.ScreenId.LOBBY: preload("res://scenes/ui/lobby_screen.tscn"),
	ScreenTypes.ScreenId.MATCH: preload("res://scenes/ui/match_screen.tscn"),
}

var current_id: ScreenTypes.ScreenId = ScreenTypes.ScreenId.MAIN_MENU
var current: Control

func _ready() -> void:
	Session.changed.connect(_on_session_changed)
	go_to(ScreenTypes.ScreenId.MAIN_MENU)

## F11 / Alt+Enter switch fullscreen on every screen (Docs/00 §1), before screens see Enter.
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_F11 or (key.physical_keycode in [KEY_ENTER, KEY_KP_ENTER] and key.alt_pressed):
		_toggle_fullscreen()
		get_viewport().set_input_as_handled()

func go_to(screen_id: ScreenTypes.ScreenId, data: RefCounted = null) -> void:
	var scene: PackedScene = SCREEN_SCENES.get(screen_id)
	if scene == null:
		push_error("No scene for screen %s" % ScreenTypes.ScreenId.keys()[screen_id])
		return
	if is_instance_valid(current):
		remove_child(current)
		current.queue_free()
	current = scene.instantiate()
	current_id = screen_id
	add_child(current)
	current.exit_requested.connect(_on_exit_requested.bind(screen_id))
	current.enter(data)

func _on_exit_requested(result: RefCounted, from: ScreenTypes.ScreenId) -> void:
	if from != current_id:
		return
	if result is MainMenuExitResult:
		go_to(ScreenTypes.ScreenId.START_GAME)
	elif result is StartGameExitResult:
		var start_result := result as StartGameExitResult
		if start_result.route == StartGameExitResult.Route.LOBBY:
			go_to(ScreenTypes.ScreenId.LOBBY, _lobby_data(start_result.room_mode, start_result.role))
		else:
			go_to(ScreenTypes.ScreenId.MAIN_MENU)
	elif result is LobbyExitResult:
		var lobby_result := result as LobbyExitResult
		if lobby_result.route == LobbyExitResult.Route.MATCH:
			go_to(ScreenTypes.ScreenId.MATCH)
		else:
			go_to(ScreenTypes.ScreenId.START_GAME, _start_data(lobby_result.notice))
	elif result is MatchExitResult:
		var match_result := result as MatchExitResult
		if match_result.route == MatchExitResult.Route.LOBBY:
			go_to(ScreenTypes.ScreenId.LOBBY, _lobby_data(Session.room.mode, ScreenTypes.Role.HOST if Session.is_host() else ScreenTypes.Role.CLIENT))
		else:
			go_to(ScreenTypes.ScreenId.START_GAME, _start_data(match_result.notice))
	else:
		push_error("Unknown exit result from %s" % ScreenTypes.ScreenId.keys()[from])

## Forced moves from network events. The lobby handles its own exits (Docs/02 §4.10);
## the match screen has no spec yet, so the router returns it to 게임하기 here.
func _on_session_changed() -> void:
	if current_id == ScreenTypes.ScreenId.MATCH and Session.phase == Session.Phase.MENU:
		var notice := Session.toast
		Session.toast = ""
		go_to(ScreenTypes.ScreenId.START_GAME, _start_data(notice))

func _lobby_data(room_mode: ScreenTypes.RoomMode, role: ScreenTypes.Role) -> LobbyEnterData:
	var data := LobbyEnterData.new()
	data.room_mode = room_mode
	data.role = role
	return data

func _start_data(notice: String) -> StartGameEnterData:
	var data := StartGameEnterData.new()
	data.notice = notice
	return data

## Starts fullscreen (project setting); F11 or Alt+Enter switches to a window, e.g. to run
## two copies on one computer.
func _toggle_fullscreen() -> void:
	var fullscreen := DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)
