class_name SettingsPanel
extends Control
## [설정] tab (Docs/02 §3.9): sub tabs [방][개인], room rows (name, map, max players) and
## personal rows (BGM, SFX, nickname). Display and input only; LobbyScreen applies changes.

signal sub_tab_selected(view: int)
signal room_name_committed(text: String)
signal map_button_pressed
signal max_players_pressed(value: int)
signal nickname_committed(text: String)
signal pref_changed(key: StringName, value: int)

## Match LobbyScreen.SettingsView.
const VIEW_ROOM: int = 0
const VIEW_PERSONAL: int = 1
const BAR_HEIGHT: float = 84.0
const ROW_GAP: float = 14.0
const ONLINE_ROW_HEIGHT: float = 160.0
const INPUT_SIZE := Vector2(380, 68)
const MAP_BUTTON_SIZE := Vector2(400, 262)
const SLIDER_WIDTH: float = 360.0

var _built_key: Array = []
var _room_name_input: SlantInput
var _nickname_input: SlantInput
var _map_button: SelectTile
var _player_chips: Dictionary = {}
var _sliders: Dictionary = {}
var _slider_values: Dictionary = {}

@onready var content: Control = %Content

## Rebuilds only when the layout changes, so typing is never interrupted by a refresh.
func refresh(view: int, room: RoomState, editable: bool, training: bool, my_name: String, prefs: Dictionary) -> void:
	var key := [view, editable, training]
	if key != _built_key:
		_built_key = key
		_build(view, editable, training)
	if view == VIEW_ROOM:
		if _room_name_input != null:
			_room_name_input.set_text(room.name)
		_map_button.configure(SelectTile.Kind.MAP, room.map, Session.catalog.map_name(room.map), _map_english(room.map))
		for count: int in _player_chips:
			var chip: Button = _player_chips[count]
			chip.disabled = not editable or count < room.players.size()
			_style_chip(chip, count == room.max_players)
	else:
		_nickname_input.set_text(my_name)
		for pref_key: StringName in _sliders:
			var slider: HSlider = _sliders[pref_key]
			slider.set_value_no_signal(int(prefs.get(pref_key, 0)))
			(_slider_values[pref_key] as Label).text = str(int(slider.value))

func _build(view: int, editable: bool, training: bool) -> void:
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	_room_name_input = null
	_nickname_input = null
	_map_button = null
	_player_chips.clear()
	_sliders.clear()
	_slider_values.clear()
	var bar_top := LobbyGeometry.PANEL_PAD_Y
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	bar.position = Vector2(LobbyGeometry.PANEL_BORDER + LobbyGeometry.PANEL_PAD + LobbyGeometry.TAN * (bar_top + 8.0), bar_top + 8.0)
	bar.size = Vector2(LobbyGeometry.PANEL_INNER_W, 68)
	content.add_child(bar)
	bar.add_child(_sub_tab(UiStyle.SUB_TAB_ROOM, VIEW_ROOM, view == VIEW_ROOM))
	bar.add_child(_sub_tab(UiStyle.SUB_TAB_PERSONAL, VIEW_PERSONAL, view == VIEW_PERSONAL))
	if view == VIEW_ROOM and not editable:
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.add_child(spacer)
		bar.add_child(_read_only_badge())
	var top := bar_top + BAR_HEIGHT + ROW_GAP
	if view == VIEW_ROOM:
		var map_height := LobbyGeometry.PANEL_INNER_H - BAR_HEIGHT - ROW_GAP
		if not training:
			map_height -= (ONLINE_ROW_HEIGHT + ROW_GAP) * 2.0
			var name_row := _row(top, ONLINE_ROW_HEIGHT, UiStyle.ROW_ROOM_NAME, UiStyle.ROW_ROOM_NAME_DESC, editable)
			_room_name_input = SlantInput.new()
			_room_name_input.size = INPUT_SIZE
			_place_right(name_row, _room_name_input)
			name_row.add_child(_room_name_input)
			_room_name_input.setup(RoomState.NAME_MAX_LENGTH, "", editable)
			_room_name_input.committed.connect(func(text: String) -> void: room_name_committed.emit(text))
			top += ONLINE_ROW_HEIGHT + ROW_GAP
		var map_row := _row(top, map_height, UiStyle.ROW_MAP, UiStyle.ROW_MAP_DESC, editable)
		_map_button = SelectTile.new()
		_map_button.size = MAP_BUTTON_SIZE
		_map_button.position = Vector2(36.0 + LobbyGeometry.TAN * 120.0, 120.0)
		_map_button.mouse_filter = Control.MOUSE_FILTER_STOP if editable else Control.MOUSE_FILTER_IGNORE
		map_row.add_child(_map_button)
		_map_button.configure(SelectTile.Kind.MAP, &"", "")
		_map_button.pressed.connect(func() -> void: map_button_pressed.emit())
		top += map_height + ROW_GAP
		if not training:
			var count_row := _row(top, ONLINE_ROW_HEIGHT, UiStyle.ROW_MAX_PLAYERS, UiStyle.ROW_MAX_PLAYERS_DESC, editable)
			var chips := HBoxContainer.new()
			chips.add_theme_constant_override("separation", 12)
			chips.size = Vector2(3 * 118 + 24, 68)
			_place_right(count_row, chips)
			count_row.add_child(chips)
			for count in range(RoomState.MIN_PLAYERS, RoomState.MAX_PLAYERS + 1):
				var chip := _chip_button(UiStyle.PLAYER_COUNT_CHIP % count)
				var value := count
				chip.pressed.connect(func() -> void: max_players_pressed.emit(value))
				chips.add_child(chip)
				_player_chips[count] = chip
	else:
		var height := (LobbyGeometry.PANEL_INNER_H - BAR_HEIGHT - ROW_GAP * 3.0) / 3.0
		for pref_key: StringName in [&"bgm", &"sfx"]:
			var row := _row(top, height, UiStyle.ROW_BGM if pref_key == &"bgm" else UiStyle.ROW_SFX, UiStyle.ROW_VOLUME_DESC, true)
			row.add_child(_slider_row(row, pref_key))
			top += height + ROW_GAP
		var nick_row := _row(top, height, UiStyle.ROW_NICKNAME, UiStyle.ROW_NICKNAME_DESC, true)
		_nickname_input = SlantInput.new()
		_nickname_input.size = INPUT_SIZE
		_place_right(nick_row, _nickname_input)
		nick_row.add_child(_nickname_input)
		_nickname_input.setup(PlayerData.NAME_MAX_LENGTH, "", true)
		_nickname_input.committed.connect(func(text: String) -> void: nickname_committed.emit(text))

