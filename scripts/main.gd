extends Control
## Screen flow from Design/ui-ux-scenes-v2.pdf: S1 menu, S1-1 join popup, S2 lobby,
## S3 match HUD, S4 result. Screens only call Session and redraw on Session.changed.

## [제안] Short fade between screens.
@export var fade_seconds: float = 0.2
## [제안] Pause on the final ring-out before S4 appears.
@export var result_delay: float = 0.8
@export var toast_seconds: float = 3.0

var background: ColorRect
var menu: Control
var join_popup: Control
var lobby: Control
var hud: MatchHud
var result_panel: ResultScreen
var fade: ColorRect
var join_button: Button
var create_button: Button
var quit_button: Button
var toast_panel: PanelContainer
var toast_label: Label
var address_field: LineEdit
var join_error_label: Label
var join_confirm_button: Button
var join_cancel_button: Button
var address_label: Label
var copy_button: Button
var slot_panels: Array[PanelContainer] = []
var slot_labels: Array[Dictionary] = []
var count_label: Label
var ready_count_label: Label
var stock_label: Label
var notice_label: Label
var hint_label: Label
var leave_button: Button
var ready_button: Button
var start_button: Button
var close_dialog: ConfirmationDialog
var _join_open: bool = false
var _last_phase: String = ""
var _result_wait: float = 0.0
var _toast_left: float = 0.0

func _ready() -> void:
	background = ColorRect.new()
	background.color = UiStyle.BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_build_menu(layer)
	_build_join_popup(layer)
	_build_lobby(layer)
	hud = MatchHud.new()
	layer.add_child(hud)
	result_panel = ResultScreen.new()
	layer.add_child(result_panel)
	fade = ColorRect.new()
	fade.color = Color(UiStyle.BACKGROUND, 0.0)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(fade)
	Session.changed.connect(_refresh)
	_refresh()

func _process(delta: float) -> void:
	if _toast_left > 0.0:
		_toast_left = maxf(0.0, _toast_left - delta)
		toast_panel.visible = _toast_left > 0.0
	if Session.phase == "result" and not result_panel.visible:
		_result_wait += delta
		if _result_wait >= result_delay:
			result_panel.visible = true
			hud.visible = false
			result_panel.refresh()

func _physics_process(_delta: float) -> void:
	if Session.phase == "playing" and not Session.local_mode:
		Session.submit_local_input(Fighter.read_keyboard([KEY_A, KEY_D, KEY_W, KEY_J], KEY_S))

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key := (event as InputEventKey).physical_keycode
	if key == KEY_ESCAPE and join_popup.visible:
		_cancel_join()
		get_viewport().set_input_as_handled()
	elif (key == KEY_ENTER or key == KEY_KP_ENTER) and result_panel.visible:
		Session.confirm_result()
		get_viewport().set_input_as_handled()

func _refresh() -> void:
	var phase := Session.phase
	if phase != _last_phase:
		_on_phase_changed(phase)
	background.visible = phase in ["menu", "connecting", "lobby", "closing"]
	menu.visible = phase in ["menu", "connecting"]
	join_popup.visible = _join_open and menu.visible
	lobby.visible = phase in ["lobby", "closing"]
	if phase != "result":
		result_panel.visible = false
	hud.visible = phase in ["playing", "result"] and not result_panel.visible
	if not Session.toast.is_empty():
		_show_toast(Session.toast)
		Session.toast = ""
	_refresh_menu()
	_refresh_join()
	if lobby.visible:
		_refresh_lobby()
	if result_panel.visible:
		result_panel.refresh()

func _on_phase_changed(phase: String) -> void:
	_last_phase = phase
	_result_wait = 0.0
	if phase == "menu" and not _join_open:
		join_button.call_deferred("grab_focus")
	if phase == "lobby" and _join_open:
		_join_open = false
	if fade_seconds > 0.0 and is_inside_tree():
		fade.color.a = 1.0
		create_tween().tween_property(fade, "color:a", 0.0, fade_seconds)

# S1 main menu ---------------------------------------------------------------

