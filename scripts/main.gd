extends Control

var menu: PanelContainer
var lobby: PanelContainer
var result_panel: PanelContainer
var name_field: LineEdit
var address_field: LineEdit
var port_field: SpinBox
var menu_notice: Label
var lobby_notice: Label
var roster_label: Label
var start_button: Button
var back_button: Button
var identity: Label
var result_label: Label
var return_button: Button
var background: ColorRect

func _ready() -> void:
	background = ColorRect.new()
	background.color = Color("101927")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	menu = _panel(layer, Vector2(370, 95), Vector2(540, 530))
	var content := _column(menu)
	_heading(content, "Gfight")
	_label(content, "플랫폼 격투 · 스톡 3개 · 마지막 생존자가 승리")
	_label(content, "플레이어 이름")
	name_field = LineEdit.new()
	name_field.text = "Player"
	name_field.max_length = 20
	content.add_child(name_field)
	_label(content, "접속 주소 (같은 컴퓨터: 127.0.0.1)")
	address_field = LineEdit.new()
	address_field.text = "127.0.0.1"
	content.add_child(address_field)
	_label(content, "포트")
	port_field = SpinBox.new()
	port_field.min_value = 1024
	port_field.max_value = 65535
	port_field.value = Session.DEFAULT_PORT
	content.add_child(port_field)
	_button(content, "방 만들기", func(): Session.host_game(name_field.text, int(port_field.value)))
	_button(content, "방 참가", func(): Session.join_game(address_field.text, int(port_field.value), name_field.text))
	_button(content, "한 키보드로 2인 플레이", Session.local_game)
	menu_notice = _label(content, "")
	menu_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lobby = _panel(layer, Vector2(370, 150), Vector2(540, 420))
	var lobby_content := _column(lobby)
	_heading(lobby_content, "대기방")
	lobby_notice = _label(lobby_content, "")
	lobby_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	roster_label = _label(lobby_content, "")
	roster_label.custom_minimum_size.y = 130
	start_button = _button(lobby_content, "경기 시작", func(): Session.start_game())
	_button(lobby_content, "메뉴로", Session.leave)
	identity = Label.new()
	identity.position = Vector2(24, 175)
	identity.add_theme_font_size_override("font_size", 20)
	layer.add_child(identity)
	back_button = Button.new()
	back_button.text = "나가기 (Esc)"
	back_button.position = Vector2(1100, 180)
	back_button.pressed.connect(Session.leave)
	layer.add_child(back_button)
	result_panel = _panel(layer, Vector2(420, 240), Vector2(440, 220))
	var result_content := _column(result_panel)
	result_label = _heading(result_content, "")
	return_button = _button(result_content, "대기방으로 · 재경기", Session.return_to_lobby)
	_button(result_content, "메뉴로", Session.leave)
	Session.changed.connect(_refresh)
	_refresh()

func _physics_process(_delta: float) -> void:
	if Session.phase == "playing" and not Session.local_mode:
		Session.submit_local_input(Fighter.read_keyboard([KEY_A, KEY_D, KEY_W, KEY_J], KEY_S))

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		Session.leave()

func _refresh() -> void:
	menu.visible = Session.phase in ["menu", "connecting"]
	background.visible = Session.phase in ["menu", "connecting", "lobby"]
	lobby.visible = Session.phase == "lobby"
	result_panel.visible = Session.phase == "result"
	back_button.visible = Session.phase in ["playing", "result"]
	identity.visible = back_button.visible
	menu_notice.text = Session.message
	lobby_notice.text = Session.message
	start_button.disabled = not Session.can_start()
	start_button.text = "경기 시작" if Session.can_start() else ("2명 이상 필요합니다" if Session.roster.size() < 2 else "호스트가 시작할 때까지 대기")
	var names := PackedStringArray(["참가자 %d / %d" % [Session.roster.size(), Session.MAX_PLAYERS]])
	var ids := Session.roster.keys()
	ids.sort()
	for slot in range(ids.size()):
		var id: int = ids[slot]
		var suffix := " (나)" if id == multiplayer.get_unique_id() else ""
		names.append("P%d · %s%s" % [slot + 1, Session.roster[id], suffix])
	roster_label.text = "\n".join(names)
	var own_slot := ids.find(multiplayer.get_unique_id()) + 1
	if is_instance_valid(Session.arena):
		for fighter in Session.arena.fighters:
			if fighter.player_id == multiplayer.get_unique_id():
				own_slot = fighter.player_slot
	identity.text = "로컬 2인: P1 WASD/J · P2 방향키/K" if Session.local_mode else "내 플레이어: P%d · %s" % [own_slot, Session.local_name]
	return_button.disabled = not Session.local_mode and not multiplayer.is_server()
	if Session.phase == "result" and is_instance_valid(Session.arena):
		result_label.text = Session.arena.result.replace(" — R: Restart", "")

func _panel(parent: Node, at: Vector2, size: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.position = at
	panel.custom_minimum_size = size
	var style := StyleBoxFlat.new()
	style.bg_color = Color("223147")
	style.set_corner_radius_all(12)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	return panel

func _column(parent: Node) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	parent.add_child(column)
	return column

func _label(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	parent.add_child(label)
	return label

func _heading(parent: Node, text: String) -> Label:
	var label := _label(parent, text)
	label.add_theme_font_size_override("font_size", 30)
	return label

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 36
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
