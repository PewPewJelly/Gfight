extends SceneTree
## The character tools: the automatic slider form, character files, the workshop panel, and the lab.
## Everything is written under user:// so the project stays untouched.

const TEST_ROOT := "user://character_tool_test"

class TunedKit extends CharacterKit:
	const LABELS := {"charge_seconds": ["충전 시간", "가득 찰 때까지"]}

	@export_range(0.0, 10.0, 0.5, "suffix:초") var charge_seconds: float = 3.0

var failures: int = 0
var base: CharacterDef

func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error(description)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	_remove_tree(TEST_ROOT)
	CharacterFiles.characters_folder = TEST_ROOT + "/characters"
	CharacterFiles.design_folder = TEST_ROOT + "/design"
	base = load("res://resources/characters/test_fighter.tres")
	await test_form_controls()
	await test_form_nested()
	test_kit_values_appear()
	test_copy_is_independent()
	test_create_and_save()
	await test_panel()
	await test_lab()
	_remove_tree(TEST_ROOT)
	print("Character tool checks complete: %d failures" % failures)
	quit(1 if failures > 0 else 0)

func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for folder in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(folder))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)

func control(form: Node, field: StringName) -> Node:
	for child in form.find_children("*", "Control", true, false):
		if child.has_meta("field") and child.get_meta("field") == field:
			return child
	return null

func text_of(form: Node) -> String:
	var parts := PackedStringArray()
	for child in form.find_children("*", "Label", true, false):
		parts.append((child as Label).text)
	return " ".join(parts)

func new_form(resource: Resource, reference: Resource = null) -> TuningForm:
	var form := TuningForm.new()
	root.add_child(form)
	form.show_resource(resource, reference)
	return form

func pick(option: OptionButton, index: int) -> void:
	option.select(index)
	option.item_selected.emit(index)

func test_form_controls() -> void:
	var move := SkillData.new()
	var reference := AttackData.new()
	reference.damage = 7.0
	var form := new_form(move, reference)
	var words := text_of(form)
	check(words.contains("피해") and words.contains("선딜") and words.contains("타이밍") and words.contains("재사용 대기"), "Fields and groups show their Korean names (%s)" % words)
	check(words.contains("기준 7"), "A number shows its comparison value")
	var edits: Array[StringName] = []
	form.value_changed.connect(func(_resource: Resource, field: StringName) -> void: edits.append(field))
	var damage: SpinBox = control(form, &"damage")
	damage.value = 33.0
	check(is_equal_approx(move.damage, 33.0) and edits.has(&"damage"), "A number box writes the value and reports it")
	var launch: SpinBox = control(form, &"base_launch_speed")
	check(is_equal_approx(launch.value, 420.0) and is_equal_approx(launch.max_value, 1200.0), "A field shows its stored value and its own range")
	launch.value = 1500.0
	check(is_equal_approx(move.base_launch_speed, 1500.0), "A field marked or_greater accepts values past the slider")
	check(damage.suffix.is_empty() and (control(form, &"percent_increase") as SpinBox).suffix == "%", "Units come from @export_range")
	var startup: SpinBox = control(form, &"startup_frames")
	startup.value = 4.0
	check(move.startup_frames == 4 and typeof(move.get(&"startup_frames")) == TYPE_INT, "Whole-number fields stay whole numbers")
	var lock: OptionButton = control(form, &"move_lock")
	check(lock.get_item_text(1) == "제자리 고정", "Choices use their Korean names")
	pick(lock, 1)
	check(move.move_lock == AttackData.MoveLock.ROOTED, "A choice writes the value")
	var reflect: CheckBox = control(form, &"reflects_projectiles")
	reflect.button_pressed = true
	check(move.reflects_projectiles, "A check box writes the value")
	var direction: SpinBox = control(form, &"launch_direction")
	direction.value = 0.5
	check(is_equal_approx(move.launch_direction.x, 0.5), "A vector box writes the value")
	var locked := new_form(move)
	locked.read_only = true
	locked.rebuild()
	check(not (control(locked, &"damage") as SpinBox).editable and (control(locked, &"move_lock") as OptionButton).disabled and control(locked, &"spawns") == null, "A read-only form cannot change anything")
	form.queue_free()
	locked.queue_free()
	await process_frame

func test_form_nested() -> void:
	var move := AttackData.new()
	var form := new_form(move)
	var add: Button = control(form, &"spawns")
	add.pressed.emit()
	await process_frame
	check(move.spawns.size() == 1 and move.spawns[0] is ProjectileSpawn, "A list can add an item of its element type")
	var make: Button = control(form, &"projectile")
	make.pressed.emit()
	await process_frame
	check(move.spawns[0].projectile is ProjectileData, "An empty resource field can create its value")
	check(control(form, &"speed") != null and text_of(form).contains("판정 크기"), "Nested resources show their fields")
	var choice: OptionButton = control(form, &"behavior")
	var homing_index := -1
	for index in range(choice.item_count):
		if choice.get_item_text(index) == "유도":
			homing_index = index
	check(homing_index > 0 and choice.get_item_text(0) == "없음", "Behaviors are listed from scripts/projectiles")
	pick(choice, homing_index)
	await process_frame
	check(move.spawns[0].projectile.behavior is HomingShot, "Choosing a behavior creates it")
	check(control(form, &"turn_rate") != null, "A chosen behavior's numbers appear by themselves")
	var picked: OptionButton = control(form, &"behavior")
	check(picked.selected == homing_index, "The form shows the chosen behavior after rebuilding")
	form.queue_free()
	await process_frame

