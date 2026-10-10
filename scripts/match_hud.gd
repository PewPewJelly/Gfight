class_name MatchHud
extends Control
## S3 match HUD: bottom band of player cards, centered floating start countdown,
## spectating band and off-screen arrows. Reads Session.arena; never changes game state.

## [제안] Height of the bottom card band; the arena's lowest platform stays above it.
@export var band_height: float = 130.0
## [제안] How long "시작!" stays after the countdown reaches zero.
@export var go_seconds: float = 0.7
@export var arrow_size: float = 18.0

var _go_left: float = 0.0
var _was_counting: bool = false
var _font: Font
## Card and countdown styles built once; _draw runs every frame.
var _card_styles: Dictionary = {}
var _floating_style: StyleBoxFlat

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = get_theme_default_font()
	for out in [false, true]:
		for mine in [false, true]:
			_card_styles[int(out) * 2 + int(mine)] = UiStyle.box(UiStyle.PANEL_MUTED if out else UiStyle.BACKGROUND,
				UiStyle.ACCENT if mine else UiStyle.TEXT_DIM, 3 if mine else 1, 10)
	_floating_style = UiStyle.box(Color(UiStyle.BACKGROUND, 0.9), UiStyle.TEXT, 2, 16)
	visibility_changed.connect(func() -> void: set_process(is_visible_in_tree()))
	set_process(false)

func _process(delta: float) -> void:
	var arena := Session.arena
	if is_instance_valid(arena):
		var counting := arena.countdown_left > 0.0
		if _was_counting and not counting:
			_go_left = go_seconds
		_was_counting = counting
	_go_left = maxf(0.0, _go_left - delta)
	queue_redraw()

func _draw() -> void:
	var arena := Session.arena
	if not is_instance_valid(arena):
		return
	var screen := get_viewport_rect().size
	var band := Rect2(0, screen.y - band_height, screen.x, band_height)
	draw_rect(band, Color(UiStyle.PANEL, 0.92))
	draw_line(band.position, Vector2(band.end.x, band.position.y), UiStyle.TEXT_DIM, 1.0)
	var count := arena.fighters.size()
	var gap := 16.0
	var card_width := minf(280.0, (screen.x - gap * (Session.MAX_PLAYERS + 1)) / Session.MAX_PLAYERS)
	var total := card_width * count + gap * (count - 1)
	var x := (screen.x - total) / 2.0
	var local_fighter: Fighter = null
	for fighter in arena.fighters:
		if fighter.is_local:
			local_fighter = fighter
		_draw_card(Rect2(x, band.position.y + 12.0, card_width, band_height - 24.0), fighter)
		x += card_width + gap
		_draw_offscreen_arrow(fighter, Rect2(Vector2.ZERO, Vector2(screen.x, band.position.y)), arena.get_viewport().get_canvas_transform())
	if arena.countdown_left > 0.0:
		_draw_floating(screen, "%d" % ceili(arena.countdown_left))
	elif _go_left > 0.0:
		_draw_floating(screen, UiStyle.GO)
	if local_fighter != null and local_fighter.life_state == Fighter.LifeState.ELIMINATED and not arena.ended:
		var strip := Rect2(0, 24, screen.x, 44)
		draw_rect(strip, Color(0, 0, 0, 0.55))
		_text(strip, UiStyle.SPECTATING, 22, UiStyle.TEXT)

func _draw_card(rect: Rect2, fighter: Fighter) -> void:
	var gone := not Session.local_mode and not Session.roster.has(fighter.player_id)
	var out := gone or fighter.life_state == Fighter.LifeState.ELIMINATED
	draw_style_box(_card_styles[int(out) * 2 + int(fighter.is_local)], rect)
	var color := UiStyle.slot_color(fighter.player_slot)
	if out:
		color = color.darkened(0.5)
	draw_rect(Rect2(rect.position + Vector2(14, 14), Vector2(14, 14)), color)
	var title := UiStyle.slot_title(fighter.player_slot)
	if fighter.is_local:
		title += " " + UiStyle.ME_TAG
	draw_string(_font, rect.position + Vector2(36, 27), title, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 44, 16, UiStyle.TEXT_DIM if out else UiStyle.TEXT)
	var middle := Rect2(rect.position + Vector2(0, 34), Vector2(rect.size.x, 36))
	if gone:
		_text(middle, UiStyle.DISCONNECTED, 24, UiStyle.TEXT_DIM)
	elif fighter.life_state == Fighter.LifeState.ELIMINATED:
		_text(middle, UiStyle.ELIMINATED, 24, UiStyle.TEXT_DIM)
	elif fighter.life_state == Fighter.LifeState.WAITING:
		_text(middle, UiStyle.RESPAWNING % maxi(1, ceili(fighter.respawn_left)), 24, UiStyle.TEXT)
	else:
		_text(middle, "%d%%" % roundi(fighter.percent), 30, UiStyle.danger_color(fighter.percent))
	var stocks := PackedStringArray()
	for index in range(CombatRules.INITIAL_STOCKS):
		stocks.append("●" if index < fighter.stocks else "○")
	_text(Rect2(rect.position + Vector2(0, 70), Vector2(rect.size.x, 20)), " ".join(stocks), 18, UiStyle.TEXT_DIM if out else UiStyle.TEXT)
	if fighter.invulnerability_left > 0.0 and fighter.life_state == Fighter.LifeState.ACTIVE:
		var ratio := clampf(fighter.invulnerability_left / CombatRules.RESPAWN_INVULNERABILITY, 0.0, 1.0)
		draw_rect(Rect2(rect.position.x + 12, rect.end.y - 8, (rect.size.x - 24) * ratio, 3), UiStyle.slot_color(fighter.player_slot))

func _draw_floating(screen: Vector2, text: String) -> void:
	var rect := Rect2(screen.x / 2.0 - 140.0, screen.y * 0.3 - 50.0, 280.0, 100.0)
	draw_style_box(_floating_style, rect)
	_text(rect, text, 52, UiStyle.TEXT)

## view is in screen space; the arena camera transform maps fighter positions onto it.
func _draw_offscreen_arrow(fighter: Fighter, view: Rect2, world_to_screen: Transform2D) -> void:
	var on_screen := world_to_screen * fighter.global_position
	if fighter.life_state != Fighter.LifeState.ACTIVE or view.has_point(on_screen):
		return
	var tip := Vector2(clampf(on_screen.x, arrow_size, view.end.x - arrow_size),
		clampf(on_screen.y, arrow_size, view.end.y - arrow_size))
	var direction := (on_screen - tip).normalized()
	if direction.is_zero_approx():
		return
	var side := direction.orthogonal() * arrow_size * 0.6
	var base := tip - direction * arrow_size
	draw_colored_polygon(PackedVector2Array([tip, base + side, base - side]), UiStyle.slot_color(fighter.player_slot))

func _text(rect: Rect2, text: String, font_size: int, color: Color) -> void:
	var baseline := rect.position.y + (rect.size.y + _font.get_ascent(font_size) - _font.get_descent(font_size)) / 2.0
	draw_string(_font, Vector2(rect.position.x, baseline), text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, font_size, color)
