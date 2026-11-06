class_name FightArena
extends Node2D

signal match_finished(winner_id: int)
signal snapshot_ready(state: Dictionary)
signal tick_completed(state: Dictionary)
var participant_ids: Array[int] = [1, 2]
## Participants without a player (training dummy): no input, neutral look.
var dummy_ids: Array[int] = []
var standalone: bool = true
var authoritative: bool = true
var input_provider: Callable
var frame: int = 0
var simulation_seed: int = 1
var starting_stocks: int = CombatRules.INITIAL_STOCKS
@export var rules: CombatRules = preload("res://resources/combat_rules.tres")
@export var attack: AttackData = preload("res://resources/basic_attack.tres")
@export var movement: MovementSettings = preload("res://resources/movement_settings.tres")
var fighters: Array[Fighter] = []
var character_picks: Dictionary = {}
var platforms: Array[Rect2] = [Rect2(180, 540, 920, 30), Rect2(260, 360, 260, 20), Rect2(760, 360, 260, 20)]
var screen_bounds := Rect2(0, 0, 1280, 720)
## Crossing any edge of this rectangle is an instant ring-out (see CombatRules.blast_zone).
var blast_zone: Rect2
var result: String = ""
var ended: bool = false
var winner_id: int = 0
## Seconds left in the shared start countdown; simulation waits until it reaches zero.
var countdown_left: float = 0.0
## Peer id whose fighter is drawn with the ▼나 marker (0 = none, e.g. local 2-player).
var local_player_id: int = 0
var hud: Label
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.seed = simulation_seed if simulation_seed != 0 else 1
	var stage := platforms[0]
	var lowest_top := platforms[0].position.y
	for surface in platforms:
		stage = stage.merge(surface)
		lowest_top = maxf(lowest_top, surface.position.y)
	blast_zone = rules.blast_zone(stage, lowest_top, screen_bounds, movement)
	for index in range(platforms.size()):
		var surface := platforms[index]
		var body := StaticBody2D.new()
		body.position = surface.get_center()
		var collider := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = surface.size
		collider.shape = shape
		collider.one_way_collision = index > 0
		collider.one_way_collision_margin = 4.0
		body.set_meta("drop_through", index > 0)
		body.add_child(collider)
		add_child(body)
	for id in range(participant_ids.size()):
		var fighter := Fighter.new()
		fighter.rules = rules
		fighter.player_id = participant_ids[id]
		fighter.character_id = StringName(character_picks.get(fighter.player_id, &"test_fighter"))
		fighter.player_slot = id + 1
		fighter.self_tick = false
		fighter.is_dummy = dummy_ids.has(fighter.player_id)
		fighter.tint = UiStyle.DUMMY_COLOR if fighter.is_dummy else UiStyle.slot_color(id + 1)
		fighter.is_local = fighter.player_id == local_player_id
		fighter.stock_lost.connect(_on_stock_lost)
		if id == 1:
			fighter.controls = [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_K]
		add_child(fighter)
		fighters.append(fighter)
	# Fixed camera on the stage center: wider or taller fullscreen windows add margin
	# around the whole stage instead of cutting it off (window/stretch/aspect = expand).
	var camera := Camera2D.new()
	camera.position = screen_bounds.get_center()
	add_child(camera)
	if standalone:
		var layer := CanvasLayer.new()
		add_child(layer)
		hud = Label.new()
		hud.position = Vector2(24, 18)
		hud.add_theme_font_size_override("font_size", 22)
		layer.add_child(hud)
	restart()

func restart() -> void:
	if not authoritative or fighters.size() < 2:
		return
	ended = false
	result = ""
	winner_id = 0
	countdown_left = 0.0 if standalone else maxf(0.0, rules.start_countdown)
	# Park everyone off-stage so each random start only avoids fighters already placed.
	for fighter in fighters:
		fighter.position = Vector2(-10000, -10000)
	for fighter in fighters:
		fighter.input_enabled = true
		var location := _spawn_location(fighter)
		if location == Vector2.INF:
			push_error("No free start position for P%d" % fighter.player_slot)
			location = Vector2(platforms[0].get_center().x, platforms[0].position.y - Fighter.HALF_SIZE.y)
		fighter.reset_round(location)
		fighter.stocks = starting_stocks
		fighter.tag_emphasis = countdown_left > 0.0
		fighter.queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
	if standalone and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		restart()