func test_kit_values_appear() -> void:
	var form := new_form(TunedKit.new())
	check(text_of(form).contains("충전 시간"), "A kit's LABELS name its numbers")
	check((control(form, &"charge_seconds") as SpinBox).suffix == "초", "A kit's @export_range sets the slider")
	form.queue_free()

func test_copy_is_independent() -> void:
	var copy: CharacterDef = CharacterFiles.copy_of(base)
	check(copy != base and copy.side_attack != base.side_attack and copy.movement != base.movement, "A copy has its own moves and movement")
	check(copy.side_attack == copy.up_attack, "Slots that shared a move still share one in the copy")
	copy.side_attack.damage = 99.0
	copy.movement.speed = 1.0
	check(base.side_attack.damage != 99.0 and base.movement.speed != 1.0, "Editing a copy leaves the original alone")
	var move := AttackData.new()
	var spawn := ProjectileSpawn.new()
	spawn.projectile = ProjectileData.new()
	move.spawns.append(spawn)
	var moved: AttackData = CharacterFiles.copy_of(move)
	check(moved.spawns[0] != spawn and moved.spawns[0].projectile != spawn.projectile, "Copies reach into typed lists")

func test_catalog() -> ContentCatalog:
	var catalog := ContentCatalog.new()
	catalog.characters.append(base)
	return catalog

