class_name LobbyIcons
extends RefCounted
## Lobby icons: white SVGs in res://assets/icons/ (Docs/02 §3.3), tinted when drawn.

enum Kind { X, O, V, STAR, BACK, INFO, DOTS, MUTE, PLAY, LOCK, COPY }

static var _textures: Dictionary = {}

static func texture(kind: Kind) -> Texture2D:
	if not _textures.has(kind):
		var path := "res://assets/icons/%s.svg" % String(Kind.keys()[kind]).to_lower()
		var loaded := load(path) as Texture2D
		if loaded == null:
			push_error("Missing icon %s" % path)
		_textures[kind] = loaded
	return _textures[kind]

static func draw(canvas: CanvasItem, kind: Kind, rect: Rect2, color: Color) -> void:
	var icon := texture(kind)
	if icon != null:
		canvas.draw_texture_rect(icon, rect, false, color)
