class_name StartGameScreen
extends Control
## SYS-01 게임하기 (Docs/01): 실전 (방 참여 / 방 생성) and 훈련장.
## Logic handlers change state; _apply_state() is the only place that changes what is shown.

signal exit_requested(result: StartGameExitResult)

enum ScreenState {
	IDLE,            # 실전 sub buttons hidden
	REAL_EXPANDED,   # mouse over 실전: [방 참여][방 생성] shown
	CREATING,        # [방 생성] waiting for Session.host_game
	JOIN_EDITING,    # address popup open
	JOIN_INVALID,    # format error shown (no network request)
	JOIN_CONNECTING, # connecting (up to Session.JOIN_TIMEOUT_MSEC)
	JOIN_FAILED,     # network failure shown
	LEAVING,         # switching screens; all input ignored
}
enum JoinError { NONE, BAD_FORMAT, NOT_FOUND, ROOM_FULL, IN_PROGRESS, VERSION_MISMATCH }

const HOVER_CLOSE_DELAY: float = 0.15
const TOAST_SECONDS: float = 3.0
const SUBMENU_FADE_SECONDS: float = 0.12
const FADE_SECONDS: float = 0.2
const JOIN_ERROR_TEXT: Dictionary = {
	JoinError.NONE: "",
	JoinError.BAD_FORMAT: UiStyle.BAD_ADDRESS,
	JoinError.NOT_FOUND: UiStyle.NOT_FOUND,
	JoinError.ROOM_FULL: UiStyle.ROOM_FULL,
	JoinError.IN_PROGRESS: UiStyle.IN_PROGRESS,
	JoinError.VERSION_MISMATCH: UiStyle.VERSION_MISMATCH,
}

var state: ScreenState = ScreenState.IDLE
var join_error: JoinError = JoinError.NONE
## Generation number that cancels a pending hover-close.
var _collapse_ticket: int = 0
var _toast_left: float = 0.0

@onready var back_button: Button = %BackButton
@onready var location_label: Label = %LocationLabel
@onready var real_area: Control = %RealArea
@onready var real_button: Button = %RealButton
@onready var real_icon: TextureRect = %RealIcon
@onready var real_label: Label = %RealLabel
@onready var real_sub_menu: VBoxContainer = %RealSubMenu
@onready var join_room_button: Button = %JoinRoomButton
@onready var create_room_button: Button = %CreateRoomButton
@onready var training_button: Button = %TrainingButton
@onready var training_icon: TextureRect = %TrainingIcon
@onready var training_label: Label = %TrainingLabel
@onready var toast: PanelContainer = %Toast
@onready var toast_label: Label = %ToastLabel
@onready var join_popup: Control = %JoinPopup
@onready var join_panel: PanelContainer = %JoinPanel
@onready var join_title: Label = %JoinTitle
@onready var address_field: LineEdit = %AddressField
@onready var join_error_label: Label = %JoinErrorLabel
@onready var join_cancel_button: Button = %JoinCancelButton
@onready var join_confirm_button: Button = %JoinConfirmButton
@onready var fade: ColorRect = %Fade

func _ready() -> void:
	location_label.text = UiStyle.PLAY_TITLE
	real_label.text = UiStyle.MODE_REAL
	training_label.text = UiStyle.MODE_TRAINING
	join_room_button.text = UiStyle.JOIN_ROOM
	join_title.text = UiStyle.JOIN_ADDRESS_TITLE
	join_cancel_button.text = UiStyle.CANCEL
	join_panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, UiStyle.TEXT_DIM, 1, 14))
	toast.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL_MUTED, UiStyle.TEXT_DIM, 1, 20))
	back_button.pressed.connect(_on_back_pressed)
	real_area.mouse_entered.connect(_on_real_area_mouse_entered)
	real_area.mouse_exited.connect(_on_real_area_mouse_exited)
	real_button.pressed.connect(_on_real_button_pressed)
	join_room_button.pressed.connect(_on_join_room_pressed)
	create_room_button.pressed.connect(_on_create_room_pressed)
	training_button.pressed.connect(_on_training_pressed)
	address_field.text_changed.connect(_on_address_text_changed)
	address_field.text_submitted.connect(_on_address_submitted)
	join_confirm_button.pressed.connect(_on_join_confirm_pressed)
	join_cancel_button.pressed.connect(_on_join_cancel_pressed)
	set_process(false)

func _process(delta: float) -> void:
	_toast_left = maxf(0.0, _toast_left - delta)
	if is_zero_approx(_toast_left):
		toast.visible = false
		set_process(false)