func test_create_and_save() -> void:
	var catalog := test_catalog()
	check(not CharacterFiles.id_problem("Bad Id", catalog).is_empty(), "A bad id is refused")
	check(not CharacterFiles.id_problem("random", catalog).is_empty(), "The reserved id is refused")
	check(not CharacterFiles.id_problem("test_fighter", catalog).is_empty(), "A duplicate id is refused")
	check(CharacterFiles.id_problem("fire_mage", catalog).is_empty(), "A good id is accepted")
	var entry := CharacterFiles.create("fire_mage", "불의 마법사", base, catalog)
	check(entry != null and catalog.character(&"fire_mage") == entry, "A new character joins the catalog")
	check(not CharacterFiles.id_problem("fire_mage", catalog).is_empty(), "A used id is refused")
	var document := FileAccess.get_file_as_string(CharacterFiles.design_folder + "/fire_mage.md")
	check(document.contains("# 캐릭터 기획서: 불의 마법사") and document.contains("`fire_mage`"), "A design document is written from the template")
	entry.side_attack.damage = 21.0
	entry.movement.speed = 300.0
	check(CharacterFiles.save(entry) == OK, "A character can be saved")
	var from_disk: CharacterDef = ResourceLoader.load(entry.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	check(from_disk.side_attack.damage == 21.0 and from_disk.movement.speed == 300.0, "Saved values come back from the file")
	check(from_disk.side_attack == from_disk.up_attack, "Shared slots stay shared in the file")
	check(CharacterFiles.save(base) == ERR_UNAUTHORIZED, "The baseline character cannot be overwritten")
	var request := CharacterFiles.ai_request(entry)
	check(request.contains("fire_mage") and request.contains("kit-rules.md") and request.contains("@export_range"), "The AI request names the character and the rules")

func test_panel() -> void:
	var panel := WorkshopPanel.new()
	root.add_child(panel)
	await process_frame
	check(panel.current == base and panel.save_button.disabled, "The panel opens on the baseline and will not save it")
	check(not (control(panel.basic_form, &"display_name") as LineEdit).editable, "The baseline's fields are locked")
	var catalog := test_catalog()
	panel.catalog = catalog
	panel.create_character("panel_probe", "패널 시험", base, "", "")
	var entry := panel.current
	check(entry != null and entry.id == &"panel_probe" and not panel.save_button.disabled, "The panel creates and opens a character")
	check(not panel.dirty, "A new character starts with nothing unsaved")
	var problems := " ".join(CharacterValidator.problems(entry))
	check(problems.contains("그림"), "Automatic checks report the missing picture")
	(control(panel.move_form, &"reach") as SpinBox).value = 140.0
	check(panel.dirty and entry.side_attack.reach == 140.0 and panel.status_label.text.contains("저장"), "Editing marks the character unsaved")
	check(panel.preview.move == entry.side_attack, "The preview follows the selected move")
	check(panel.move_note.text.contains("위·중립"), "The panel says which slots share the move (%s)" % panel.move_note.text)
	panel.move_action_button.pressed.emit()
	check(entry.side_attack != entry.up_attack and entry.side_attack.reach == 140.0, "A shared move can be split into its own slot")
	panel.slot_buttons[CharacterDef.Slot.AIR_UP].pressed.emit()
	panel.skill_button.pressed.emit()
	check(panel.move_note.text.contains("땅의 같은") or panel.move_note.text.contains("비어"), "Empty slots are explained")
	panel.selected_slot = CharacterDef.Slot.SIDE
	panel.show_move()
	check(panel.move_action_button.text == "기술 만들기", "An empty skill slot offers to create a skill")
	panel.move_action_button.pressed.emit()
	check(entry.side_skill is SkillData, "A skill can be created in an empty slot")
	check(panel.move_action_button.text == "이 칸 비우기", "A skill can be removed")
	panel.move_action_button.pressed.emit()
	check(entry.side_skill == null, "A skill slot can be emptied")
	panel.save_current()
	check(not panel.dirty, "Saving clears the unsaved mark")
	var from_disk: CharacterDef = ResourceLoader.load(entry.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	check(from_disk.side_attack.reach == 140.0 and from_disk.side_attack != from_disk.up_attack, "The panel saves to the file")
	var reach_before := entry.side_attack.reach
	panel.selected_skill = false
	panel.show_move()
	(control(panel.move_form, &"reach") as SpinBox).value = 200.0
	panel._on_character_clicked(0)
	check(panel.dirty and panel._pending_index == 0, "Switching characters with unsaved changes asks first")
	panel.unsaved_dialog.canceled.emit()
	check(panel.dirty and panel.current == entry and entry.side_attack.reach == 200.0 and panel._pending_index == -1, "Closing the question keeps the edits")
	panel._on_character_clicked(0)
	panel.unsaved_dialog.custom_action.emit(&"discard")
	check(panel.current == base and not panel.dirty, "Choosing not to save moves on")
	var discarded: CharacterDef = panel.catalog.character(&"panel_probe")
	check(discarded.side_attack.reach == reach_before, "Choosing not to save goes back to the saved values")
	panel.queue_free()
	await process_frame

func test_lab() -> void:
	var catalog := test_catalog()
	var entry := CharacterFiles.create("lab_probe", "연습 시험", base, catalog)
	var lab: CharacterLab = load(CharacterFiles.LAB_SCENE).instantiate()
	lab.catalog = catalog
	lab.requested_id = &"lab_probe"
	root.add_child(lab)
	for _frame in range(3):
		await physics_frame
	check(lab.player.character == entry and lab.dummy.is_dummy, "The lab opens the requested character with a dummy")
	check(lab.player.stocks == CharacterLab.LAB_STOCKS, "The lab does not run out of stocks")
	check(lab.player.start_move(entry.side_attack), "A move can run in the lab")
	await physics_frame
	await physics_frame
	check(lab.shown_move == entry.side_attack and lab.move_title.text.contains("방금 쓴 기술"), "The lab shows the numbers of the move just used")
	(control(lab.move_form, &"reach") as SpinBox).value = 150.0
	check(entry.side_attack.reach == 150.0 and lab.dirty, "Lab sliders take effect immediately")
	(control(lab.movement_form, &"speed") as SpinBox).value = 330.0
	check(lab.player.movement.speed == 330.0, "Movement sliders take effect immediately")
	(control(lab.character_form, &"body_size") as SpinBox).value = 60.0
	check(is_equal_approx(lab.player.half_size.x, 30.0) and is_equal_approx(lab.player.body_shape.size.x, 60.0), "Body size applies to the running fighter")
	lab.cycle_speed()
	check(is_equal_approx(Engine.time_scale, 0.5), "Slow motion changes the game speed")
	lab.dummy_percent.value = 120.0
	check(lab.dummy.percent == 120.0, "The dummy's percent can be set")
	lab.reset_positions()
	check(lab.dummy.percent == 120.0 and lab.player.position.x == CharacterLab.PLAYER_START_X, "Resetting keeps the chosen dummy percent")
	lab.save_character()
	var from_disk: CharacterDef = ResourceLoader.load(entry.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	check(from_disk.side_attack.reach == 150.0 and from_disk.movement.speed == 330.0 and not lab.dirty, "The lab saves only when asked")
	(control(lab.movement_form, &"speed") as SpinBox).value = 110.0
	check(lab.dirty, "A change after saving is unsaved again")
	var on_disk: CharacterDef = ResourceLoader.load(entry.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	check(on_disk.movement.speed == 330.0, "Sliders do not write to the file before saving")
	lab.revert_character()
	check(lab.character.movement.speed == 330.0 and lab.player.movement.speed == 330.0 and not lab.dirty, "Reverting returns to the saved values")
	var saved_on_baseline := CharacterFiles.save(base)
	check(saved_on_baseline == ERR_UNAUTHORIZED, "The lab cannot overwrite the baseline")
	lab.queue_free()
	await process_frame
	check(is_equal_approx(Engine.time_scale, 1.0), "Leaving the lab restores the game speed")
