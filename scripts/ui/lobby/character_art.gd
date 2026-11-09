class_name CharacterArt
extends TextureRect
## Character picture: res://assets/characters/<pick>.png or .svg, random.svg for `random` or a missing file.

static var _cache: Dictionary = {}

@export var pick: StringName = &"":
	set(value):
		pick = value
		texture = art_texture(value)

func _init() -> void:
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mouse_filter = Control.MOUSE_FILTER_IGNORE

static func art_texture(id: StringName) -> Texture2D:
	return _load_art("res://assets/characters/%s.svg", id, _cache)

## Whether the character has its own picture instead of the random.svg stand-in.
static func has_art(id: StringName) -> bool:
	var stem := "res://assets/characters/%s" % id
	return ResourceLoader.exists(stem + ".png") or ResourceLoader.exists(stem + ".svg")

## Shared with MapArt: loads <folder>/<id>.png or .svg once, falling back to random.svg.
static func _load_art(pattern: String, id: StringName, cache: Dictionary) -> Texture2D:
	var key := String(id) if not String(id).is_empty() else String(ContentCatalog.RANDOM)
	if not cache.has(key):
		var path := pattern % key
		var png := path.get_basename() + ".png"
		if ResourceLoader.exists(png):
			path = png
		elif not ResourceLoader.exists(path):
			push_warning("Missing art %s" % path)
			path = pattern % ContentCatalog.RANDOM
		cache[key] = load(path) as Texture2D
	return cache[key]