func _physics_process(delta: float) -> void:
	if not authoritative:
		_update_hud()
		return
	simulate_tick(delta)

func simulate_tick(delta: float) -> void:
	if countdown_left > 0.0:
		countdown_left = maxf(0.0, countdown_left - delta)
		if is_zero_approx(countdown_left):
			_set_tag_emphasis(false)
	elif not ended:
		for fighter in fighters:
			var mask: int = input_provider.call(fighter.player_id) if input_provider.is_valid() else Fighter.read_keyboard(fighter.controls, KEY_S if fighter == fighters[0] else KEY_DOWN)
			fighter.simulate(delta, mask)
		# Resolve all exits before checking victory, including simultaneous final exits.
		for fighter in fighters:
			if fighter.life_state == Fighter.LifeState.ACTIVE and rules.is_outside(fighter.position, blast_zone):
				fighter.ring_out()
		_resolve_result()
		if not ended:
			for fighter in fighters:
				if fighter.life_state == Fighter.LifeState.WAITING:
					fighter.respawn_left = maxf(0.0, fighter.respawn_left - delta)
					if fighter.respawn_left <= 0.0:
						var location := _spawn_location(fighter)
						if location != Vector2.INF:
							fighter.respawn(location)
			_resolve_attacks()
	_update_hud()
	frame += 1
	tick_completed.emit(snapshot())
	if frame % 3 == 0:
		snapshot_ready.emit(snapshot())

func _resolve_attacks() -> void:
	# Snapshot first: simultaneous attacks may both land; per target hits are ordered by player ID.
	var hits: Array[Dictionary] = []
	for source in fighters:
		if not source.attack_requested or source.life_state != Fighter.LifeState.ACTIVE:
			continue
		source.attack_requested = false
		var direction := source.attack_direction()
		var box := source.attack_box()
		box.position += source.position
		var data: AttackData = source.attack_data_for_kind()
		for target in fighters:
			if target == source or target.life_state != Fighter.LifeState.ACTIVE:
				continue
			if box.intersects(Rect2(target.position - Fighter.HALF_SIZE, Fighter.HALF_SIZE * 2.0)):
				hits.append({"source": source, "target": target, "direction": direction, "attack": data})
	for hit in hits:
		var target: Fighter = hit.target
		var before := target.percent
		var source: Fighter = hit.source
		var strike_count := source.junbae.finisher_close_hits if source.attack_kind == "finisher" and absf(source.position.x - target.position.x) < 60.0 else 1
		for strike in range(strike_count):
			if not target.receive_hit(hit.attack, hit.direction):
				break
			source.dealt_percent += target.percent - before
			before = target.percent
			target.last_attacker_id = source.player_id
	_resolve_projectile_hits()