func _row(top: float, height: float, title: String, description: String, editable: bool) -> SlantBox:
	var row := SlantBox.new()
	row.position = Vector2(LobbyGeometry.PANEL_BORDER + LobbyGeometry.PANEL_PAD + LobbyGeometry.TAN * top, top)
	row.size = Vector2(LobbyGeometry.PANEL_INNER_W, height)
	row.fill = Color.WHITE if editable else UiStyle.LOBBY_READ_ONLY
	row.border_color = UiStyle.LOBBY_LINE_DARK
	row.border_width = 4.0
	row.corner_radius = 16.0
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(row)
	var title_label := _label(title, 34, UiStyle.LOBBY_TEXT, UiStyle.bold_font())
	title_label.position = Vector2(36.0 + LobbyGeometry.TAN * 24.0, 24.0)
	row.add_child(title_label)
	var description_label := _label(description, 20, UiStyle.LOBBY_TEXT_DIM)
	description_label.position = Vector2(36.0 + LobbyGeometry.TAN * 76.0, 76.0)
	row.add_child(description_label)
	return row

## Right edge of a row, vertically centered, following the slant.
func _place_right(row: Control, child: Control) -> void:
	var y := (row.size.y - child.size.y) / 2.0
	child.position = Vector2(row.size.x - 36.0 - child.size.x + LobbyGeometry.TAN * y, y)

func _slider_row(row: Control, pref_key: StringName) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 16)
	line.size = Vector2(SLIDER_WIDTH + 80, 48)
	_place_right(row, line)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.custom_minimum_size = Vector2(SLIDER_WIDTH, 48)
	slider.focus_mode = Control.FOCUS_NONE
	var track := StyleBoxFlat.new()
	track.bg_color = UiStyle.LOBBY_READ_ONLY
	track.set_corner_radius_all(6)
	track.content_margin_top = 6
	track.content_margin_bottom = 6
	var filled := StyleBoxFlat.new()
	filled.bg_color = UiStyle.LOBBY_SLIDER
	filled.set_corner_radius_all(6)
	filled.content_margin_top = 6
	filled.content_margin_bottom = 6
	slider.add_theme_stylebox_override("slider", track)
	slider.add_theme_stylebox_override("grabber_area", filled)
	slider.add_theme_stylebox_override("grabber_area_highlight", filled)
	line.add_child(slider)
	var value_label := _label("0", 28, UiStyle.LOBBY_TEXT, UiStyle.bold_font())
	value_label.custom_minimum_size.x = 64
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_child(value_label)
	slider.value_changed.connect(func(value: float) -> void:
		value_label.text = str(int(value))
		pref_changed.emit(pref_key, int(value)))
	_sliders[pref_key] = slider
	_slider_values[pref_key] = value_label
	return line

func _sub_tab(text: String, view: int, selected: bool) -> Button:
	var button := _chip_button(text)
	_style_chip(button, selected)
	button.pressed.connect(func() -> void: sub_tab_selected.emit(view))
	return button

func _chip_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(118, 68)
	button.add_theme_font_override("font", UiStyle.bold_font())
	button.add_theme_font_size_override("font_size", 26)
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
		button.add_theme_color_override(color_name, UiStyle.LOBBY_TEXT)
	_style_chip(button, false)
	return button

func _style_chip(button: Button, selected: bool) -> void:
	var fill := UiStyle.LOBBY_GOLD_BG if selected else Color.WHITE
	var border := UiStyle.LOBBY_GOLD if selected else UiStyle.LOBBY_LINE
	for state_name in ["normal", "hover", "pressed", "disabled"]:
		var style := UiStyle.box(fill if state_name != "disabled" or selected else UiStyle.LOBBY_TAB_IDLE, border, 4, 34)
		style.content_margin_top = 4
		style.content_margin_bottom = 4
		button.add_theme_stylebox_override(state_name, style)
	button.modulate.a = 0.5 if button.disabled and not selected else 1.0

func _read_only_badge() -> HBoxContainer:
	var badge := HBoxContainer.new()
	badge.add_theme_constant_override("separation", 8)
	var lock := TextureRect.new()
	lock.texture = LobbyIcons.texture(LobbyIcons.Kind.LOCK)
	lock.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	lock.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	lock.custom_minimum_size = Vector2(26, 26)
	lock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lock.self_modulate = Color.WHITE
	badge.add_child(lock)
	var text := _label(UiStyle.READ_ONLY, 20, Color.WHITE)
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.add_child(text)
	return badge

func _map_english(id: StringName) -> String:
	var entry := Session.catalog.map(id)
	return entry.english_name if entry != null else ""

func _label(text: String, font_size: int, color: Color, font: Font = null) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if font != null:
		label.add_theme_font_override("font", font)
	return label