func enter(data: StartGameEnterData) -> void:
	state = ScreenState.IDLE
	join_error = JoinError.NONE
	_apply_state(state)
	if not Session.changed.is_connected(_on_session_changed):
		Session.changed.connect(_on_session_changed)
	if data != null and not data.notice.is_empty():
		_show_toast(data.notice)
	fade.color.a = 1.0
	create_tween().tween_property(fade, "color:a", 0.0, FADE_SECONDS)

func _set_state(next: ScreenState) -> void:
	if state == ScreenState.LEAVING:
		return
	var was_expanded := real_sub_menu.visible
	state = next
	_apply_state(next)
	if real_sub_menu.visible and not was_expanded:
		real_sub_menu.modulate.a = 0.0
		create_tween().tween_property(real_sub_menu, "modulate:a", 1.0, SUBMENU_FADE_SECONDS)

## Docs/01 §3.3. Display only.
func _apply_state(s: ScreenState) -> void:
	var popup_open := s in [ScreenState.JOIN_EDITING, ScreenState.JOIN_INVALID, ScreenState.JOIN_CONNECTING, ScreenState.JOIN_FAILED]
	var all_disabled := s in [ScreenState.CREATING, ScreenState.LEAVING]
	if s != ScreenState.LEAVING:
		real_sub_menu.visible = s in [ScreenState.REAL_EXPANDED, ScreenState.CREATING]
		join_popup.visible = popup_open
	real_icon.self_modulate = UiStyle.ACCENT if s in [ScreenState.REAL_EXPANDED, ScreenState.CREATING] else UiStyle.TEXT
	training_icon.self_modulate = UiStyle.TEXT
	for button: Button in [back_button, real_button, join_room_button, create_room_button, training_button]:
		button.disabled = all_disabled
	create_room_button.text = UiStyle.CREATING if s == ScreenState.CREATING else UiStyle.CREATE_ROOM
	var connecting := s == ScreenState.JOIN_CONNECTING
	join_confirm_button.disabled = connecting or s == ScreenState.LEAVING
	join_cancel_button.disabled = s == ScreenState.LEAVING
	join_confirm_button.text = UiStyle.CONNECTING if connecting else UiStyle.CONFIRM
	address_field.editable = not connecting and s != ScreenState.LEAVING
	var failed := s in [ScreenState.JOIN_INVALID, ScreenState.JOIN_FAILED]
	address_field.add_theme_color_override("font_color", UiStyle.ERROR if failed else UiStyle.TEXT)
	join_error_label.text = JOIN_ERROR_TEXT[join_error] if failed else ""

func _exit_to(route: StartGameExitResult.Route, room_mode: ScreenTypes.RoomMode = ScreenTypes.RoomMode.NONE, role: ScreenTypes.Role = ScreenTypes.Role.NONE) -> void:
	_set_state(ScreenState.LEAVING)
	var result := StartGameExitResult.new()
	result.route = route
	result.room_mode = room_mode
	result.role = role
	result.room_address = Session.room.address if room_mode == ScreenTypes.RoomMode.ONLINE else ""
	exit_requested.emit(result)

# Back --------------------------------------------------------------------------

func _on_back_pressed() -> void:
	if state not in [ScreenState.IDLE, ScreenState.REAL_EXPANDED]:
		return
	_exit_to(StartGameExitResult.Route.MAIN_MENU)

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.physical_keycode != KEY_ESCAPE:
		return
	# Handled first: going back removes this screen from the tree.
	get_viewport().set_input_as_handled()
	if state in [ScreenState.JOIN_EDITING, ScreenState.JOIN_INVALID, ScreenState.JOIN_CONNECTING, ScreenState.JOIN_FAILED]:
		_on_join_cancel_pressed()
	elif state in [ScreenState.IDLE, ScreenState.REAL_EXPANDED]:
		_on_back_pressed()

# 실전 hover ---------------------------------------------------------------------

func _on_real_area_mouse_entered() -> void:
	_collapse_ticket += 1
	if state == ScreenState.IDLE:
		_set_state(ScreenState.REAL_EXPANDED)

func _on_real_area_mouse_exited() -> void:
	if state != ScreenState.REAL_EXPANDED:
		return
	_collapse_ticket += 1
	var ticket := _collapse_ticket
	await get_tree().create_timer(HOVER_CLOSE_DELAY).timeout
	if is_inside_tree():
		_try_collapse(ticket)

func _try_collapse(ticket: int) -> void:
	if ticket != _collapse_ticket:
		return
	if real_area.get_global_rect().has_point(get_global_mouse_position()):
		return
	if state == ScreenState.REAL_EXPANDED:
		_set_state(ScreenState.IDLE)

