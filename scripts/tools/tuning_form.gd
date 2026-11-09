@tool
class_name TuningForm
extends VBoxContainer
## Builds labeled controls for a resource's @export values, so new numbers appear by themselves.
## The range comes from @export_range and the Korean name from the script's LABELS constant:
## LABELS = {"field": ["이름", "설명", ["선택지", ...]], "@Group": "묶음 이름"}. A subclass of
## a script that already has one uses another name ending in LABELS (GDScript forbids reuse).
## Used by the character workshop (editor) and the character lab (running game).

signal value_changed(resource: Resource, field: StringName)
## A nested resource was added, removed, or replaced; the form has rebuilt itself.
signal structure_changed

## Exported types whose value is chosen from the scripts in a folder.
const SCRIPT_FOLDERS := {"ProjectileBehavior": "res://scripts/projectiles", "CharacterKit": "res://scripts/characters"}
const VALUE_WIDTH := 112.0
const PICTURE_SIZE := 56.0
const NOTE_FONT_RATIO := 0.8
const NOTE_COLOR := Color(0.62, 0.66, 0.72)
const CHANGED_COLOR := Color(0.95, 0.72, 0.3)
const GROUP_COLOR := Color(0.55, 0.75, 1.0)

var target: Resource
## Values shown next to each number for comparison (the test fighter's). Optional.
var baseline: Resource
## When not empty, only these fields are shown.
var only_fields: Array[StringName] = []
var hidden_fields: Array[StringName] = []
var read_only: bool = false
## Display scale for fixed widths (the editor's, on high-resolution screens).
var ui_scale: float = 1.0
## Copies a PNG into the project: func(source_path, owner_resource, field) -> Texture2D.
## Left empty where pictures cannot change (the running game).
var import_picture: Callable

## Korean name, help text, and option names for a field.
static func field_words(resource: Resource, field: String) -> Array:
	var words: Variant = _labels_entry(resource, field)
	if words is String:
		return [words, "", []]
	if words is Array:
		var entry: Array = words
		return [entry[0], entry[1] if entry.size() > 1 else "", entry[2] if entry.size() > 2 else []]
	return [field.capitalize(), "", []]

## The scripts offered for a SCRIPT_FOLDERS type.
static func scripts_in(folder: String) -> Array[Script]:
	var found: Array[Script] = []
	if not DirAccess.dir_exists_absolute(folder):
		return found
	for file in DirAccess.get_files_at(folder):
		if file.ends_with(".gd"):
			var script: Script = load(folder.path_join(file))
			if script != null:
				found.append(script)
	return found

static func script_title(script: Script) -> String:
	return str(script.get_script_constant_map().get("DISPLAY_NAME", script.resource_path.get_file().get_basename()))

static func _labels_entry(resource: Resource, key: String) -> Variant:
	var script: Script = resource.get_script()
	while script != null:
		var constants := script.get_script_constant_map()
		for constant_name: String in constants:
			if constant_name.ends_with("LABELS") and constants[constant_name] is Dictionary and constants[constant_name].has(key):
				return constants[constant_name][key]
		script = script.get_base_script()
	return null

static func _new_of_class(type_name: String) -> Resource:
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		if entry["class"] == StringName(type_name):
			return load(entry["path"]).new()
	push_error("Unknown resource class %s" % type_name)
	return null

func show_resource(resource: Resource, reference: Resource = null) -> void:
	target = resource
	baseline = reference
	rebuild()

func rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	if target != null:
		_add_fields(self, target, baseline)

func _add_fields(box: Container, resource: Resource, reference: Resource) -> void:
	var pending_group := ""
	for property in CharacterDef.script_properties(resource):
		var usage := int(property.usage)
		if usage & PROPERTY_USAGE_GROUP:
			pending_group = str(property.name)
			continue
		if not usage & PROPERTY_USAGE_SCRIPT_VARIABLE or not usage & PROPERTY_USAGE_EDITOR or not _is_shown(resource, property.name):
			continue
		if not pending_group.is_empty():
			_add_group(box, resource, pending_group)
			pending_group = ""
		_add_field(box, resource, reference, property)

func _is_shown(resource: Resource, field: StringName) -> bool:
	if resource != target:
		return true
	return not hidden_fields.has(field) and (only_fields.is_empty() or only_fields.has(field))

func _add_group(box: Container, resource: Resource, group: String) -> void:
	var words: Variant = _labels_entry(resource, "@" + group)
	var title := Label.new()
	title.text = str(words) if words != null else group
	title.add_theme_color_override("font_color", GROUP_COLOR)
	box.add_child(title)

func _add_field(box: Container, resource: Resource, reference: Resource, property: Dictionary) -> void:
	var type := int(property.type)
	var hint := int(property.hint)
	if type == TYPE_BOOL:
		_add_check(box, resource, property)
	elif type == TYPE_INT and hint == PROPERTY_HINT_ENUM:
		_add_choice(box, resource, property)
	elif type == TYPE_INT or type == TYPE_FLOAT:
		_add_number(box, resource, reference, property)
	elif type == TYPE_VECTOR2:
		_add_vector(box, resource, property)
	elif type == TYPE_STRING or type == TYPE_STRING_NAME:
		_add_text(box, resource, property)
	elif type == TYPE_ARRAY:
		_add_list(box, resource, property)
	elif type == TYPE_OBJECT and String(property.hint_string) == "Texture2D":
		_add_picture(box, resource, property)
	elif type == TYPE_OBJECT:
		_add_nested(box, resource, reference, property)

