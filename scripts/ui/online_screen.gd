class_name OnlineScreen
extends Control
## Public-room browser backed by OnlineClient. This screen only owns discovery,
## room creation and joining; battle traffic remains on WebRTC data channels.

signal exit_requested(result: OnlineExitResult)

enum ScreenState { IDLE, CREATING, JOINING, LEAVING }

const REFRESH_SECONDS: float = 3.0
const TOAST_SECONDS: float = 3.0
const MAX_PLAYERS: int = 4

var state: ScreenState = ScreenState.IDLE
var _toast_left: float = 0.0

@onready var back_button: Button = %BackButton
@onready var refresh_button: Button = %RefreshButton
@onready var room_name_field: LineEdit = %RoomNameField
@onready var create_room_button: Button = %CreateRoomButton
@onready var room_list: VBoxContainer = %RoomList
@onready var refresh_timer: Timer = %RefreshTimer
@onready var toast: PanelContainer = %Toast
@onready var toast_label: Label = %ToastLabel

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	refresh_button.pressed.connect(_refresh_rooms)
	create_room_button.pressed.connect(_on_create_room_pressed)
	room_name_field.text_submitted.connect(func(_text: String) -> void: _on_create_room_pressed())
	refresh_timer.timeout.connect(_refresh_rooms)
	OnlineClient.rooms_updated.connect(_show_rooms)
	OnlineClient.connection_changed.connect(_on_connection_changed)
	OnlineClient.room_state_updated.connect(_on_room_state_updated)
	OnlineClient.request_failed.connect(_on_request_failed)
	toast.add_theme_stylebox_override("panel", _panel_style(Color("fff4a8e8"), Color("ff1493"), 3, 16))
	set_process(false)

## data: OnlineEnterData or null.
func enter(data: RefCounted) -> void:
	state = ScreenState.IDLE
	_apply_state()
	var online_data := data as OnlineEnterData
	if online_data != null and not online_data.notice.is_empty():
		_show_toast(online_data.notice)
	_refresh_rooms()
	refresh_timer.start(REFRESH_SECONDS)
	room_name_field.grab_focus()

func _exit_tree() -> void:
	refresh_timer.stop()

func _process(delta: float) -> void:
	_toast_left = maxf(0.0, _toast_left - delta)
	if is_zero_approx(_toast_left):
		toast.visible = false
		set_process(false)

func _apply_state() -> void:
	var busy := state != ScreenState.IDLE
	back_button.disabled = busy
	refresh_button.disabled = busy
	room_name_field.editable = not busy
	create_room_button.disabled = busy
	create_room_button.text = "만드는 중..." if state == ScreenState.CREATING else "방 만들기"

func _refresh_rooms() -> void:
	if state != ScreenState.IDLE:
		return
	refresh_button.text = "불러오는 중..."
	OnlineClient.list_rooms()

func _show_rooms(rooms: Array) -> void:
	refresh_button.text = "새로고침"
	for child: Node in room_list.get_children():
		room_list.remove_child(child)
		child.queue_free()
	for value: Variant in rooms:
		if value is Dictionary:
			var room: Dictionary = value
			room_list.add_child(_make_room_card(room))

func _make_room_card(room: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 142)
	card.add_theme_stylebox_override("panel", _panel_style(Color("fffbd5e8"), Color("ff2c9c"), 4, 18))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_bottom", 14)
	card.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	margin.add_child(row)

	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 7)
	row.add_child(details)
	details.add_child(_center_label(str(room.get("name", "이름 없는 방")), 25, Color("17234a")))
	details.add_child(_center_label("테스트 맵  ·  Stock 3  ·  아이템 없음", 17, Color("5b246b")))

	var player_count := clampi(int(room.get("player_count", 0)), 0, MAX_PLAYERS)
	var host_name := str(room.get("host_name", "알 수 없음"))
	var participant_text := "참가자  %s" % host_name
	if player_count > 1:
		participant_text += "  ·  외 %d명" % (player_count - 1)
	details.add_child(_center_label(participant_text, 17, Color("17234a")))

	var population := VBoxContainer.new()
	population.custom_minimum_size.x = 150
	population.add_theme_constant_override("separation", 8)
	row.add_child(population)
	population.add_child(_center_label("%d / %d" % [player_count, MAX_PLAYERS], 22, Color("17234a")))
	var lights := HBoxContainer.new()
	lights.alignment = BoxContainer.ALIGNMENT_CENTER
	lights.add_theme_constant_override("separation", 7)
	population.add_child(lights)
	for index: int in range(MAX_PLAYERS):
		var light := Label.new()
		light.text = "●"
		light.add_theme_font_size_override("font_size", 22)
		light.add_theme_color_override("font_color", Color("28e56f") if index < player_count else Color("b7aebd"))
		lights.add_child(light)

	var join_button := Button.new()
	join_button.custom_minimum_size = Vector2(130, 54)
	join_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	join_button.add_theme_font_size_override("font_size", 19)
	var status := str(room.get("status", "lobby"))
	join_button.disabled = player_count >= MAX_PLAYERS or status != "lobby"
	join_button.text = "참여 불가" if join_button.disabled else "참여"
	join_button.pressed.connect(_join_room.bind(str(room.get("room_id", ""))))
	row.add_child(join_button)
	return card

func _center_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _panel_style(fill: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(radius)
	return box

func _on_create_room_pressed() -> void:
	if state != ScreenState.IDLE:
		return
	var room_name := room_name_field.text.strip_edges()
	if room_name.is_empty():
		_show_toast("방 이름을 입력해 주세요.")
		room_name_field.grab_focus()
		return
	state = ScreenState.CREATING
	_apply_state()
	OnlineClient.create_room(room_name, Session.local_name)
	_show_toast("공개 방을 만드는 중...")

func _join_room(room_id: String) -> void:
	if state != ScreenState.IDLE or room_id.is_empty():
		return
	state = ScreenState.JOINING
	_apply_state()
	OnlineClient.join_room(room_id, Session.local_name)
	_show_toast("방에 연결하는 중...")

func _on_connection_changed(connected: bool) -> void:
	if connected:
		_show_toast("방에 연결되었습니다. F3에서 연결 상태를 볼 수 있습니다.")
	else:
		state = ScreenState.IDLE
		_apply_state()

func _on_room_state_updated(_room_state: Dictionary) -> void:
	state = ScreenState.IDLE
	_apply_state()
	_show_toast("대기방 연결 완료")

func _on_request_failed(message: String) -> void:
	state = ScreenState.IDLE
	_apply_state()
	refresh_button.text = "새로고침"
	_show_toast(message)

func _on_back_pressed() -> void:
	if state != ScreenState.IDLE:
		return
	state = ScreenState.LEAVING
	_apply_state()
	OnlineClient.disconnect_room()
	var result := OnlineExitResult.new()
	result.route = OnlineExitResult.Route.MAIN_MENU
	exit_requested.emit(result)

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_on_back_pressed()

func _show_toast(text: String) -> void:
	toast_label.text = text
	toast.visible = true
	_toast_left = TOAST_SECONDS
	set_process(true)
