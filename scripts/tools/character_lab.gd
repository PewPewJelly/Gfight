class_name CharacterLab
extends Node
## Development-only practice room: one character and a dummy, with live tuning, hit area
## display, and slow motion. Opened from the character workshop; no game menu leads here,
## so the training room stays free of cheats (Docs/02 decision 8).
##
## Unlike the game, this edits the loaded character resources directly. Nothing reaches the
## files until the save button is pressed.

const DUMMY_ID := 2
const PLAYER_ID := 1
const LAB_STOCKS := 99
const PANEL_WIDTH := 340.0
const SLOW_SPEEDS: Array[float] = [1.0, 0.5, 0.25]
const PLAYER_START_X := 420.0
const DUMMY_START_X := 620.0
const FLOOR_Y := 540.0
const WINDOW_SIZE := Vector2i(1600, 900)
const STAGE_ZOOM := 0.73
const STAGE_CENTER := Vector2(872.0, 360.0)
const BODY_COLOR := Color(0.45, 0.7, 1.0)
const HIT_COLOR := Color(0.89, 0.29, 0.29)
const SHOT_COLOR := Color(0.95, 0.72, 0.3)
const STARTUP_COLOR := Color(0.94, 0.62, 0.15)
const RECOVERY_COLOR := Color(0.52, 0.72, 0.92)
const FONT_PATH := "res://resources/fonts/noto_kr_medium.tres"
const HELP := "A/D 이동 · Space 점프 · W/S 방향 · J 공격 · K 스킬\nF1 패널 · F2 판정 표시 · F3 슬로모션 · F4 처음 위치로"

## Draws bodies, live hit areas, and projectile hit areas over the stage.
class HitAreas extends Node2D:
	var lab: CharacterLab

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		for fighter in lab.arena.fighters:
			if fighter.life_state != Fighter.LifeState.ACTIVE:
				continue
			draw_rect(Rect2(fighter.position - fighter.half_size, fighter.half_size * 2.0), BODY_COLOR, false, 1.5)
			if fighter.move_phase == Fighter.MovePhase.ACTIVE:
				var box := fighter.attack_box()
				box.position += fighter.position
				draw_rect(box, Color(HIT_COLOR, 0.3))
				draw_rect(box, HIT_COLOR, false, 2.0)
		for shot in lab.arena.projectiles:
			draw_rect(shot.box(), SHOT_COLOR, false, 2.0)

## The last move's startup, active, and recovery frames with a marker on the current frame.
class FrameBar extends Control:
	var lab: CharacterLab

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var move := lab.player.active_move
		if move == null:
			return
		var total := float(move.total_frames())
		var x := 0.0
		for part: Array in [[maxi(0, move.startup_frames), STARTUP_COLOR], [maxi(1, move.active_frames), HIT_COLOR], [maxi(0, move.recovery_frames), RECOVERY_COLOR]]:
			var width: float = size.x * float(part[0]) / total
			draw_rect(Rect2(x, 0.0, width, size.y), part[1])
			x += width
		if lab.player.move_phase != Fighter.MovePhase.NONE:
			var marker := size.x * float(lab.player.move_frame) / total
			draw_rect(Rect2(marker - 1.0, -3.0, 3.0, size.y + 6.0), Color.WHITE)

## Character to open. Empty reads the file the workshop wrote.
var requested_id: StringName = &""
## Catalog to look the character up in. Empty loads the project's.
var catalog: ContentCatalog
var arena: FightArena
var player: Fighter
var dummy: Fighter
var character: CharacterDef
var dirty: bool = false
var slow_index: int = 0
var areas: HitAreas
var shown_move: AttackData

var panel: PanelContainer
var move_form: TuningForm
var movement_form: TuningForm
var character_form: TuningForm
var kit_form: TuningForm
var move_title: Label
var frame_text: Label
var status_label: Label
var save_button: Button
var dummy_percent: SpinBox
var hold_percent: CheckBox
var speed_label: Label

func _ready() -> void:
	if catalog == null:
		catalog = load(CharacterFiles.CATALOG_PATH)
	character = _target_character()
	if character == null:
		push_error("Character lab: no character to open")
		return
	if get_window().mode == Window.MODE_FULLSCREEN or get_window().mode == Window.MODE_EXCLUSIVE_FULLSCREEN:
		get_window().mode = Window.MODE_WINDOWED
		get_window().size = WINDOW_SIZE
		get_window().move_to_center()
	_start_arena()
	_build_overlay()
	_refresh_forms()
	reset_positions()

