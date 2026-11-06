class_name CharacterArt
extends TextureRect
## Character picture: res://assets/characters/<pick>.svg, random.svg for `random` or a missing file.

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
	var key := String(id) if not String(id).is_empty() else String(ContentCatalog.RANDOM)
	if not _cache.has(key):
		var path := "res://assets/characters/%s.svg" % key
		for extension in ["png", "webp", "jpg", "svg"]:
			var candidate := "res://assets/characters/%s.%s" % [key, extension]
			if ResourceLoader.exists(candidate):
				path = candidate
				break
		if not ResourceLoader.exists(path):
			path = "res://assets/characters/random.svg"
		_cache[key] = load(path) as Texture2D
	return _cache[key]

## Shared with MapArt: loads <folder>/<id>.svg once, falling back to random.svg.
static func _load_art(pattern: String, id: StringName, cache: Dictionary) -> Texture2D:
	var key := String(id) if not String(id).is_empty() else String(ContentCatalog.RANDOM)
	if not cache.has(key):
		var path := pattern % key
		if not ResourceLoader.exists(path):
			push_warning("Missing art %s" % path)
			path = pattern % ContentCatalog.RANDOM
		cache[key] = load(path) as Texture2D
	return cache[key]