func nearest_fighter(from: Vector2, exclude_id: int) -> Fighter:
	var nearest: Fighter = null
	var nearest_distance := INF
	for fighter in fighters:
		if fighter.player_id == exclude_id or fighter.life_state != Fighter.LifeState.ACTIVE:
			continue
		var distance := from.distance_squared_to(fighter.position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = fighter
	return nearest

func fighter_for_id(id: int) -> Fighter:
	for fighter: Fighter in fighters:
		if fighter.player_id == id:
			return fighter
	return null

func _resolve_projectile_hits() -> void:
	_reflect_projectiles()
	for owner: Fighter in fighters:
		if owner.character_id != &"junbae" or owner.projectile_kind.is_empty():
			continue
		var attacker := fighter_for_id(owner.projectile_owner_id)
		if attacker == null:
			attacker = owner
		for target: Fighter in fighters:
			if target.player_id == owner.projectile_owner_id or target.life_state != Fighter.LifeState.ACTIVE:
				continue
			var radius := 18.0 if owner.projectile_kind.begins_with("mirror") else 24.0
			var shot_box := Rect2(owner.projectile_position - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)
			if not shot_box.intersects(Rect2(target.position - Fighter.HALF_SIZE, Fighter.HALF_SIZE * 2.0)):
				continue
			var kind := owner.projectile_kind
			var data := owner.attack_data_for_kind(kind)
			if kind == "altino":
				data.damage = owner.junbae.altino_damage + 2.0
				data.percent_increase = owner.junbae.altino_percent + 2.0
				data.base_launch_speed = 540.0
				data.width = 132.0
				data.launch_direction = Vector2(owner.facing, -0.4)
			elif kind == "meme":
				data = owner.attack_data_for_kind("meme")
				owner.attack_kind = "meme"
			var blast_center := owner.projectile_position
			if kind == "altino":
				owner._emote("와아, 우레시이~", 0.55)
				owner.projectile_kind = ""
				for blast_target: Fighter in fighters:
					if blast_target == attacker or blast_target.life_state != Fighter.LifeState.ACTIVE:
						continue
					if (blast_target.position - blast_center).abs().x > 62.0 or (blast_target.position - blast_center).abs().y > 72.0:
						continue
					_apply_attack_hit(attacker, blast_target, data, Vector2(owner.projectile_velocity.normalized().x, -0.4))
			else:
				if kind == "meme":
					owner._emote("어흐", 0.75)
				_apply_attack_hit(attacker, target, data, owner.projectile_velocity.normalized())
				owner.projectile_kind = ""
			break

func _reflect_projectiles() -> void:
	# Reflection is resolved before projectile impacts so the new owner can be hit.
	for swordsman: Fighter in fighters:
		if swordsman.character_id != &"junbae" or swordsman.attack_kind != "sword" or swordsman.attack_cooldown < 0.42:
			continue
		var sweep := swordsman.attack_box()
		sweep.position += swordsman.position
		for owner: Fighter in fighters:
			if owner == swordsman or owner.projectile_kind.is_empty():
				continue
			var point_box := Rect2(owner.projectile_position - Vector2(18, 18), Vector2(36, 36))
			if sweep.intersects(point_box):
				owner.projectile_velocity = Vector2(-owner.projectile_velocity.x, -owner.projectile_velocity.y)
				owner.projectile_owner_id = swordsman.player_id

func _apply_attack_hit(source: Fighter, target: Fighter, attack_data: AttackData, direction: Vector2) -> void:
	var before := target.percent
	if target.receive_hit(attack_data, direction):
		source.dealt_percent += target.percent - before
		target.last_attacker_id = source.player_id

## Credits the kill to the last attacker and records elimination order for ranks.
func _on_stock_lost(fighter: Fighter) -> void:
	if not authoritative:
		return
	if fighter.last_attacker_id != 0 and fighter.last_attacker_id != fighter.player_id:
		for other in fighters:
			if other.player_id == fighter.last_attacker_id:
				other.kills += 1
	fighter.last_attacker_id = 0
	if fighter.life_state == Fighter.LifeState.ELIMINATED:
		fighter.eliminated_frame = frame

func _set_tag_emphasis(enabled: bool) -> void:
	for fighter in fighters:
		fighter.tag_emphasis = enabled
		fighter.queue_redraw()

## Ranks for the result screen: winner first, then later eliminations rank higher.
## Fighters eliminated on the same frame share a rank (a final simultaneous exit is a shared 1st).
static func compute_ranks(entries: Array[Dictionary]) -> Dictionary:
	var order := entries.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _rank_key(a) > _rank_key(b))
	var ranks := {}
	var previous_key := -2
	var current_rank := 0
	for index in range(order.size()):
		var key := _rank_key(order[index])
		if key != previous_key:
			current_rank = index + 1
			previous_key = key
		ranks[order[index].id] = current_rank
	return ranks

static func _rank_key(entry: Dictionary) -> int:
	var out_frame: int = entry.out
	return 1 << 30 if out_frame < 0 else out_frame

func _resolve_result() -> void:
	var survivors: Array[Fighter] = []
	for fighter in fighters:
		if fighter.stocks > 0:
			survivors.append(fighter)
	if survivors.size() > 1:
		return
	ended = true
	winner_id = survivors[0].player_id if survivors.size() == 1 else 0
	_set_tag_emphasis(false)
	result = "P%d WINS" % survivors[0].player_slot if winner_id > 0 else "DRAW"
	for fighter in fighters:
		fighter.input_enabled = false
		fighter.attack_requested = false
	match_finished.emit(winner_id)

