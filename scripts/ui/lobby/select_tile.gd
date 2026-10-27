class_name SelectTile
extends BaseButton
## Character / map tile shared by the selection grids (Docs/02 §3.8).
## Selection shows only as a dashed orange border; no hover effect.

signal picked(pick: StringName)

enum Kind { CHARACTER, MAP }

const RADIUS: float = 16.0
const BORDER: float = 4.0
const PICKED_BORDER: float = 5.0
const DASH: float = 12.0
const GAP: float = 8.0
const CHARACTER_ART: float = 210.0
const CHARACTER_ART_BOTTOM: float = 48.0
const MAP_GRADIENT_RATIO: float = 0.46
const INFO_SIZE: float = 40.0

var kind: Kind = Kind.CHARACTER
var pick: StringName = &""
var item_name: String = ""
var english_name: String = ""
var selected: bool = false:
	set(value):
		selected = value
		queue_redraw()
		if is_instance_valid(_overlay):
			_overlay.queue_redraw()

var _art: TextureRect
var _overlay: Control
var _info: Control

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	pressed.connect(func() -> void: picked.emit(pick))
	resized.connect(_layout)

func configure(tile_kind: Kind, tile_pick: StringName, title: String, subtitle: String = "") -> void:
	kind = tile_kind
	pick = tile_pick
	item_name = title
	english_name = subtitle
	tooltip_text = ""
	if _art == null:
		_art = CharacterArt.new() if kind == Kind.CHARACTER else MapArt.new()
		add_child(_art)
		_overlay = Control.new()
		_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_overlay.draw.connect(_draw_overlay)
		add_child(_overlay)
		_info = Control.new()
		_info.mouse_filter = Control.MOUSE_FILTER_PASS
		_info.draw.connect(_draw_info)
		add_child(_info)
	_art.set("pick", tile_pick)
	_info.tooltip_text = title
	_layout()

func _layout() -> void:
	if _art == null:
		return
	if kind == Kind.CHARACTER:
		_art.position = Vector2((size.x - CHARACTER_ART) / 2.0, size.y - CHARACTER_ART_BOTTOM - CHARACTER_ART)
		_art.size = Vector2(CHARACTER_ART, CHARACTER_ART)
	else:
		_art.position = Vector2.ZERO
		_art.size = size
	_overlay.position = Vector2.ZERO
	_overlay.size = size
	_info.position = Vector2(size.x - 24.0 - INFO_SIZE, 16.0)
	_info.size = Vector2(INFO_SIZE, INFO_SIZE)
	queue_redraw()
	_overlay.queue_redraw()

## Background; with CLIP_CHILDREN_AND_DRAW it is also the mask that rounds the art.
func _draw() -> void:
	draw_colored_polygon(LobbyGeometry.rounded_rect(Rect2(Vector2.ZERO, size), RADIUS), UiStyle.LOBBY_CARD)

func _draw_overlay() -> void:
	var font := UiStyle.bold_font()
	if kind == Kind.MAP:
		var top := size.y * (1.0 - MAP_GRADIENT_RATIO)
		var colors := PackedColorArray([Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.8), Color(0, 0, 0, 0.8)])
		var half := (size.y - top) / 2.0
		_overlay.draw_polygon(PackedVector2Array([Vector2(0, top), Vector2(size.x, top), Vector2(size.x, top + half), Vector2(0, top + half)]),
			PackedColorArray([Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.4), Color(0, 0, 0, 0.4)]))
		_overlay.draw_polygon(PackedVector2Array([Vector2(0, top + half), Vector2(size.x, top + half), Vector2(size.x, size.y), Vector2(0, size.y)]),
			PackedColorArray([Color(0, 0, 0, 0.4), Color(0, 0, 0, 0.4), colors[2], colors[3]]))
		_overlay.draw_string(font, Vector2(32, size.y - 52), item_name, HORIZONTAL_ALIGNMENT_LEFT, size.x - 64, 40,
			UiStyle.LOBBY_PICKED_MAP_TEXT if selected else Color.WHITE)
		_overlay.draw_string(font, Vector2(32, size.y - 18), english_name, HORIZONTAL_ALIGNMENT_LEFT, size.x - 64, 22, Color(1, 1, 1, 0.7))
	else:
		_overlay.draw_string(font, Vector2(32, size.y - 16), item_name, HORIZONTAL_ALIGNMENT_LEFT, size.x - 64, 32,
			UiStyle.LOBBY_PICKED_TEXT if selected else UiStyle.LOBBY_TEXT)
	var outline := LobbyGeometry.rounded_rect(Rect2(Vector2.ONE * PICKED_BORDER / 2.0, size - Vector2.ONE * PICKED_BORDER), RADIUS)
	if selected:
		draw_dashed_outline(_overlay, outline, UiStyle.LOBBY_ORANGE, PICKED_BORDER, DASH, GAP)
	else:
		_overlay.draw_polyline(LobbyGeometry.closed(outline), UiStyle.LOBBY_LINE_DARK, BORDER, true)

func _draw_info() -> void:
	var center := _info.size / 2.0
	_info.draw_circle(center, INFO_SIZE / 2.0, Color(1, 1, 1, 0.9))
	LobbyIcons.draw(_info, LobbyIcons.Kind.INFO, Rect2(center - Vector2(15, 15), Vector2(30, 30)), UiStyle.LOBBY_LINE_DARK)

static func draw_dashed_outline(canvas: CanvasItem, outline: PackedVector2Array, color: Color, width: float, dash: float, gap: float) -> void:
	var points := LobbyGeometry.closed(outline)
	var on := true
	var left := dash
	for index in range(points.size() - 1):
		var from := points[index]
		var to := points[index + 1]
		var length := from.distance_to(to)
		var travelled := 0.0
		while travelled < length:
			var step := minf(left, length - travelled)
			var a := from.lerp(to, travelled / length)
			var b := from.lerp(to, (travelled + step) / length)
			if on:
				canvas.draw_line(a, b, color, width, true)
			travelled += step
			left -= step
			if left <= 0.0:
				on = not on
				left = dash if on else gap
