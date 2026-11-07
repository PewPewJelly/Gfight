class_name SlantTab
extends BaseButton
## Lobby tab (Docs/02 §3.10): 128×56, slanted, radius 12, border 4, 24px bold.

const PRESS_OFFSET: float = 3.0
const SHADOW: float = 4.0
const FONT_SIZE: int = 24

@export var text: String = "":
	set(value):
		text = value
		queue_redraw()
@export var active: bool = false:
	set(value):
		active = value
		queue_redraw()

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)

func _draw() -> void:
	var held := get_draw_mode() in [BaseButton.DRAW_PRESSED, BaseButton.DRAW_HOVER_PRESSED]
	var face := Rect2(Vector2(0, PRESS_OFFSET if held else 0.0), size - Vector2(0, SHADOW))
	var shadow_fill := UiStyle.LOBBY_GOLD_SHADOW if active else UiStyle.LOBBY_LINE
	SlantBox.draw_slanted(self, Rect2(Vector2(0, SHADOW), size - Vector2(0, SHADOW)), shadow_fill, Color.TRANSPARENT, 0.0, 12.0)
	SlantBox.draw_slanted(self, face, UiStyle.LOBBY_GOLD_BG if active else UiStyle.LOBBY_TAB_IDLE,
		UiStyle.LOBBY_GOLD if active else UiStyle.LOBBY_LINE, 4.0, 12.0)
	var font := UiStyle.bold_font()
	var baseline := face.position.y + (face.size.y + font.get_ascent(FONT_SIZE) - font.get_descent(FONT_SIZE)) / 2.0
	var shift := LobbyGeometry.TAN * face.size.y / 2.0
	draw_string(font, Vector2(face.position.x + shift, baseline), text, HORIZONTAL_ALIGNMENT_CENTER, face.size.x, FONT_SIZE, UiStyle.LOBBY_TEXT)
