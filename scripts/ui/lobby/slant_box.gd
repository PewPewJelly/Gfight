class_name SlantBox
extends Control
## Slanted rounded rectangle (Docs/02 §3.3). Children are laid out and drawn upright.

@export var fill: Color = UiStyle.LOBBY_CARD:
	set(value):
		fill = value
		queue_redraw()
@export var border_color: Color = UiStyle.LOBBY_LINE:
	set(value):
		border_color = value
		queue_redraw()
@export var border_width: float = 4.0:
	set(value):
		border_width = value
		queue_redraw()
@export var corner_radius: float = 16.0:
	set(value):
		corner_radius = value
		queue_redraw()
## Hard shadow drawn this many px below the shape in shadow_color.
@export var shadow_offset: float = 0.0:
	set(value):
		shadow_offset = value
		queue_redraw()
@export var shadow_color: Color = UiStyle.LOBBY_LINE:
	set(value):
		shadow_color = value
		queue_redraw()
@export var skew_deg: float = LobbyGeometry.SKEW_DEG:
	set(value):
		skew_deg = value
		queue_redraw()

func _ready() -> void:
	resized.connect(queue_redraw)

func _draw() -> void:
	draw_slanted(self, Rect2(Vector2.ZERO, size), fill, border_color, border_width, corner_radius, shadow_offset, shadow_color, tan(deg_to_rad(skew_deg)))

## Shared by every slanted shape (tabs, rows, inputs): shadow, fill, then border.
static func draw_slanted(canvas: CanvasItem, rect: Rect2, fill_color: Color, line_color: Color, line_width: float,
		radius: float, shadow: float = 0.0, shadow_fill: Color = UiStyle.LOBBY_LINE, tan_value: float = LobbyGeometry.TAN) -> void:
	var shape := LobbyGeometry.skewed(LobbyGeometry.rounded_rect(rect, radius), rect.position.y, tan_value)
	if shadow > 0.0:
		var moved := PackedVector2Array()
		for point in shape:
			moved.append(point + Vector2(0, shadow))
		canvas.draw_colored_polygon(moved, shadow_fill)
	if fill_color.a > 0.0:
		canvas.draw_colored_polygon(shape, fill_color)
	if line_width > 0.0 and line_color.a > 0.0:
		canvas.draw_polyline(LobbyGeometry.closed(shape), line_color, line_width, true)