func _spawn_location(fighter: Fighter) -> Vector2:
	var candidates: Array[Vector2] = []
	for surface in platforms:
		var x := surface.position.x + Fighter.HALF_SIZE.x + 8.0
		while x <= surface.end.x - Fighter.HALF_SIZE.x - 8.0:
			var candidate := Vector2(x, surface.position.y - Fighter.HALF_SIZE.y)
			var occupied := false
			for other in fighters:
				if other != fighter and other.life_state == Fighter.LifeState.ACTIVE:
					var separation := (other.position - candidate).abs()
					if separation.x < Fighter.HALF_SIZE.x * 2.0 + 8.0 and separation.y < Fighter.HALF_SIZE.y * 2.0 + 8.0:
						occupied = true
			if not occupied:
				candidates.append(candidate)
			x += 48.0
	# No free platform position: remain waiting and retry, never spawn in another fighter.
	return Vector2.INF if candidates.is_empty() else candidates[rng.randi_range(0, candidates.size() - 1)]

func _update_hud() -> void:
	if hud == null:
		return
	var instructions := "A/D move · W jump · S drop · J attack (W/J up, S/J down)"
	if standalone:
		instructions += " | P2: Arrows + K | R restart"
	var lines := PackedStringArray([instructions])
	for fighter in fighters:
		var status := ""
		if fighter.life_state == Fighter.LifeState.WAITING:
			status = "Respawn %.1fs" % fighter.respawn_left
		elif fighter.life_state == Fighter.LifeState.ELIMINATED:
			status = "Eliminated"
		elif fighter.invulnerability_left > 0.0:
			status = "Invulnerable %.1fs" % fighter.invulnerability_left
		lines.append("P%d    Stocks %d    %.0f%%    %s" % [fighter.player_slot, fighter.stocks, fighter.percent, status])
	if ended:
		lines.append(result)
	hud.text = "\n".join(lines)

func snapshot() -> Dictionary:
	var players: Array[Dictionary] = []
	for fighter in fighters:
		players.append({"id": fighter.player_id, "position": fighter.position, "velocity": fighter.velocity,
			"stocks": fighter.stocks, "percent": fighter.percent, "damage": fighter.damage_received,
			"life": fighter.life_state, "invulnerability": fighter.invulnerability_left,
			"respawn": fighter.respawn_left, "hitstun": fighter.hitstun_left,
			"cooldown": fighter.attack_cooldown, "jumps": fighter.jumps_left,
			"facing": fighter.facing, "kind": fighter.attack_kind, "visual": fighter.attack_visual,
			"kills": fighter.kills, "dealt": fighter.dealt_percent, "out": fighter.eliminated_frame,
			"jump_down": fighter.jump_was_down, "attack_down": fighter.attack_was_down,
			"down_down": fighter.down_was_down, "attack_requested": fighter.attack_requested,
			"last_input": fighter.last_input_mask, "last_attacker": fighter.last_attacker_id,
			"drop": fighter.drop_left, "character": String(fighter.character_id),
			"special_cooldown": fighter.special_cooldown, "special_down": fighter.special_was_down,
			"digital": fighter.digital_mode, "digital_delay": fighter.digital_delay,
			"digital_count": fighter.digital_delay_count, "digital_action": fighter.digital_action,
			"digital_action_left": fighter.digital_action_left, "digital_airborne": fighter.digital_skill_airborne,
			"projectile_kind": fighter.projectile_kind,
			"look_style": fighter.look_style, "portrait_style": fighter.portrait_style,
			"portrait_position": fighter.digital_portrait_position,
			"emote": fighter.emote_text, "emote_left": fighter.emote_left,
			"projectile_position": fighter.projectile_position, "projectile_velocity": fighter.projectile_velocity,
			"projectile_left": fighter.projectile_left, "projectile_owner": fighter.projectile_owner_id,
			"mirror_position": fighter.mirror_position, "neutral_combo": fighter.neutral_combo,
			"neutral_combo_left": fighter.neutral_combo_left})
	return {"players": players, "ended": ended, "result": result, "winner": winner_id,
		"countdown": countdown_left, "frame": frame, "rng": rng.state}

func apply_snapshot(state: Dictionary) -> void:
	_apply_snapshot(state, false)

## Rollback deliberately restores an older frame, unlike ordinary network snapshots.
func restore_snapshot(state: Dictionary) -> void:
	_apply_snapshot(state, true)

