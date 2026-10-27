class_name Chip
extends PanelContainer
## Room tag (Docs/02 §3.3): 44px pill, #4E4E4E, 20px bold white; the label part is 55% white.

var _prefix: Label
var _value: Label

func _ready() -> void:
	var style := UiStyle.box(UiStyle.LOBBY_CHIP, Color.TRANSPARENT, 0, 22)
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	style.content_margin_left = 18
	style.content_margin_right = 18
	add_theme_stylebox_override("panel", style)
	custom_minimum_size.y = 44
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	add_child(row)
	_prefix = _label(Color(1, 1, 1, 0.55))
	row.add_child(_prefix)
	_value = _label(Color.WHITE)
	row.add_child(_value)

func set_parts(prefix: String, value: String) -> void:
	_prefix.text = prefix
	_value.text = value

func _label(color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", UiStyle.bold_font())
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label