## One row: the field's name on the left, room for its control on the right.
func _line(box: Container, resource: Resource, field: String) -> HBoxContainer:
	var words := field_words(resource, field)
	var line := HBoxContainer.new()
	var title := Label.new()
	title.text = words[0]
	title.tooltip_text = words[1]
	title.mouse_filter = Control.MOUSE_FILTER_PASS
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	line.add_child(title)
	box.add_child(line)
	return line

func _store(resource: Resource, field: StringName, value: Variant) -> void:
	resource.set(field, value)
	resource.emit_changed()
	value_changed.emit(resource, field)

func _structure_edited() -> void:
	rebuild()
	structure_changed.emit()

## Parses an @export_range hint; fields without one get a number box and no slider.
static func _limits(property: Dictionary, is_int: bool) -> Dictionary:
	var limits := {"min": -100000.0, "max": 100000.0, "step": 1.0 if is_int else 0.01, "greater": false, "less": false, "suffix": "", "slider": false}
	if int(property.hint) != PROPERTY_HINT_RANGE:
		return limits
	limits.slider = true
	var parts := String(property.hint_string).split(",")
	limits.min = parts[0].to_float()
	limits.max = parts[1].to_float()
	for index in range(2, parts.size()):
		var part := parts[index].strip_edges()
		if part == "or_greater":
			limits.greater = true
		elif part == "or_less":
			limits.less = true
		elif part.begins_with("suffix:"):
			limits.suffix = part.trim_prefix("suffix:")
		elif part.is_valid_float():
			limits.step = part.to_float()
	return limits

func _add_number(box: Container, resource: Resource, reference: Resource, property: Dictionary) -> void:
	var field: StringName = property.name
	var is_int := int(property.type) == TYPE_INT
	var limits := _limits(property, is_int)
	var line := _line(box, resource, field)
	var spin := SpinBox.new()
	spin.min_value = limits.min
	spin.max_value = limits.max
	spin.step = limits.step
	spin.allow_greater = limits.greater
	spin.allow_lesser = limits.less
	spin.suffix = limits.suffix
	spin.custom_minimum_size.x = VALUE_WIDTH * ui_scale
	spin.value = float(resource.get(field))
	spin.editable = not read_only
	spin.set_meta("field", field)
	line.add_child(spin)
	var note := _add_baseline(line, reference, field, float(resource.get(field)))
	if limits.slider:
		var slider := HSlider.new()
		spin.share(slider)
		slider.focus_mode = Control.FOCUS_NONE
		slider.editable = not read_only
		box.add_child(slider)
	spin.value_changed.connect(func(value: float) -> void:
		_store(resource, field, int(value) if is_int else value)
		if note != null:
			_tint_note(note, value, float(reference.get(field))))

func _add_baseline(line: HBoxContainer, reference: Resource, field: StringName, value: float) -> Label:
	if reference == null or reference.get(field) == null:
		return null
	var compared := float(reference.get(field))
	var note := Label.new()
	note.text = "기준 %s" % String.num(compared, 2)
	note.add_theme_font_size_override("font_size", roundi(get_theme_default_font_size() * NOTE_FONT_RATIO))
	_tint_note(note, value, compared)
	line.add_child(note)
	return note

func _tint_note(note: Label, value: float, compared: float) -> void:
	note.add_theme_color_override("font_color", NOTE_COLOR if is_equal_approx(value, compared) else CHANGED_COLOR)

func _add_check(box: Container, resource: Resource, property: Dictionary) -> void:
	var field: StringName = property.name
	var line := _line(box, resource, field)
	var check := CheckBox.new()
	check.button_pressed = resource.get(field)
	check.disabled = read_only
	check.focus_mode = Control.FOCUS_NONE
	check.set_meta("field", field)
	check.toggled.connect(func(pressed: bool) -> void: _store(resource, field, pressed))
	line.add_child(check)

func _add_choice(box: Container, resource: Resource, property: Dictionary) -> void:
	var field: StringName = property.name
	var line := _line(box, resource, field)
	var names: Array = field_words(resource, field)[2]
	var option := OptionButton.new()
	var choices := String(property.hint_string).split(",")
	for index in range(choices.size()):
		var value := index
		if choices[index].contains(":"):
			value = choices[index].get_slice(":", 1).to_int()
		option.add_item(names[index] if index < names.size() else choices[index].get_slice(":", 0), value)
	option.select(option.get_item_index(int(resource.get(field))))
	option.disabled = read_only
	option.focus_mode = Control.FOCUS_NONE
	option.set_meta("field", field)
	option.item_selected.connect(func(index: int) -> void: _store(resource, field, option.get_item_id(index)))
	line.add_child(option)