func _exit_tree() -> void:
	Engine.time_scale = 1.0

func _target_character() -> CharacterDef:
	var id := requested_id
	if String(id).is_empty() and FileAccess.file_exists(CharacterFiles.LAB_TARGET_FILE):
		id = StringName(FileAccess.get_file_as_string(CharacterFiles.LAB_TARGET_FILE).strip_edges())
	var entry := catalog.character(id)
	return entry if entry != null else catalog.character(catalog.default_character())

func _start_arena() -> void:
	arena = load("res://arena.tscn").instantiate()
	arena.standalone = false
	arena.authoritative = true
	arena.catalog = catalog
	arena.starting_stocks = LAB_STOCKS
	arena.local_player_id = PLAYER_ID
	arena.participant_ids.assign([PLAYER_ID, DUMMY_ID])
	arena.dummy_ids.assign([DUMMY_ID])
	arena.character_ids = {PLAYER_ID: character.id, DUMMY_ID: CharacterFiles.BASELINE_ID}
	arena.input_provider = _input_for
	add_child(arena)
	arena.countdown_left = 0.0
	player = arena.fighter_by_id(PLAYER_ID)
	dummy = arena.fighter_by_id(DUMMY_ID)
	for fighter in arena.fighters:
		fighter.tag_emphasis = false
	for child in arena.get_children():
		if child is Camera2D:
			child.zoom = Vector2.ONE * STAGE_ZOOM
			child.position = STAGE_CENTER
	areas = HitAreas.new()
	areas.lab = self
	arena.add_child(areas)

## Keys typed into a number box must not also move the fighter.
func _input_for(id: int) -> int:
	if id != PLAYER_ID or get_viewport().gui_get_focus_owner() is LineEdit:
		return 0
	return Fighter.read_keyboard(Fighter.P1_KEYS)

func _physics_process(_delta: float) -> void:
	if player == null:
		return
	if hold_percent.button_pressed:
		dummy.percent = dummy_percent.value
	if player.active_move != shown_move and player.active_move != null:
		shown_move = player.active_move
		_show_move()
	if shown_move != null:
		frame_text.text = "선딜 %d · 지속 %d · 후딜 %d · 현재 %s" % [shown_move.startup_frames, shown_move.active_frames, shown_move.recovery_frames, "%df" % player.move_frame if player.move_phase != Fighter.MovePhase.NONE else "-"]

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_F1:
			panel.visible = not panel.visible
		KEY_F2:
			areas.visible = not areas.visible
		KEY_F3:
			cycle_speed()
		KEY_F4:
			reset_positions()

func cycle_speed() -> void:
	slow_index = (slow_index + 1) % SLOW_SPEEDS.size()
	Engine.time_scale = SLOW_SPEEDS[slow_index]
	speed_label.text = "속도 %d%%" % roundi(SLOW_SPEEDS[slow_index] * 100.0)

func reset_positions() -> void:
	arena.projectiles.clear()
	player.reset_round(Vector2(PLAYER_START_X, FLOOR_Y - player.half_size.y))
	dummy.reset_round(Vector2(DUMMY_START_X, FLOOR_Y - dummy.half_size.y))
	player.stocks = LAB_STOCKS
	dummy.stocks = LAB_STOCKS
	dummy.percent = dummy_percent.value

func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root_control := Control.new()
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.theme = _korean_theme()
	layer.add_child(root_control)
	root_control.add_child(_build_help())
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -PANEL_WIDTH
	root_control.add_child(panel)
	panel.add_child(_build_panel_content())

func _korean_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = load(FONT_PATH)
	theme.default_font_size = 14
	return theme

func _build_help() -> Control:
	var box := VBoxContainer.new()
	box.position = Vector2(16, 12)
	box.custom_minimum_size.x = 620.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := Label.new()
	title.text = "연습실 — %s" % character.display_name
	box.add_child(title)
	var help := Label.new()
	help.text = HELP
	box.add_child(help)
	speed_label = Label.new()
	speed_label.text = "속도 100%"
	box.add_child(speed_label)
	frame_text = Label.new()
	frame_text.text = "기술을 쓰면 프레임이 표시됩니다"
	box.add_child(frame_text)
	var bar := FrameBar.new()
	bar.lab = self
	bar.custom_minimum_size = Vector2(0, 12)
	box.add_child(bar)
	return box

