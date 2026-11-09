@tool
class_name WorkshopPanel
extends VBoxContainer
## The 캐릭터 작업실 screen: pick or create a character, adjust its numbers, see the selected
## move at game scale, and open the character lab. Runs in the editor through plugin.gd.

const SIDE_WIDTH := 140.0
const FORM_WIDTH := 260.0
const TAB_MOVE := 2
const BASIC_HIDDEN: Array[StringName] = [&"id", &"movement", &"kit", &"side_attack", &"up_attack", &"down_attack", &"air_up_attack", &"air_down_attack", &"side_skill", &"up_skill", &"down_skill", &"air_up_skill", &"air_down_skill"]
const OK_COLOR := Color(0.55, 0.85, 0.45)
const PROBLEM_COLOR := Color(0.95, 0.72, 0.3)

## EditorFileSystem, set by plugin.gd; null when the panel runs outside the editor.
var file_system: Object
var play_lab: Callable
## The editor's display scale, so fixed widths stay readable on high-resolution screens.
var ui_scale: float = 1.0

var catalog: ContentCatalog
var current: CharacterDef
var selected_slot: CharacterDef.Slot = CharacterDef.Slot.SIDE
var selected_skill: bool = false
var dirty: bool = false
var _loaded_time: int = 0
var _move_action: Callable

var character_list: ItemList
var problem_box: VBoxContainer
var slot_buttons: Array[Button] = []
var attack_button: Button
var skill_button: Button
var preview: MovePreview
var move_note: Label
var move_action_button: Button
var tabs: TabContainer
var basic_form: TuningForm
var movement_form: TuningForm
var move_form: TuningForm
var kit_form: TuningForm
var derived_label: Label
var status_label: Label
var save_button: Button
var new_dialog: ConfirmationDialog
var new_id: LineEdit
var new_name: LineEdit
var new_source: OptionButton
var new_error: Label
var new_match_label: Label
var new_lobby_label: Label
var _new_match_path: String = ""
var _new_lobby_path: String = ""
var unsaved_dialog: ConfirmationDialog
var _pending_index: int = -1

func _ready() -> void:
	_build()
	reload_catalog()

func _notification(what: int) -> void:
	# The character lab saves from its own process; pick that up when the editor regains focus.
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and is_visible_in_tree() and current != null and not dirty:
		if FileAccess.get_modified_time(current.resource_path) != _loaded_time:
			_reload_current()

func reload_catalog() -> void:
	catalog = load(CharacterFiles.CATALOG_PATH)
	character_list.clear()
	for entry in catalog.characters:
		character_list.add_item("%s (기준)" % entry.display_name if CharacterFiles.is_baseline(entry) else entry.display_name)
	if not catalog.characters.is_empty():
		character_list.select(0)
		select_character(0)

func select_character(index: int) -> void:
	current = catalog.characters[index]
	_loaded_time = FileAccess.get_modified_time(current.resource_path)
	var locked := CharacterFiles.is_baseline(current)
	if current.movement == null and not locked:
		current.movement = CharacterFiles.copy_of(Fighter.DEFAULT_MOVEMENT)
	var reference := _baseline()
	basic_form.read_only = locked
	basic_form.show_resource(current, reference)
	movement_form.read_only = locked
	movement_form.show_resource(current.movement if current.movement != null else Fighter.DEFAULT_MOVEMENT, Fighter.DEFAULT_MOVEMENT)
	kit_form.read_only = locked
	kit_form.show_resource(current)
	save_button.disabled = locked
	_set_dirty(false)
	_set_status("기준 캐릭터는 수정할 수 없습니다. [새 캐릭터]로 복사해서 쓰세요." if locked else "")
	show_move()
	_refresh_derived()
	_refresh_problems()

