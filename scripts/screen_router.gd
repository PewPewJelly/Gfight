class_name ScreenRouter
extends Control
## Root of main.tscn (Docs/00 §4.2): keeps exactly one screen as a child and swaps it when
## the screen emits exit_requested(result). Screens never open other screens themselves.

const SCREEN_SCENES: Dictionary = {
	ScreenTypes.ScreenId.MAIN_MENU: preload("res://scenes/ui/main_menu_screen.tscn"),
	ScreenTypes.ScreenId.ONLINE: preload("res://scenes/ui/online_screen.tscn"),
	ScreenTypes.ScreenId.LOBBY: preload("res://scenes/ui/lobby_screen.tscn"),
	ScreenTypes.ScreenId.MATCH: preload("res://scenes/ui/match_screen.tscn"),
}

var current_id: ScreenTypes.ScreenId = ScreenTypes.ScreenId.MAIN_MENU
var current: Control
## Mode of the last lobby opened, so leaving a room returns to where the player came from:
## training → main menu (PLAY submenu open), online → the online screen.
var _room_mode: ScreenTypes.RoomMode = ScreenTypes.RoomMode.NONE

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
	var lobby_data := data as LobbyEnterData
	if lobby_data != null:
		_room_mode = lobby_data.room_mode
	current = scene.instantiate()
	current_id = screen_id
	add_child(current)
	current.exit_requested.connect(_on_exit_requested.bind(screen_id))
	current.enter(data)

func _on_exit_requested(result: RefCounted, from: ScreenTypes.ScreenId) -> void:
	if from != current_id:
		return
	if result is MainMenuExitResult:
		var menu_result := result as MainMenuExitResult
		if menu_result.route == MainMenuExitResult.Route.TRAINING:
			go_to(ScreenTypes.ScreenId.LOBBY, _lobby_data(ScreenTypes.RoomMode.TRAINING, ScreenTypes.Role.HOST))
		else:
			go_to(ScreenTypes.ScreenId.ONLINE)
	elif result is OnlineExitResult:
		var online_result := result as OnlineExitResult
		if online_result.route == OnlineExitResult.Route.LOBBY:
			go_to(ScreenTypes.ScreenId.LOBBY, _lobby_data(online_result.room_mode, online_result.role))
		else:
			go_to(ScreenTypes.ScreenId.MAIN_MENU, _menu_data(MainMenuScreen.PlayItem.ONLINE))
	elif result is LobbyExitResult:
		var lobby_result := result as LobbyExitResult
		if lobby_result.route == LobbyExitResult.Route.MATCH:
			go_to(ScreenTypes.ScreenId.MATCH)
		else:
			_leave_room(lobby_result.notice)
	elif result is MatchExitResult:
		var match_result := result as MatchExitResult
		if match_result.route == MatchExitResult.Route.LOBBY:
			go_to(ScreenTypes.ScreenId.LOBBY, _lobby_data(Session.room.mode, ScreenTypes.Role.HOST if Session.is_host() else ScreenTypes.Role.CLIENT))
		else:
			_leave_room(match_result.notice)
	else:
		push_error("Unknown exit result from %s" % ScreenTypes.ScreenId.keys()[from])

## Forced moves from network events. The lobby handles its own exits (Docs/02 §4.10);
## the match screen has no spec yet, so the router takes it out of the room here.
func _on_session_changed() -> void:
	if current_id == ScreenTypes.ScreenId.MATCH and Session.phase == Session.Phase.MENU:
		var notice := Session.toast
		Session.toast = ""
		_leave_room(notice)

## After a room ends: training goes back to the PLAY submenu, online to the online screen
## (which shows the notice as a toast).
func _leave_room(notice: String) -> void:
	if _room_mode == ScreenTypes.RoomMode.TRAINING:
		go_to(ScreenTypes.ScreenId.MAIN_MENU, _menu_data(MainMenuScreen.PlayItem.TRAINING))
	else:
		go_to(ScreenTypes.ScreenId.ONLINE, _online_data(notice))

func _lobby_data(room_mode: ScreenTypes.RoomMode, role: ScreenTypes.Role) -> LobbyEnterData:
	var data := LobbyEnterData.new()
	data.room_mode = room_mode
	data.role = role
	return data

func _online_data(notice: String) -> OnlineEnterData:
	var data := OnlineEnterData.new()
	data.notice = notice
	return data

func _menu_data(play_item: MainMenuScreen.PlayItem) -> MainMenuEnterData:
	var data := MainMenuEnterData.new()
	data.open_play_menu = true
	data.play_item = play_item
	return data

## Starts fullscreen (project setting); F11 or Alt+Enter switches to a window, e.g. to run
## two copies on one computer.
func _toggle_fullscreen() -> void:
	var fullscreen := DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)