func _build_panel_content() -> Control:
	var column := VBoxContainer.new()
	var buttons := HBoxContainer.new()
	save_button = _button("저장", save_character)
	save_button.disabled = CharacterFiles.is_baseline(character) or not OS.has_feature("editor")
	buttons.add_child(save_button)
	buttons.add_child(_button("되돌리기", revert_character))
	buttons.add_child(_button("처음 위치로", reset_positions))
	column.add_child(buttons)
	status_label = Label.new()
	status_label.text = "기준 캐릭터는 저장할 수 없습니다." if CharacterFiles.is_baseline(character) else ""
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(status_label)
	var dummy_row := HBoxContainer.new()
	var dummy_label := Label.new()
	dummy_label.text = "허수아비 배율"
	dummy_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dummy_row.add_child(dummy_label)
	dummy_percent = SpinBox.new()
	dummy_percent.max_value = 999.0
	dummy_percent.suffix = "%"
	dummy_percent.value_changed.connect(func(value: float) -> void: dummy.percent = value)
	dummy_row.add_child(dummy_percent)
	hold_percent = CheckBox.new()
	hold_percent.text = "고정"
	hold_percent.focus_mode = Control.FOCUS_NONE
	dummy_row.add_child(hold_percent)
	column.add_child(dummy_row)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(tabs)
	move_form = _add_tab(tabs, "기술")
	move_title = Label.new()
	move_title.text = "기술을 쓰면 여기에 수치가 나옵니다"
	move_form.get_parent().add_child(move_title)
	move_form.get_parent().move_child(move_title, 0)
	movement_form = _add_tab(tabs, "이동")
	character_form = _add_tab(tabs, "몸과 그림")
	character_form.only_fields = [&"body_size", &"sprite_height", &"sprite_offset", &"sprite_faces_left"]
	kit_form = _add_tab(tabs, "기믹")
	return column

func _add_tab(tabs: TabContainer, title: String) -> TuningForm:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	tabs.add_child(scroll)
	var form := TuningForm.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.value_changed.connect(func(_resource: Resource, _field: StringName) -> void: _on_changed())
	form.structure_changed.connect(_on_changed)
	box.add_child(form)
	return form

func _button(text: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(pressed)
	return button

## Characters without their own movement get a private copy, so tuning cannot change the
## defaults every other character shares.
func _refresh_forms() -> void:
	if character.movement == null and not CharacterFiles.is_baseline(character):
		character.movement = CharacterFiles.copy_of(Fighter.DEFAULT_MOVEMENT)
		player.use_character(character)
	movement_form.show_resource(player.movement, Fighter.DEFAULT_MOVEMENT)
	character_form.show_resource(character)
	kit_form.show_resource(character.kit)
	_show_move()

func _show_move() -> void:
	if shown_move == null:
		return
	var slot_name := CharacterDef.SLOT_NAMES[player.attack_slot]
	move_title.text = "방금 쓴 기술: %s %s" % [slot_name, "스킬" if player.attack_is_skill else "기본 공격"]
	move_form.show_resource(shown_move)

func _on_changed() -> void:
	dirty = true
	# Body size and art are applied when a character is set up.
	var keep_state := player.kit_state
	player.use_character(character)
	player.kit_state = keep_state
	status_label.text = "저장하지 않은 변경이 있습니다."

func save_character() -> void:
	var error := CharacterFiles.save(character)
	if error == ERR_UNAUTHORIZED:
		status_label.text = "기준 캐릭터는 저장할 수 없습니다."
	elif error != OK:
		status_label.text = "저장하지 못했습니다 (%s)." % error_string(error)
	else:
		dirty = false
		status_label.text = "저장했습니다."

func revert_character() -> void:
	if character.resource_path.is_empty():
		return
	var index := catalog.characters.find(character)
	var reloaded: CharacterDef = ResourceLoader.load(character.resource_path, "", ResourceLoader.CACHE_MODE_REPLACE_DEEP)
	if reloaded == null:
		status_label.text = "되돌리지 못했습니다."
		return
	character = reloaded
	if index >= 0:
		catalog.characters[index] = reloaded
	shown_move = null
	move_form.show_resource(null)
	move_title.text = "기술을 쓰면 여기에 수치가 나옵니다"
	player.use_character(character)
	arena.index_projectile_types()
	reset_positions()
	_refresh_forms()
	dirty = false
	status_label.text = "저장된 값으로 되돌렸습니다."
