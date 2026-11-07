class_name BubbleView
extends Control
## Speech bubble (Docs/02 §3.6): one line, max 460px wide, 24px, white, 4px border, tail below.

const MAX_WIDTH: float = 460.0
const FONT_SIZE: int = 24
const PAD_X: float = 22.0
const HEIGHT: float = 56.0
const RADIUS: float = 18.0
const BORDER: float = 4.0
const TAIL_WIDTH: float = 24.0
const TAIL_HEIGHT: float = 16.0

var _label: Label
var _anchor: Vector2 = Vector2.ZERO

## Built in _init so show_text works before the bubble enters the tree (PlayerList cards).
func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_label.add_theme_color_override("font_color", UiStyle.LOBBY_TEXT)
	_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	visible = false

## Places the tail tip at `anchor` (in the parent's coordinates) and shows `text`.
func show_text(text: String, anchor: Vector2) -> void:
	_anchor = anchor
	visible = not text.is_empty()
	if not visible:
		return
	var text_width := ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var width := minf(MAX_WIDTH, text_width + PAD_X * 2.0)
	size = Vector2(width, HEIGHT + TAIL_HEIGHT)
	position = anchor - Vector2(width / 2.0, HEIGHT + TAIL_HEIGHT)
	_label.text = text
	_label.position = Vector2(PAD_X, 0)
	_label.size = Vector2(width - PAD_X * 2.0, HEIGHT)
	queue_redraw()

func _draw() -> void:
	draw_bubble(self, Rect2(Vector2.ZERO, Vector2(size.x, HEIGHT)))

## Shared with BubbleInput.
static func draw_bubble(canvas: CanvasItem, body: Rect2) -> void:
	var outline := LobbyGeometry.rounded_rect(body, RADIUS)
	canvas.draw_colored_polygon(outline, Color.WHITE)
	canvas.draw_polyline(LobbyGeometry.closed(outline), UiStyle.LOBBY_LINE, BORDER, true)
	var mid := body.position.x + body.size.x / 2.0
	var tail := PackedVector2Array([Vector2(mid - TAIL_WIDTH / 2.0, body.end.y - BORDER / 2.0), Vector2(mid + TAIL_WIDTH / 2.0, body.end.y - BORDER / 2.0), Vector2(mid, body.end.y + TAIL_HEIGHT)])
	canvas.draw_colored_polygon(tail, Color.WHITE)
	canvas.draw_line(tail[1], tail[2], UiStyle.LOBBY_LINE, BORDER, true)
	canvas.draw_line(tail[2], tail[0], UiStyle.LOBBY_LINE, BORDER, true)
