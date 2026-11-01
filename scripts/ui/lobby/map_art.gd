class_name MapArt
extends TextureRect
## Map picture: res://assets/maps/<pick>.svg (640×360 ratio), random.svg for `random`.

static var _cache: Dictionary = {}

@export var pick: StringName = &"":
	set(value):
		pick = value
		texture = CharacterArt._load_art("res://assets/maps/%s.svg", value, _cache)

func _init() -> void:
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	mouse_filter = Control.MOUSE_FILTER_IGNORE