func show_move() -> void:
	for index in range(slot_buttons.size()):
		slot_buttons[index].set_pressed_no_signal(index == selected_slot)
	attack_button.set_pressed_no_signal(not selected_skill)
	skill_button.set_pressed_no_signal(selected_skill)
	var field := CharacterDef.slot_field(selected_slot, selected_skill)
	var own: AttackData = current.get(field)
	var shown: AttackData = current.skill(selected_slot) if selected_skill else current.attack(selected_slot)
	var locked := CharacterFiles.is_baseline(current)
	var reference: AttackData = null if selected_skill else _baseline().attack(selected_slot)
	move_form.read_only = locked or own == null
	move_form.show_resource(shown, reference)
	preview.show_move(current, shown)
	_describe_move(own, shown, locked)

## Explains what this slot currently holds and offers the one action that makes sense.
func _describe_move(own: AttackData, shown: AttackData, locked: bool) -> void:
	var sharing := _slots_sharing(own)
	if shown == null:
		_set_move_note("이 칸은 비어 있습니다.", "기술 만들기", _make_own_move.bind(null))
	elif own == null:
		_set_move_note("땅의 같은 방향 기술을 같이 씁니다.", "공중 전용으로 만들기", _make_own_move.bind(shown))
	elif not sharing.is_empty():
		_set_move_note("같은 기술을 쓰는 칸: %s" % ", ".join(sharing), "이 칸만 따로 만들기", _make_own_move.bind(shown))
	elif selected_skill:
		_set_move_note("", "이 칸 비우기", _clear_move)
	else:
		_set_move_note("", "", Callable())
	if locked:
		move_action_button.hide()

func _set_move_note(text: String, action_text: String, action: Callable) -> void:
	move_note.text = text
	move_action_button.text = action_text
	move_action_button.visible = not action_text.is_empty()
	_move_action = action

func _slots_sharing(own: AttackData) -> PackedStringArray:
	var names := PackedStringArray()
	if own == null:
		return names
	for slot: CharacterDef.Slot in CharacterDef.Slot.values():
		for is_skill: bool in [false, true]:
			if (slot != selected_slot or is_skill != selected_skill) and current.get(CharacterDef.slot_field(slot, is_skill)) == own:
				names.append(CharacterDef.SLOT_NAMES[slot])
	return names

func _make_own_move(source: AttackData) -> void:
	var made: AttackData = CharacterFiles.copy_of(source) if source != null else (SkillData.new() if selected_skill else AttackData.new())
	current.set(CharacterDef.slot_field(selected_slot, selected_skill), made)
	_mark_changed()
	show_move()

func _clear_move() -> void:
	current.set(CharacterDef.slot_field(selected_slot, selected_skill), null)
	_mark_changed()
	show_move()

func _baseline() -> CharacterDef:
	return catalog.character(CharacterFiles.BASELINE_ID)

func _build() -> void:
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(columns)
	columns.add_child(_build_character_column())
	columns.add_child(_build_move_column())
	columns.add_child(_build_form_column())
	add_child(_build_bottom_bar())
	_build_new_dialog()
	unsaved_dialog = ConfirmationDialog.new()
	unsaved_dialog.dialog_text = "저장하지 않은 변경이 있습니다. 저장할까요?"
	unsaved_dialog.ok_button_text = "저장"
	unsaved_dialog.cancel_button_text = "취소"
	unsaved_dialog.add_button("저장 안 함", true, "discard")
	unsaved_dialog.confirmed.connect(_on_unsaved_answer.bind(true))
	unsaved_dialog.custom_action.connect(func(_action: StringName) -> void:
		unsaved_dialog.hide()
		_on_unsaved_answer(false))
	unsaved_dialog.canceled.connect(_keep_editing)
	add_child(unsaved_dialog)

