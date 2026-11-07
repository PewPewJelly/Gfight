class_name RoundButton
extends BaseButton
## Round lobby button with a hard shadow and an icon (Docs/02 §3.3). While held, the face
## moves 3px down onto its shadow (the lobby's only motion).

const PRESS_OFFSET: float = 3.0

@export var fill: Color = Color.WHITE:
	set(value):
		fill = value
		queue_redraw()
@export var border_color: Color = UiStyle.LOBBY_LINE:
	set(value):
		border_color = value
		queue_redraw()
@export var shadow_color: Color = UiStyle.LOBBY_LINE:
	set(value):
		shadow_color = value
		queue_redraw()
@export var icon: LobbyIcons.Kind = LobbyIcons.Kind.X:
	set(value):
		icon = value
		queue_redraw()
@export var icon_size: float = 40.0:
	set(value):
		icon_size = value
		queue_redraw()
@export var icon_color: Color = UiStyle.LOBBY_LINE_DARK:
	set(value):
		icon_color = value
		queue_redraw()
@export var border_width: float = 5.0
@export var shadow_offset: float = 5.0

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)
	resized.connect(queue_redraw)

func _has_point(point: Vector2) -> bool:
	return point.distance_to(size / 2.0) <= minf(size.x, size.y) / 2.0

func _draw() -> void:
	var radius := minf(size.x, size.y) / 2.0 - border_width / 2.0
	var center := size / 2.0
	var held := get_draw_mode() in [BaseButton.DRAW_PRESSED, BaseButton.DRAW_HOVER_PRESSED]
	var face := center + Vector2(0, PRESS_OFFSET if held else 0.0)
	if shadow_offset > 0.0:
		draw_circle(center + Vector2(0, shadow_offset), radius + border_width / 2.0, shadow_color)
	draw_circle(face, radius, fill)
	draw_arc(face, radius, 0.0, TAU, 48, border_color, border_width, true)
	LobbyIcons.draw(self, icon, Rect2(face - Vector2(icon_size, icon_size) / 2.0, Vector2(icon_size, icon_size)), icon_color)
