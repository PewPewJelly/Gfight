class_name SlantInput
extends Control
## Slanted text field with an n/max counter (Docs/02 §3.9): room name 12, nickname 10.
## Commits on Enter or when focus leaves, never per character.

signal committed(text: String)

const COUNTER_WIDTH: float = 72.0

var line_edit: LineEdit
var max_length: int = 12
var _counter: Label
var _editable: bool = true

func _ready() -> void:
	line_edit = LineEdit.new()
	line_edit.flat = true
	line_edit.max_length = max_length
	line_edit.add_theme_font_size_override("font_size", 28)
	line_edit.add_theme_color_override("font_color", UiStyle.LOBBY_TEXT)
	line_edit.add_theme_color_override("font_uneditable_color", UiStyle.LOBBY_TEXT_DIM)
	line_edit.add_theme_color_override("caret_color", UiStyle.LOBBY_TEXT)
	line_edit.text_changed.connect(func(_text: String) -> void: _update_counter())
	line_edit.text_submitted.connect(func(_text: String) -> void: line_edit.release_focus())
	line_edit.focus_exited.connect(func() -> void: committed.emit(line_edit.text))
	add_child(line_edit)
	_counter = Label.new()
	_counter.add_theme_font_size_override("font_size", 20)
	_counter.add_theme_color_override("font_color", UiStyle.LOBBY_TEXT_DIM)
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_counter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_counter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_counter)
	resized.connect(_layout)
	_layout()

func setup(length: int, text: String, editable: bool) -> void:
	max_length = length
	line_edit.max_length = length
	_editable = editable
	line_edit.editable = editable
	line_edit.mouse_filter = Control.MOUSE_FILTER_STOP if editable else Control.MOUSE_FILTER_IGNORE
	set_text(text)
	queue_redraw()

## Leaves a field the player is typing in untouched.
func set_text(text: String) -> void:
	if line_edit.has_focus():
		return
	line_edit.text = text
	_update_counter()

func _layout() -> void:
	var shift := LobbyGeometry.TAN * size.y / 2.0
	line_edit.position = Vector2(18.0 + shift, 6.0)
	line_edit.size = Vector2(size.x - 36.0 - COUNTER_WIDTH, size.y - 12.0)
	_counter.position = Vector2(size.x - 18.0 - COUNTER_WIDTH + shift, 0.0)
	_counter.size = Vector2(COUNTER_WIDTH, size.y)
	queue_redraw()

func _update_counter() -> void:
	_counter.text = UiStyle.LENGTH_COUNTER % [line_edit.text.length(), max_length]

func _draw() -> void:
	SlantBox.draw_slanted(self, Rect2(Vector2.ZERO, size), Color.WHITE if _editable else UiStyle.LOBBY_READ_ONLY, UiStyle.LOBBY_LINE_DARK, 4.0, 14.0)