func _build_character_column() -> Control:
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = SIDE_WIDTH * ui_scale
	column.add_child(_note("캐릭터"))
	character_list = ItemList.new()
	character_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	character_list.item_selected.connect(_on_character_clicked)
	column.add_child(character_list)
	column.add_child(_button("새 캐릭터", _open_new_dialog))
	column.add_child(_note("자동 검사"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	problem_box = VBoxContainer.new()
	problem_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(problem_box)
	column.add_child(scroll)
	return column

func _build_move_column() -> Control:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var kinds := HBoxContainer.new()
	attack_button = _toggle("기본 공격", _on_kind_pressed.bind(false))
	skill_button = _toggle("스킬", _on_kind_pressed.bind(true))
	kinds.add_child(attack_button)
	kinds.add_child(skill_button)
	column.add_child(kinds)
	var slots := HBoxContainer.new()
	for slot: int in CharacterDef.Slot.values():
		var button := _toggle(CharacterDef.SLOT_NAMES[slot], _on_slot_pressed.bind(slot))
		slot_buttons.append(button)
		slots.add_child(button)
	column.add_child(slots)
	var note_row := HBoxContainer.new()
	move_note = Label.new()
	move_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note_row.add_child(move_note)
	move_action_button = _button("", func() -> void:
		if _move_action.is_valid():
			_move_action.call())
	note_row.add_child(move_action_button)
	column.add_child(note_row)
	preview = MovePreview.new()
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(preview)
	return column

func _build_form_column() -> Control:
	tabs = TabContainer.new()
	tabs.custom_minimum_size.x = FORM_WIDTH * ui_scale
	basic_form = _add_form_tab("기본")
	basic_form.hidden_fields = BASIC_HIDDEN
	movement_form = _add_form_tab("이동")
	derived_label = _note("")
	derived_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	movement_form.get_parent().add_child(derived_label)
	move_form = _add_form_tab("기술")
	kit_form = _add_form_tab("기믹")
	kit_form.only_fields = [&"kit"]
	var kit_note := _note("목록에 없는 기믹은 아래 [AI 요청문 복사]로 AI에게 만들어 달라고 하세요. 만들어지면 여기에 나타나고, 조절할 수치는 슬라이더로 자동 표시됩니다.")
	kit_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	kit_form.get_parent().add_child(kit_note)
	# Scripts written while the editor is open show up the next time the tab opens.
	tabs.tab_changed.connect(func(_tab: int) -> void:
		if current != null:
			kit_form.rebuild())
	return tabs

func _add_form_tab(title: String) -> TuningForm:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	tabs.add_child(scroll)
	var form := TuningForm.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.ui_scale = ui_scale
	form.import_picture = _import_picture
	form.value_changed.connect(func(_resource: Resource, _field: StringName) -> void: _mark_changed())
	form.structure_changed.connect(_mark_changed)
	box.add_child(form)
	return form

func _build_bottom_bar() -> Control:
	var bar := HBoxContainer.new()
	status_label = Label.new()
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.clip_text = true
	bar.add_child(status_label)
	bar.add_child(_button("AI 요청문 복사", _copy_ai_request))
	save_button = _button("저장", save_current)
	bar.add_child(save_button)
	bar.add_child(_button("연습실에서 테스트", open_lab))
	return bar

func _build_new_dialog() -> void:
	new_dialog = ConfirmationDialog.new()
	new_dialog.title = "새 캐릭터"
	new_dialog.ok_button_text = "만들기"
	new_dialog.dialog_hide_on_ok = false
	new_dialog.confirmed.connect(_on_new_confirmed)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(420.0 * ui_scale, 0.0)
	new_id = LineEdit.new()
	new_id.placeholder_text = "영어 소문자 id (예: fire_mage)"
	box.add_child(new_id)
	new_name = LineEdit.new()
	new_name.placeholder_text = "표시 이름 (예: 불의 마법사)"
	box.add_child(new_name)
	box.add_child(_note("복사해서 시작할 캐릭터"))
	new_source = OptionButton.new()
	box.add_child(new_source)
	new_match_label = _note("경기 그림: 없음 (슬롯 색 상자)")
	box.add_child(new_match_label)
	box.add_child(_button("경기 그림 PNG 선택", _pick_new_picture.bind(true)))
	new_lobby_label = _note("대기방 그림: 없음 (경기 그림을 같이 씀)")
	box.add_child(new_lobby_label)
	box.add_child(_button("대기방 그림 PNG 선택", _pick_new_picture.bind(false)))
	new_error = Label.new()
	new_error.add_theme_color_override("font_color", PROBLEM_COLOR)
	new_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(new_error)
	new_dialog.add_child(box)
	add_child(new_dialog)

func _note(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", TuningForm.NOTE_COLOR)
	return label

func _button(text: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(pressed)
	return button

func _toggle(text: String, pressed: Callable) -> Button:
	var button := _button(text, pressed)
	button.toggle_mode = true
	return button

func _on_character_clicked(index: int) -> void:
	if dirty:
		_pending_index = index
		unsaved_dialog.popup_centered()
	else:
		select_character(index)

func _on_unsaved_answer(should_save: bool) -> void:
	if should_save:
		save_current()
	else:
		_reload_current()
	if _pending_index >= 0:
		select_character(_pending_index)
		_pending_index = -1

## Closing the question keeps the edits and goes back to the character being edited.
func _keep_editing() -> void:
	_pending_index = -1
	character_list.select(catalog.characters.find(current))

func _on_kind_pressed(is_skill: bool) -> void:
	selected_skill = is_skill
	_show_selected_move()

func _on_slot_pressed(slot: int) -> void:
	selected_slot = slot as CharacterDef.Slot
	_show_selected_move()

func _show_selected_move() -> void:
	if current != null:
		tabs.current_tab = TAB_MOVE
		show_move()

func _set_dirty(value: bool) -> void:
	dirty = value

func _set_status(text: String) -> void:
	status_label.text = text

func _mark_changed() -> void:
	_set_dirty(true)
	_set_status("저장하지 않은 변경이 있습니다.")
	preview.queue_redraw()
	_refresh_derived()
	_refresh_problems()

func _refresh_derived() -> void:
	var values: MovementSettings = movement_form.target
	var reach := CombatRules.recovery_reach(values)
	var gravity := maxf(1.0, values.gravity)
	derived_label.text = "점프 높이 %dpx · 체공 %.2f초\n2단 점프 복귀 거리 %dpx · 복귀 높이 %dpx" % [values.jump_speed * values.jump_speed / (2.0 * gravity), 2.0 * values.jump_speed / gravity, reach.x, reach.y]

func _refresh_problems() -> void:
	for child in problem_box.get_children():
		problem_box.remove_child(child)
		child.queue_free()
	var problems := CharacterValidator.problems(current)
	if problems.is_empty():
		var fine := Label.new()
		fine.text = "문제 없음"
		fine.add_theme_color_override("font_color", OK_COLOR)
		problem_box.add_child(fine)
	for problem in problems:
		var line := Label.new()
		line.text = problem
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.add_theme_color_override("font_color", PROBLEM_COLOR)
		problem_box.add_child(line)

func save_current() -> void:
	var error := CharacterFiles.save(current)
	if error != OK:
		_set_status("저장하지 못했습니다 (%s)." % error_string(error))
		return
	_loaded_time = FileAccess.get_modified_time(current.resource_path)
	if file_system != null:
		file_system.update_file(current.resource_path)
	_set_dirty(false)
	_set_status("저장했습니다.")

func open_lab() -> void:
	if dirty:
		save_current()
	var file := FileAccess.open(CharacterFiles.LAB_TARGET_FILE, FileAccess.WRITE)
	if file == null:
		_set_status("연습실을 열지 못했습니다.")
		return
	file.store_string(String(current.id))
	file.close()
	if play_lab.is_valid():
		play_lab.call()

func _copy_ai_request() -> void:
	DisplayServer.clipboard_set(CharacterFiles.ai_request(current))
	_set_status("복사했습니다. AI에게 붙여 넣고 원하는 기믹을 적어 주세요.")

func _reload_current() -> void:
	var index := catalog.characters.find(current)
	var reloaded: CharacterDef = ResourceLoader.load(current.resource_path, "", ResourceLoader.CACHE_MODE_REPLACE_DEEP)
	if index < 0 or reloaded == null:
		return
	catalog.characters[index] = reloaded
	select_character(index)

## Copies a PNG into assets/characters as <id>_<name>.png and returns it, imported and ready.
func _import_picture(source_path: String, _owner_resource: Resource, field: StringName) -> Texture2D:
	return _bring_in_png(source_path, "%s_%s" % [current.id, _ascii_stem(source_path, field)])

static func _ascii_stem(source_path: String, fallback: StringName) -> String:
	var stem := RegEx.create_from_string("[^a-z0-9_]").sub(source_path.get_file().get_basename().to_snake_case(), "", true)
	return stem if not stem.is_empty() else String(fallback)

func _bring_in_png(source_path: String, stem: String) -> Texture2D:
	var target := "res://assets/characters/%s.png" % stem
	var error := DirAccess.copy_absolute(source_path, ProjectSettings.globalize_path(target))
	if error != OK:
		_set_status("그림을 복사하지 못했습니다 (%s)." % error_string(error))
		return null
	if file_system != null:
		file_system.update_file(target)
		file_system.reimport_files(PackedStringArray([target]))
	return load(target)

func _open_new_dialog() -> void:
	new_source.clear()
	for entry in catalog.characters:
		new_source.add_item(entry.display_name)
	new_source.select(0)
	new_id.text = ""
	new_name.text = ""
	new_error.text = ""
	_new_match_path = ""
	_new_lobby_path = ""
	new_match_label.text = "경기 그림: 없음 (슬롯 색 상자)"
	new_lobby_label.text = "대기방 그림: 없음 (경기 그림을 같이 씀)"
	new_dialog.popup_centered()

func _pick_new_picture(is_match: bool) -> void:
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.png ; PNG"])
	dialog.use_native_dialog = true
	dialog.file_selected.connect(func(path: String) -> void:
		if is_match:
			_new_match_path = path
			new_match_label.text = "경기 그림: %s" % path.get_file()
		else:
			_new_lobby_path = path
			new_lobby_label.text = "대기방 그림: %s" % path.get_file())
	add_child(dialog)
	dialog.popup_centered_ratio(0.6)

func _on_new_confirmed() -> void:
	var id := new_id.text.strip_edges()
	var display_name := new_name.text.strip_edges()
	var problem := CharacterFiles.id_problem(id, catalog)
	if problem.is_empty() and display_name.is_empty():
		problem = "표시 이름을 적어 주세요."
	if not problem.is_empty():
		new_error.text = problem
		return
	new_dialog.hide()
	create_character(id, display_name, catalog.characters[new_source.selected], _new_match_path, _new_lobby_path)

func create_character(id: String, display_name: String, source: CharacterDef, match_path: String, lobby_path: String) -> void:
	var entry := CharacterFiles.create(id, display_name, source, catalog)
	if entry == null:
		_set_status("캐릭터를 만들지 못했습니다.")
		return
	if not match_path.is_empty():
		entry.match_sprite = _bring_in_png(match_path, "%s_match" % id)
	var lobby_source := lobby_path if not lobby_path.is_empty() else match_path
	if not lobby_source.is_empty():
		_bring_in_png(lobby_source, id)
	CharacterFiles.save(entry)
	if file_system != null:
		file_system.update_file(entry.resource_path)
		file_system.update_file(catalog.resource_path)
	var index := catalog.characters.size() - 1
	character_list.add_item(entry.display_name)
	character_list.select(index)
	select_character(index)
	_set_status("만들었습니다. 기획서는 Docs/gdd/characters/%s.md 입니다." % id)
