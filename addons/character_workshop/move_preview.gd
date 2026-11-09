@tool
class_name MovePreview
extends Control
## Draws a character at game scale with the selected move's hit area, launch direction,
## projectile launch points, and frame timeline.

## Smallest area shown around the body, so small changes keep the same scale.
const MIN_VIEW := Rect2(-170.0, -150.0, 400.0, 230.0)
const VIEW_MARGIN := 24.0
const BAR_HEIGHT := 14.0
const ARROW_LENGTH := 70.0
const BACKGROUND := Color("101927")
const FLOOR_COLOR := Color("637890")
const BODY_COLOR := Color(0.45, 0.7, 1.0)
const HIT_COLOR := Color(0.89, 0.29, 0.29)
const ARROW_COLOR := Color(0.85, 0.35, 0.19)
const SHOT_COLOR := Color(0.95, 0.72, 0.3)
const STARTUP_COLOR := Color(0.94, 0.62, 0.15)
const ACTIVE_COLOR := Color(0.89, 0.29, 0.29)
const RECOVERY_COLOR := Color(0.52, 0.72, 0.92)

var character: CharacterDef
var move: AttackData

func _init() -> void:
	clip_contents = true

func show_move(new_character: CharacterDef, new_move: AttackData) -> void:
	character = new_character
	move = new_move
	queue_redraw()

func _draw() -> void:
	var font_size := get_theme_default_font_size()
	var stage := Vector2(size.x, maxf(1.0, size.y - BAR_HEIGHT - font_size * 2.0))
	draw_rect(Rect2(Vector2.ZERO, stage), BACKGROUND)
	if character == null:
		return
	var view := _view_rect()
	var zoom := minf(stage.x / view.size.x, stage.y / view.size.y)
	draw_set_transform(stage / 2.0 - view.get_center() * zoom, 0.0, Vector2.ONE * zoom)
	_draw_character(view)
	if move != null:
		_draw_move()
	draw_set_transform(Vector2.ZERO)
	if move != null:
		_draw_timeline(stage.y, font_size)

## The area to fit on screen: at least MIN_VIEW, growing only when the content is larger.
func _view_rect() -> Rect2:
	var half := character.body_size / 2.0
	var view := MIN_VIEW.merge(Rect2(-half, half * 2.0).grow(VIEW_MARGIN))
	view = view.expand(Vector2(0.0, half.y - _picture_height() - VIEW_MARGIN))
	if move == null:
		return view
	var box := move.hit_box(half, 1.0)
	if box.has_area():
		view = view.merge(box.grow(ARROW_LENGTH + VIEW_MARGIN))
	for spawn in move.spawns:
		if spawn != null and spawn.projectile != null:
			view = view.merge(Rect2(spawn.offset, Vector2.ZERO).grow(ARROW_LENGTH + VIEW_MARGIN))
	return view

func _picture_height() -> float:
	if character.match_sprite == null:
		return 0.0
	return character.sprite_height if character.sprite_height > 0.0 else character.body_size.y

func _draw_character(view: Rect2) -> void:
	var half := character.body_size / 2.0
	draw_line(Vector2(view.position.x, half.y), Vector2(view.end.x, half.y), FLOOR_COLOR, 2.0)
	var picture := character.match_sprite
	if picture != null:
		var height := _picture_height()
		var drawn := Vector2(height * picture.get_width() / float(maxi(1, picture.get_height())), height)
		var feet := Vector2(character.sprite_offset.x, half.y + character.sprite_offset.y)
		var flip := -1.0 if character.sprite_faces_left else 1.0
		draw_texture_rect(picture, Rect2(feet + Vector2(-drawn.x / 2.0 * flip, -drawn.y), Vector2(drawn.x * flip, drawn.y)), false)
	draw_rect(Rect2(-half, half * 2.0), BODY_COLOR, false, 2.0)

func _draw_move() -> void:
	var half := character.body_size / 2.0
	var box := move.hit_box(half, 1.0)
	if box.has_area():
		draw_rect(box, Color(HIT_COLOR, 0.25))
		draw_rect(box, HIT_COLOR, false, 1.5)
		_draw_arrow(box.get_center(), move.launch_direction, ARROW_COLOR)
	for spawn in move.spawns:
		if spawn != null and spawn.projectile != null:
			_draw_spawn(spawn)

func _draw_spawn(spawn: ProjectileSpawn) -> void:
	var count := maxi(1, spawn.count)
	draw_rect(Rect2(spawn.offset - spawn.projectile.size / 2.0, spawn.projectile.size), SHOT_COLOR, false, 1.5)
	for index in range(count):
		var spread := 0.0 if count == 1 else spawn.spread_degrees * (float(index) / float(count - 1) - 0.5)
		var angle := deg_to_rad(spawn.angle_degrees + spread)
		_draw_arrow(spawn.offset, Vector2(cos(angle), sin(angle)), SHOT_COLOR)

func _draw_arrow(from: Vector2, direction: Vector2, color: Color) -> void:
	if direction.is_zero_approx():
		return
	var heading := direction.normalized()
	var tip := from + heading * ARROW_LENGTH
	draw_line(from, tip, color, 2.0)
	draw_line(tip, tip - heading.rotated(0.5) * 12.0, color, 2.0)
	draw_line(tip, tip - heading.rotated(-0.5) * 12.0, color, 2.0)

func _draw_timeline(top: float, font_size: int) -> void:
	var total := float(move.total_frames())
	var bar_top := top + 6.0
	var x := 0.0
	for part: Array in [[maxi(0, move.startup_frames), STARTUP_COLOR], [maxi(1, move.active_frames), ACTIVE_COLOR], [maxi(0, move.recovery_frames), RECOVERY_COLOR]]:
		var width: float = size.x * float(part[0]) / total
		draw_rect(Rect2(x, bar_top, width, BAR_HEIGHT), part[1])
		x += width
	var text := "선딜 %df · 지속 %df · 후딜 %df · 전체 %df (%.2f초)" % [move.startup_frames, move.active_frames, move.recovery_frames, move.total_frames(), total / 60.0]
	draw_string(get_theme_default_font(), Vector2(0.0, bar_top + BAR_HEIGHT + font_size * 1.3), text, HORIZONTAL_ALIGNMENT_LEFT, size.x, font_size)