## Clicking expands even when no mouse_entered arrived (cursor came from outside the window).
func _on_real_button_pressed() -> void:
	if state == ScreenState.IDLE:
		_set_state(ScreenState.REAL_EXPANDED)

# 방 생성 ------------------------------------------------------------------------

func _on_create_room_pressed() -> void:
	if state != ScreenState.REAL_EXPANDED:
		return
	_set_state(ScreenState.CREATING)
	# Let the "방을 만드는 중…" label draw for one frame.
	await get_tree().process_frame
	if not is_inside_tree() or state != ScreenState.CREATING:
		return
	var err: Error = Session.host_game(Session.local_name)
	if err == OK:
		_exit_to(StartGameExitResult.Route.LOBBY, ScreenTypes.RoomMode.ONLINE, ScreenTypes.Role.HOST)
	else:
		_show_toast(Session.toast)
		Session.toast = ""
		_set_state(ScreenState.IDLE)

# 훈련장 -------------------------------------------------------------------------

func _on_training_pressed() -> void:
	if state not in [ScreenState.IDLE, ScreenState.REAL_EXPANDED]:
		return
	Session.start_training()
	_exit_to(StartGameExitResult.Route.LOBBY, ScreenTypes.RoomMode.TRAINING, ScreenTypes.Role.HOST)

# 방 참여 popup ------------------------------------------------------------------

func _on_join_room_pressed() -> void:
	if state != ScreenState.REAL_EXPANDED:
		return
	Session.join_error = ""
	join_error = JoinError.NONE
	address_field.text = _initial_address()
	_set_state(ScreenState.JOIN_EDITING)
	address_field.grab_focus()
	address_field.select_all()

func _initial_address() -> String:
	if not Session.last_address.is_empty():
		return Session.last_address
	return "%s:%d" % [Session.local_ipv4(), Session.DEFAULT_PORT]

func _on_address_text_changed(_new_text: String) -> void:
	if state in [ScreenState.JOIN_INVALID, ScreenState.JOIN_FAILED]:
		join_error = JoinError.NONE
		_set_state(ScreenState.JOIN_EDITING)

func _on_address_submitted(_text: String) -> void:
	_on_join_confirm_pressed()

func _on_join_confirm_pressed() -> void:
	if state not in [ScreenState.JOIN_EDITING, ScreenState.JOIN_INVALID, ScreenState.JOIN_FAILED]:
		return
	if address_field.text.strip_edges().is_empty():
		join_error = JoinError.BAD_FORMAT
		_set_state(ScreenState.JOIN_INVALID)
		return
	var parsed := Session.parse_address(address_field.text)
	if not parsed.ok:
		join_error = JoinError.BAD_FORMAT
		_set_state(ScreenState.JOIN_INVALID)
		return
	_set_state(ScreenState.JOIN_CONNECTING)
	# A failed start reports through Session.changed -> join_error (handled below).
	Session.join_game(parsed.host, parsed.port, Session.local_name)

func _on_join_cancel_pressed() -> void:
	if state not in [ScreenState.JOIN_EDITING, ScreenState.JOIN_INVALID, ScreenState.JOIN_CONNECTING, ScreenState.JOIN_FAILED]:
		return
	Session.cancel_join()
	join_error = JoinError.NONE
	_set_state(ScreenState.REAL_EXPANDED)
	if not real_area.get_global_rect().has_point(get_global_mouse_position()):
		_on_real_area_mouse_exited()

# Session ----------------------------------------------------------------------

func _on_session_changed() -> void:
	if state == ScreenState.LEAVING:
		return
	if state == ScreenState.JOIN_CONNECTING and Session.phase == Session.Phase.LOBBY:
		_exit_to(StartGameExitResult.Route.LOBBY, ScreenTypes.RoomMode.ONLINE, ScreenTypes.Role.CLIENT)
		return
	if state == ScreenState.JOIN_CONNECTING and not Session.join_error.is_empty():
		join_error = _map_join_error(Session.join_error)
		_set_state(ScreenState.JOIN_FAILED)
	if not Session.toast.is_empty() and state != ScreenState.CREATING:
		_show_toast(Session.toast)
		Session.toast = ""

func _map_join_error(text: String) -> JoinError:
	for error: int in JOIN_ERROR_TEXT:
		if error != JoinError.NONE and JOIN_ERROR_TEXT[error] == text:
			return error as JoinError
	return JoinError.NOT_FOUND

func _show_toast(text: String) -> void:
	if text.is_empty():
		return
	toast_label.text = text
	toast.visible = true
	_toast_left = TOAST_SECONDS
	set_process(true)
