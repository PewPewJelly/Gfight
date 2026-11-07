class_name PublicRoomBrowser
extends PanelContainer

signal room_selected(room_id: String)
signal create_requested(room_name: String)
signal closed

var _room_list: VBoxContainer
var _name_field: LineEdit
var _status: Label
var _refresh_timer: Timer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	position = Vector2(-300, -240)
	custom_minimum_size = Vector2(600, 480)
	_build()
	OnlineClient.rooms_updated.connect(_show_rooms)
	_refresh_timer.timeout.connect(OnlineClient.list_rooms)

func open() -> void:
	visible = true
	OnlineClient.list_rooms()
	_refresh_timer.start()

func close() -> void:
	visible = false
	_refresh_timer.stop()
	closed.emit()

func _build() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	var title := Label.new()
	title.text = "공개 방"
	title.add_theme_font_size_override("font_size", 30)
	column.add_child(title)

	_status = Label.new()
	_status.text = "방 목록을 불러오는 중…"
	column.add_child(_status)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	_room_list = VBoxContainer.new()
	_room_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_room_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_room_list)

	var create_row := HBoxContainer.new()
	column.add_child(create_row)
	_name_field = LineEdit.new()
	_name_field.placeholder_text = "방 이름"
	_name_field.max_length = 40
	_name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_row.add_child(_name_field)
	var create_button := Button.new()
	create_button.text = "방 만들기"
	create_button.pressed.connect(func() -> void:
		var room_name := _name_field.text.strip_edges()
		if room_name.is_empty():
			room_name = "%s의 방" % Session.local_name
		create_requested.emit(room_name)
	)
	create_row.add_child(create_button)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(buttons)
	var refresh := Button.new()
	refresh.text = "새로고침"
	refresh.pressed.connect(OnlineClient.list_rooms)
	buttons.add_child(refresh)
	var close_button := Button.new()
	close_button.text = "닫기"
	close_button.pressed.connect(close)
	buttons.add_child(close_button)

	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = 3.0
	_refresh_timer.one_shot = false
	add_child(_refresh_timer)

func _show_rooms(rooms: Array) -> void:
	for child in _room_list.get_children():
		child.queue_free()
	_status.text = "공개 방 %d개 · 3초마다 자동 갱신" % rooms.size()
	if rooms.is_empty():
		var empty := Label.new()
		empty.text = "현재 공개 방이 없습니다."
		_room_list.add_child(empty)
		return
	for value: Variant in rooms:
		if not value is Dictionary:
			continue
		var room: Dictionary = value
		var button := Button.new()
		button.custom_minimum_size.y = 48
		button.text = "%s    %d/%d    %s" % [
			room.get("name", "이름 없는 방"),
			int(room.get("player_count", 0)),
			int(room.get("max_players", 4)),
			_status_text(str(room.get("status", "lobby")))
		]
		button.disabled = int(room.get("player_count", 0)) >= int(room.get("max_players", 4)) or str(room.get("status", "")) != "lobby"
		button.pressed.connect(func() -> void: room_selected.emit(str(room.get("room_id", ""))))
		_room_list.add_child(button)

func _status_text(value: String) -> String:
	match value:
		"lobby": return "대기 중"
		"connecting": return "연결 중"
		"in_game": return "게임 중"
	return value