func _build_menu(layer: CanvasLayer) -> void:
	menu = _full_rect(layer)
	var panel := _panel(menu, UiStyle.box(UiStyle.PANEL, UiStyle.TEXT_DIM, 1, 14))
	panel.custom_minimum_size = Vector2(380, 0)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var column := _column(panel, 14)
	var title := _label(column, UiStyle.TITLE, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(HSeparator.new())
	join_button = _button(column, UiStyle.JOIN, _open_join)
	create_button = _button(column, UiStyle.CREATE, _create_room)
	quit_button = _button(column, UiStyle.QUIT, func() -> void: get_tree().quit())
	toast_panel = _panel(menu, UiStyle.box(UiStyle.PANEL_MUTED, UiStyle.TEXT_DIM, 1, 20))
	toast_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
	toast_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast_panel.position.y -= 110
	toast_label = _label(toast_panel, "", 18)
	toast_panel.visible = false
	var version := _label(menu, "v%s" % Session.game_version(), 14)
	version.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	version.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	version.position -= Vector2(16, 12)

func _refresh_menu() -> void:
	var busy := Session.phase == "connecting"
	join_button.disabled = busy
	create_button.disabled = busy
	create_button.text = UiStyle.CREATE

func _create_room() -> void:
	create_button.disabled = true
	create_button.text = UiStyle.CREATING
	await get_tree().process_frame
	Session.host_game(Session.local_name)
	_refresh()

func _show_toast(text: String) -> void:
	toast_label.text = text
	toast_panel.visible = true
	_toast_left = toast_seconds

# S1-1 join popup ------------------------------------------------------------

func _build_join_popup(layer: CanvasLayer) -> void:
	join_popup = _full_rect(layer)
	join_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	var dimmer := ColorRect.new()
	dimmer.color = UiStyle.DIMMER
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	join_popup.add_child(dimmer)
	var panel := _panel(join_popup, UiStyle.box(UiStyle.PANEL, UiStyle.TEXT_DIM, 1, 14))
	panel.custom_minimum_size = Vector2(480, 0)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var column := _column(panel, 14)
	_label(column, UiStyle.JOIN, 26)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)
	_label(row, UiStyle.ADDRESS, 18)
	address_field = LineEdit.new()
	address_field.placeholder_text = "%s:%d" % [Session.DEFAULT_ADDRESS, Session.DEFAULT_PORT]
	address_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	address_field.text_submitted.connect(func(_text: String) -> void: _submit_join())
	row.add_child(address_field)
	join_error_label = _label(column, "", 16)
	join_error_label.add_theme_color_override("font_color", UiStyle.ERROR)
	join_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	join_error_label.custom_minimum_size.y = 24
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)
	join_cancel_button = _button(buttons, UiStyle.CANCEL, _cancel_join)
	join_cancel_button.custom_minimum_size.x = 110
	join_confirm_button = _button(buttons, UiStyle.JOIN_CONFIRM, _submit_join)
	join_confirm_button.custom_minimum_size.x = 110

func _open_join() -> void:
	_join_open = true
	Session.join_error = ""
	address_field.text = Session.last_address
	_refresh()
	address_field.grab_focus()
	address_field.caret_column = address_field.text.length()

func _submit_join() -> void:
	if Session.phase == "connecting":
		return
	Session.join_address(address_field.text, Session.local_name)

func _cancel_join() -> void:
	_join_open = false
	Session.cancel_join()
	_refresh()
	join_button.grab_focus()

func _refresh_join() -> void:
	var connecting := Session.phase == "connecting"
	address_field.editable = not connecting
	join_confirm_button.disabled = connecting
	join_confirm_button.text = UiStyle.CONNECTING if connecting else UiStyle.JOIN_CONFIRM
	join_error_label.text = "" if connecting else Session.join_error

# S2 lobby -------------------------------------------------------------------

func _build_lobby(layer: CanvasLayer) -> void:
	lobby = _full_rect(layer)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	lobby.add_child(margin)
	var column := _column(margin, 24)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	column.add_child(header)
	var title := _label(header, UiStyle.LOBBY, 30)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	address_label = _label(header, "", 18)
	copy_button = _button(header, UiStyle.COPY, func() -> void: DisplayServer.clipboard_set(Session.room_address))
	column.add_child(HSeparator.new())
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 16)
	slots.custom_minimum_size.y = 220
	column.add_child(slots)
	for index in range(Session.MAX_PLAYERS):
		var slot := PanelContainer.new()
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slots.add_child(slot)
		var content := _column(slot, 8)
		content.alignment = BoxContainer.ALIGNMENT_CENTER
		var entries := {}
		entries.title = _centered(content, 24)
		entries.tag = _centered(content, 16)
		entries.color = _centered(content, 18)
		entries.line = HSeparator.new()
		content.add_child(entries.line)
		entries.state = _centered(content, 18)
		slot_panels.append(slot)
		slot_labels.append(entries)
	var counts := HBoxContainer.new()
	counts.add_theme_constant_override("separation", 48)
	column.add_child(counts)
	count_label = _label(counts, "", 20)
	ready_count_label = _label(counts, "", 20)
	stock_label = _label(counts, "", 20)
	notice_label = _label(counts, "", 18)
	notice_label.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
	notice_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	column.add_child(buttons)
	leave_button = _button(buttons, UiStyle.LEAVE, _leave_lobby)
	leave_button.custom_minimum_size.x = 160
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(gap)
	ready_button = _button(buttons, UiStyle.READY_BUTTON, func() -> void: Session.set_ready(ready_button.button_pressed))
	ready_button.toggle_mode = true
	ready_button.custom_minimum_size.x = 200
	start_button = _button(buttons, UiStyle.START, _start_match)
	start_button.custom_minimum_size.x = 200
	hint_label = _label(column, "", 16)
	hint_label.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	close_dialog = ConfirmationDialog.new()
	close_dialog.dialog_text = UiStyle.CLOSE_ROOM_CONFIRM
	close_dialog.confirmed.connect(Session.leave_room)
	lobby.add_child(close_dialog)