func _apply_snapshot(state: Dictionary, allow_older: bool) -> void:
	if not allow_older and int(state.get("frame", -1)) < frame:
		return
	frame = state.frame
	ended = state.ended
	result = state.result
	winner_id = state.winner
	rng.state = int(state.get("rng", rng.state))
	var emphasis_changed := (countdown_left > 0.0) != (float(state.countdown) > 0.0)
	countdown_left = state.countdown
	for data in state.players:
		for fighter in fighters:
			if fighter.player_id != data.id:
				continue
			fighter.position = data.position
			fighter.velocity = data.velocity
			fighter.stocks = data.stocks
			fighter.percent = data.percent
			fighter.damage_received = data.damage
			fighter.life_state = data.life
			fighter.invulnerability_left = data.invulnerability
			fighter.respawn_left = data.respawn
			fighter.hitstun_left = data.hitstun
			fighter.attack_cooldown = data.cooldown
			fighter.jumps_left = data.jumps
			fighter.facing = data.facing
			fighter.attack_kind = data.kind
			fighter.attack_visual = data.visual
			fighter.kills = data.kills
			fighter.dealt_percent = data.dealt
			fighter.eliminated_frame = data.out
			fighter.jump_was_down = bool(data.get("jump_down", false))
			fighter.attack_was_down = bool(data.get("attack_down", false))
			fighter.down_was_down = bool(data.get("down_down", false))
			fighter.attack_requested = bool(data.get("attack_requested", false))
			fighter.last_input_mask = int(data.get("last_input", 0))
			fighter.last_attacker_id = int(data.get("last_attacker", 0))
			fighter.special_cooldown = float(data.get("special_cooldown", 0.0))
			fighter.special_was_down = bool(data.get("special_down", false))
			fighter.digital_mode = bool(data.get("digital", false))
			fighter.digital_delay = float(data.get("digital_delay", 0.0))
			fighter.digital_delay_count = int(data.get("digital_count", 0))
			fighter.digital_action = String(data.get("digital_action", ""))
			fighter.digital_action_left = float(data.get("digital_action_left", 0.0))
			fighter.digital_skill_airborne = bool(data.get("digital_airborne", false))
			fighter.projectile_kind = String(data.get("projectile_kind", ""))
			fighter.projectile_position = data.get("projectile_position", Vector2.ZERO)
			fighter.projectile_velocity = data.get("projectile_velocity", Vector2.ZERO)
			fighter.projectile_left = float(data.get("projectile_left", 0.0))
			fighter.projectile_owner_id = int(data.get("projectile_owner", fighter.player_id))
			fighter.mirror_position = data.get("mirror_position", Vector2.ZERO)
			fighter.neutral_combo = int(data.get("neutral_combo", 0))
			fighter.neutral_combo_left = float(data.get("neutral_combo_left", 0.0))
			fighter._set_character_look(String(data.get("look_style", "digital" if fighter.digital_mode else "standing")))
			fighter.portrait_style = String(data.get("portrait_style", "profile"))
			fighter.digital_portrait_position = data.get("portrait_position", fighter.position + Vector2(0, -92))
			fighter.emote_text = String(data.get("emote", ""))
			fighter.emote_left = float(data.get("emote_left", 0.0))
			if fighter.digital_mode and is_instance_valid(fighter.portrait_marker):
				fighter.portrait_marker.texture = fighter._profile_texture(fighter.portrait_style)
				fighter.portrait_marker.global_position = fighter.digital_portrait_position
				fighter.portrait_marker.show()
			elif is_instance_valid(fighter.portrait_marker):
				fighter.portrait_marker.hide()
			fighter.restore_drop_state(float(data.get("drop", 0.0)))
			fighter.tag_emphasis = countdown_left > 0.0
			fighter.visible = fighter.life_state == Fighter.LifeState.ACTIVE
			fighter.queue_redraw()
	if emphasis_changed:
		_set_tag_emphasis(countdown_left > 0.0)
	_update_hud()

func _draw() -> void:
	draw_rect(screen_bounds, Color("101927"))
	# Blast lines (only visible on screens wider/taller than the 1280×720 stage view).
	var line_color := Color(UiStyle.ERROR, 0.35)
	var zone := blast_zone
	draw_dashed_line(zone.position, Vector2(zone.position.x, zone.end.y), line_color, 2.0, 12.0)
	draw_dashed_line(Vector2(zone.end.x, zone.position.y), zone.end, line_color, 2.0, 12.0)
	draw_dashed_line(Vector2(zone.position.x, zone.end.y), zone.end, line_color, 2.0, 12.0)
	for surface in platforms:
		draw_rect(surface, Color("637890"))
		draw_line(surface.position, Vector2(surface.end.x, surface.position.y), Color("c5d6e7"), 3.0)