func _add_vector(box: Container, resource: Resource, property: Dictionary) -> void:
	var field: StringName = property.name
	var line := _line(box, resource, field)
	var value: Vector2 = resource.get(field)
	var x_spin := _vector_part(line, value.x)
	var y_spin := _vector_part(line, value.y)
	x_spin.set_meta("field", field)
	var store := func(_changed: float) -> void: _store(resource, field, Vector2(x_spin.value, y_spin.value))
	x_spin.value_changed.connect(store)
	y_spin.value_changed.connect(store)

func _vector_part(line: HBoxContainer, value: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = -100000.0
	spin.max_value = 100000.0
	spin.step = 0.01
	spin.value = value
	spin.editable = not read_only
	line.add_child(spin)
	return spin

func _add_text(box: Container, resource: Resource, property: Dictionary) -> void:
	var field: StringName = property.name
	var is_name := int(property.type) == TYPE_STRING_NAME
	var line := _line(box, resource, field)
	var input := LineEdit.new()
	input.text = str(resource.get(field))
	input.editable = not read_only
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.set_meta("field", field)
	input.text_changed.connect(func(text: String) -> void: _store(resource, field, StringName(text) if is_name else text))
	line.add_child(input)

func _add_picture(box: Container, resource: Resource, property: Dictionary) -> void:
	var field: StringName = property.name
	var line := _line(box, resource, field)
	var shown := TextureRect.new()
	shown.custom_minimum_size = Vector2.ONE * PICTURE_SIZE * ui_scale
	shown.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shown.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	shown.texture = resource.get(field)
	line.add_child(shown)
	if read_only or not import_picture.is_valid():
		return
	var pick := _small_button("PNG 선택", _pick_picture.bind(resource, field))
	pick.set_meta("field", field)
	line.add_child(pick)
	if shown.texture != null:
		line.add_child(_small_button("지우기", func() -> void:
			_store(resource, field, null)
			_structure_edited.call_deferred()))

func _small_button(text: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(pressed)
	return button

func _pick_picture(resource: Resource, field: StringName) -> void:
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.png ; PNG"])
	dialog.use_native_dialog = true
	dialog.file_selected.connect(func(path: String) -> void:
		var picture: Variant = import_picture.call(path, resource, field)
		if picture != null:
			_store(resource, field, picture)
			_structure_edited.call_deferred())
	add_child(dialog)
	dialog.popup_centered_ratio(0.6)

func _add_nested(box: Container, resource: Resource, reference: Resource, property: Dictionary) -> void:
	var field: StringName = property.name
	var type_name := String(property.hint_string)
	var value: Resource = resource.get(field)
	if SCRIPT_FOLDERS.has(type_name):
		_add_script_choice(box, resource, property, SCRIPT_FOLDERS[type_name])
	elif value == null:
		if not read_only:
			var line := _line(box, resource, field)
			var make := _small_button("만들기", func() -> void:
				_store(resource, field, _new_of_class(type_name))
				_structure_edited.call_deferred())
			make.set_meta("field", field)
			line.add_child(make)
		return
	else:
		_line(box, resource, field)
	if value != null:
		var nested_reference: Resource = reference.get(field) if reference != null else null
		_add_nested_box(box, value, nested_reference)

func _add_nested_box(box: Container, resource: Resource, reference: Resource) -> VBoxContainer:
	var panel := PanelContainer.new()
	var inner := VBoxContainer.new()
	panel.add_child(inner)
	box.add_child(panel)
	_add_fields(inner, resource, reference)
	return inner

func _add_script_choice(box: Container, resource: Resource, property: Dictionary, folder: String) -> void:
	var field: StringName = property.name
	var line := _line(box, resource, field)
	var option := OptionButton.new()
	option.add_item("없음", 0)
	var scripts := scripts_in(folder)
	var current: Resource = resource.get(field)
	for index in range(scripts.size()):
		option.add_item(script_title(scripts[index]), index + 1)
		if current != null and current.get_script() == scripts[index]:
			option.select(index + 1)
	option.disabled = read_only
	option.focus_mode = Control.FOCUS_NONE
	option.set_meta("field", field)
	option.item_selected.connect(func(index: int) -> void:
		_store(resource, field, null if index == 0 else scripts[index - 1].new())
		_structure_edited.call_deferred())
	line.add_child(option)

func _add_list(box: Container, resource: Resource, property: Dictionary) -> void:
	var field: StringName = property.name
	var type_name := String(property.hint_string).get_slice(":", 1)
	var items: Array = resource.get(field)
	var line := _line(box, resource, field)
	if not read_only:
		var add := _small_button("추가", func() -> void:
			items.append(_new_of_class(type_name))
			_store(resource, field, items)
			_structure_edited.call_deferred())
		add.set_meta("field", field)
		line.add_child(add)
	for index in range(items.size()):
		var inner := _add_nested_box(box, items[index], null)
		if not read_only:
			inner.add_child(_small_button("삭제", func() -> void:
				items.remove_at(index)
				_store(resource, field, items)
				_structure_edited.call_deferred()))
