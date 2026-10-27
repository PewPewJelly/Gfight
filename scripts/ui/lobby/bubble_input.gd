class_name BubbleInput
extends Control
## Chat input bubble (Docs/02 §3.6): 420×66, LineEdit max 40, n/40 counter at the right.

const SIZE := Vector2(420, 66)
const COUNTER_WIDTH: float = 70.0

var line_edit: LineEdit
var _counter: Label

func _ready() -> void:
	size = SIZE
	custom_minimum_size = SIZE
	line_edit = LineEdit.new()
	line_edit.max_length = Session.CHAT_MAX_LENGTH
	line_edit.flat = true
	line_edit.add_theme_font_size_override("font_size", 24)
	line_edit.add_theme_color_override("font_color", UiStyle.LOBBY_TEXT)
	line_edit.add_theme_color_override("caret_color", UiStyle.LOBBY_TEXT)
	line_edit.position = Vector2(20, 6)
	line_edit.size = Vector2(SIZE.x - 40 - COUNTER_WIDTH, SIZE.y - 12)
	line_edit.text_changed.connect(func(_text: String) -> void: _update_counter())
	add_child(line_edit)
	_counter = Label.new()
	_counter.add_theme_font_size_override("font_size", 20)
	_counter.add_theme_color_override("font_color", UiStyle.LOBBY_TEXT_DIM)
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_counter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_counter.position = Vector2(SIZE.x - 20 - COUNTER_WIDTH, 0)
	_counter.size = Vector2(COUNTER_WIDTH, SIZE.y)
	add_child(_counter)
	_update_counter()

func clear_and_focus() -> void:
	line_edit.text = ""
	_update_counter()
	line_edit.grab_focus()

func _update_counter() -> void:
	_counter.text = UiStyle.LENGTH_COUNTER % [line_edit.text.length(), Session.CHAT_MAX_LENGTH]

func _draw() -> void:
	BubbleView.draw_bubble(self, Rect2(Vector2.ZERO, SIZE))