func _refresh_lobby() -> void:
	var my_id := multiplayer.get_unique_id()
	var ids := Session.sorted_ids()
	address_label.text = UiStyle.ROOM_ADDRESS % Session.room_address
	address_label.visible = not Session.room_address.is_empty()
	copy_button.visible = address_label.visible
	for index in range(slot_panels.size()):
		var entries: Dictionary = slot_labels[index]
		var filled := index < ids.size()
		var id: int = ids[index] if filled else 0
		var mine := filled and not Session.local_mode and id == my_id
		var border := UiStyle.ACCENT if mine else UiStyle.TEXT_DIM
		slot_panels[index].add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL if filled else UiStyle.BACKGROUND, border, 3 if mine else 1, 10))
		entries.line.visible = filled
		entries.color.visible = filled
		entries.state.visible = filled
		if not filled:
			entries.title.text = ""
			entries.tag.text = UiStyle.EMPTY_SLOT
			entries.tag.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
			continue
		entries.title.text = "P%d%s" % [index + 1, " ★" if id == 1 else ""]
		var tags := PackedStringArray()
		if id == 1 and not Session.local_mode:
			tags.append(UiStyle.HOST_TAG)
		if mine:
			tags.append(UiStyle.ME_TAG)
		entries.tag.text = " ".join(tags)
		entries.tag.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
		entries.color.text = "■ %s" % UiStyle.SLOT_COLOR_NAMES[index]
		entries.color.add_theme_color_override("font_color", UiStyle.slot_color(index + 1))
		var is_ready: bool = Session.ready_states.get(id, false)
		if id == 1 or Session.local_mode:
			entries.state.text = UiStyle.STATE_HOST if id == 1 else UiStyle.STATE_READY
			entries.state.add_theme_color_override("font_color", UiStyle.TEXT)
		else:
			entries.state.text = UiStyle.STATE_READY if is_ready else UiStyle.STATE_WAITING
			entries.state.add_theme_color_override("font_color", UiStyle.READY if is_ready else UiStyle.TEXT_DIM)
	var participants := ids.size() - 1
	count_label.text = UiStyle.PLAYER_COUNT % [ids.size(), Session.MAX_PLAYERS]
	ready_count_label.text = UiStyle.READY_COUNT % [Session.ready_count(), participants]
	ready_count_label.visible = not Session.local_mode
	stock_label.text = UiStyle.STOCK_RULE % CombatRules.INITIAL_STOCKS
	notice_label.text = Session.message
	var closing := Session.phase == "closing"
	leave_button.disabled = closing
	var host := Session.is_host()
	start_button.visible = host
	ready_button.visible = not host
	if host:
		start_button.disabled = not Session.can_start()
		start_button.text = UiStyle.START
		if ids.size() < 2:
			hint_label.text = UiStyle.NEED_TWO
		elif not Session.all_ready():
			hint_label.text = UiStyle.NEED_READY
		else:
			hint_label.text = ""
	else:
		var mine_ready: bool = Session.ready_states.get(my_id, false)
		ready_button.set_pressed_no_signal(mine_ready)
		ready_button.text = ("✔ " if mine_ready else "") + UiStyle.READY_BUTTON
		if not mine_ready:
			hint_label.text = UiStyle.PRESS_READY
		elif Session.all_ready():
			hint_label.text = UiStyle.WAIT_HOST
		else:
			hint_label.text = UiStyle.WAIT_OTHERS

func _start_match() -> void:
	start_button.disabled = true
	start_button.text = UiStyle.STARTING
	if not Session.start_game():
		_refresh()

func _leave_lobby() -> void:
	if not Session.local_mode and multiplayer.is_server() and not multiplayer.get_peers().is_empty():
		close_dialog.popup_centered()
	else:
		Session.leave_room()

# Helpers --------------------------------------------------------------------

func _full_rect(parent: Node) -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(root)
	return root

func _panel(parent: Node, style: StyleBoxFlat) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	return panel

func _column(parent: Node, separation: int) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", separation)
	parent.add_child(column)
	return column

func _label(parent: Node, text: String, font_size: int = 18) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label

func _centered(parent: Node, font_size: int) -> Label:
	var label := _label(parent, "", font_size)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 44
	button.add_theme_font_size_override("font_size", 18)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
