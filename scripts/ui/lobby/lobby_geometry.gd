class_name LobbyGeometry
extends RefCounted
## Lobby layout constants (Docs/02 §3.1). Coordinates are in the 1910×1070 Stage.

const SKEW_DEG: float = 12.0
const TAN: float = 0.21256                # tan(12°)
const STAGE_SIZE := Vector2(1910, 1070)   # inside the 5px root border
const ROOT_SIZE := Vector2(1920, 1080)
const ROOT_BORDER: float = 5.0
const PANEL_BLEED: float = 16.0
const PANEL_LEFT: float = 840.0           # left x at y = PANEL_TOP
const PANEL_TOP: float = -16.0
const PANEL_WIDTH: float = 840.0
const PANEL_HEIGHT: float = 1102.0        # STAGE.y + 2 * BLEED
const PANEL_PAD: float = 14.0
const PANEL_PAD_Y: float = 26.0           # BLEED - 4 (border) + PAD
const PANEL_INNER_H: float = 1042.0       # STAGE.y - 2 * PAD
const PANEL_BORDER: float = 4.0
const PANEL_RADIUS: float = 22.0
## Content width inside the panel border and padding: 840 - 2 * (4 + 14).
const PANEL_INNER_W: float = 804.0
const CORNER_SEGMENTS: int = 6

static func panel_right_at(y: float) -> float:
	return PANEL_LEFT + PANEL_WIDTH + TAN * (y - PANEL_TOP)

static func slant_x(x: float, y: float, origin_y: float) -> float:
	return x + TAN * (y - origin_y)

## Rounded rectangle outline, each corner approximated with CORNER_SEGMENTS segments.
static func rounded_rect(rect: Rect2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var r := minf(radius, minf(rect.size.x, rect.size.y) / 2.0)
	if r <= 0.0:
		return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	var centers := [Vector2(rect.end.x - r, rect.position.y + r), Vector2(rect.end.x - r, rect.end.y - r),
		Vector2(rect.position.x + r, rect.end.y - r), Vector2(rect.position.x + r, rect.position.y + r)]
	var start_angles := [-PI / 2.0, 0.0, PI / 2.0, PI]
	for corner in range(4):
		for step in range(CORNER_SEGMENTS + 1):
			var angle: float = start_angles[corner] + (PI / 2.0) * step / CORNER_SEGMENTS
			points.append(centers[corner] + Vector2(cos(angle), sin(angle)) * r)
	return points

## Shifts each point right by TAN * (y - origin_y), like CSS skewX(12°) from the top.
static func skewed(points: PackedVector2Array, origin_y: float, tan_value: float = TAN) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in points:
		result.append(Vector2(point.x + tan_value * (point.y - origin_y), point.y))
	return result

static func closed(points: PackedVector2Array) -> PackedVector2Array:
	var result := points.duplicate()
	if not points.is_empty():
		result.append(points[0])
	return result
