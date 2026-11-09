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
@export var movement: MovementSettings = preload("res://resources/movement_settings.tres")
## Empty loads the project's catalog in _ready. Not a preload: characters refer back to
## this script through their kits and projectile behaviors, which would be a load cycle.
@export var catalog: ContentCatalog
## peer id -> character id (MatchSetup.characters). Missing ids use the catalog's first character.
var character_ids: Dictionary = {}
var fighters: Array[Fighter] = []
## Live projectiles in launch order. Plain state, not nodes: rollback replays many ticks in one
## frame, which physics areas cannot follow, so hits use the same rectangle tests as moves.
var projectiles: Array[Projectile] = []
## Snapshots refer to projectile types by index here (see index_projectile_types).
var projectile_types: Array[ProjectileData] = []
var next_projectile_id: int = 0
var projectile_view: ProjectileView
var _default_behavior := ProjectileBehavior.new()
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
	if catalog == null:
		catalog = load("res://resources/content_catalog.tres")
	rng.seed = simulation_seed if simulation_seed != 0 else 1
	var stage := platforms[0]
	var lowest_top := platforms[0].position.y
	for surface in platforms:
		stage = stage.merge(surface)
		lowest_top = maxf(lowest_top, surface.position.y)
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
		fighter.player_slot = id + 1
		fighter.self_tick = false
		fighter.is_dummy = dummy_ids.has(fighter.player_id)
		fighter.tint = UiStyle.DUMMY_COLOR if fighter.is_dummy else UiStyle.slot_color(id + 1)
		fighter.is_local = fighter.player_id == local_player_id
		fighter.use_character(_character_for(fighter.player_id))
		fighter.arena = self
		fighter.stock_lost.connect(_on_stock_lost)
		if id == 1:
			fighter.controls = Fighter.P2_KEYS
		add_child(fighter)
		fighters.append(fighter)
	index_projectile_types()
	projectile_view = ProjectileView.new()
	projectile_view.arena = self
	add_child(projectile_view)
	blast_zone = rules.blast_zone_for_reach(stage, lowest_top, screen_bounds, _farthest_reach())
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
	projectiles.clear()
	next_projectile_id = 0
	projectile_view.queue_redraw()
	# Park everyone off-stage so each random start only avoids fighters already placed.
	for fighter in fighters:
		fighter.position = Vector2(-10000, -10000)
	for fighter in fighters:
		fighter.input_enabled = true
		var location := _spawn_location(fighter)
		if location == Vector2.INF:
			push_error("No free start position for P%d" % fighter.player_slot)
			location = Vector2(platforms[0].get_center().x, platforms[0].position.y - fighter.half_size.y)
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
			var mask: int = input_provider.call(fighter.player_id) if input_provider.is_valid() else Fighter.read_keyboard(fighter.controls)
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
			_step_projectiles(delta)
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
		var data := source.active_move
		var box := source.attack_box()
		# Movement-only skills have no hit area.
		if data == null or not box.has_area():
			continue
		var direction := source.attack_direction()
		box.position += source.position
		if data.reflects_projectiles:
			_reflect_projectiles(source, box)
		for target in fighters:
			if target == source or target.life_state != Fighter.LifeState.ACTIVE or (source.hit_mask & target.slot_bit()) != 0:
				continue
			if box.intersects(_body_box(target)):
				hits.append({"source": source, "target": target, "direction": direction, "attack": data})
	_collect_projectile_hits(hits)
	for hit in hits:
		var target: Fighter = hit.target
		var before := target.percent
		if target.receive_hit(hit.attack, hit.direction):
			var source: Fighter = hit.source
			source.dealt_percent += target.percent - before
			target.last_attacker_id = source.player_id
			_after_hit(hit, source, target)
	_remove_dead_projectiles()
	projectile_view.queue_redraw()

func _body_box(fighter: Fighter) -> Rect2:
	return Rect2(fighter.position - fighter.half_size, fighter.half_size * 2.0)

func _after_hit(hit: Dictionary, source: Fighter, target: Fighter) -> void:
	if hit.has("shot"):
		var shot: Projectile = hit.shot
		shot.hit_mask |= target.slot_bit()
		_behavior_of(shot).on_hit(shot, self, target)
		if shot.data.after_hit == ProjectileData.AfterHit.VANISH:
			shot.alive = false
	else:
		source.hit_mask |= target.slot_bit()
	if source.kit != null:
		source.kit.on_hit_dealt(source, target, hit.attack)

## Lists the projectile types of everyone in the match. Participant order is the same on every
## peer, so the same index means the same type everywhere.
func index_projectile_types() -> void:
	projectile_types.clear()
	for fighter in fighters:
		for resource in fighter.character.reachable_resources():
			if resource is ProjectileData and not projectile_types.has(resource):
				projectile_types.append(resource)

## Launches what a move's trigger asks for, fanned out across spread_degrees.
func launch(spawn: ProjectileSpawn, shooter: Fighter) -> void:
	var at := shooter.position + Vector2(spawn.offset.x * shooter.facing, spawn.offset.y)
	var count := maxi(1, spawn.count)
	for index in range(count):
		var spread := 0.0 if count == 1 else spawn.spread_degrees * (float(index) / float(count - 1) - 0.5)
		var angle := deg_to_rad(spawn.angle_degrees + spread)
		var launch_velocity := Vector2(cos(angle) * shooter.facing, sin(angle)) * spawn.projectile.speed
		spawn_projectile(spawn.projectile, shooter, at, launch_velocity)

## Adds one projectile; kits and behaviors can call this directly. Returns null when a limit
## blocks it. `data` must be an @export reachable from a character in the match.
func spawn_projectile(data: ProjectileData, shooter: Fighter, at: Vector2, launch_velocity: Vector2) -> Projectile:
	var type_index := projectile_types.find(data)
	if type_index < 0:
		push_error("%s launched a projectile it does not export" % shooter.character.id)
		return null
	if projectiles.size() >= rules.max_projectiles:
		return null
	if data.max_active > 0 and _active_count(type_index, shooter.player_id) >= data.max_active:
		return null
	var shot := Projectile.new()
	shot.id = next_projectile_id
	next_projectile_id += 1
	shot.owner_id = shooter.player_id
	shot.type_index = type_index
	shot.data = data
	shot.position = at
	shot.velocity = launch_velocity
	shot.facing = shooter.facing
	projectiles.append(shot)
	_behavior_of(shot).on_spawn(shot, self)
	return shot

func projectiles_of(shooter: Fighter) -> Array[Projectile]:
	var owned: Array[Projectile] = []
	for shot in projectiles:
		if shot.owner_id == shooter.player_id:
			owned.append(shot)
	return owned

func fighter_by_id(id: int) -> Fighter:
	for fighter in fighters:
		if fighter.player_id == id:
			return fighter
	return null

## Closest fighter still in play, excluding one player; ties go to the earlier participant.
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

func _behavior_of(shot: Projectile) -> ProjectileBehavior:
	return shot.data.behavior if shot.data.behavior != null else _default_behavior

func _active_count(type_index: int, owner_id: int) -> int:
	var count := 0
	for shot in projectiles:
		if shot.alive and shot.type_index == type_index and shot.owner_id == owner_id:
			count += 1
	return count

func _step_projectiles(delta: float) -> void:
	# Projectiles launched during this loop (splits) start moving next tick.
	for index in range(projectiles.size()):
		var shot := projectiles[index]
		var behavior := _behavior_of(shot)
		behavior.step(shot, self, delta)
		shot.age += 1
		# Same rounding as fighters, so CPU differences do not build up across peers.
		shot.position = Vector2(snappedf(shot.position.x, 0.001), snappedf(shot.position.y, 0.001))
		shot.velocity = Vector2(snappedf(shot.velocity.x, 0.001), snappedf(shot.velocity.y, 0.001))
		if shot.alive and shot.data.hits_platforms:
			for surface in platforms:
				if shot.box().intersects(surface):
					behavior.on_platform(shot, self, surface)
					break
		if shot.alive and shot.data.lifetime_frames > 0 and shot.age >= shot.data.lifetime_frames:
			behavior.on_expire(shot, self)
			shot.alive = false
		if shot.alive and rules.is_outside(shot.position, blast_zone):
			shot.alive = false

func _reflect_projectiles(reflector: Fighter, box: Rect2) -> void:
	for shot in projectiles:
		if shot.alive and shot.owner_id != reflector.player_id and box.intersects(shot.box()):
			shot.owner_id = reflector.player_id
			shot.velocity = -shot.velocity
			shot.facing = -shot.facing
			shot.hit_mask = 0
			shot.age = 0

func _collect_projectile_hits(hits: Array[Dictionary]) -> void:
	for shot in projectiles:
		var source := fighter_by_id(shot.owner_id)
		if not shot.alive or source == null:
			continue
		var side := signf(shot.velocity.x) if not is_zero_approx(shot.velocity.x) else shot.facing
		var direction := Vector2(shot.data.launch_direction.x * side, shot.data.launch_direction.y).normalized()
		for target in fighters:
			if target == source or target.life_state != Fighter.LifeState.ACTIVE or target.invulnerability_left > 0.0 or (shot.hit_mask & target.slot_bit()) != 0:
				continue
			if shot.box().intersects(_body_box(target)):
				hits.append({"source": source, "target": target, "direction": direction, "attack": shot.data, "shot": shot})
				# A shot that vanishes on hit only reaches the first fighter in its way.
				if shot.data.after_hit == ProjectileData.AfterHit.VANISH:
					break

func _remove_dead_projectiles() -> void:
	for index in range(projectiles.size() - 1, -1, -1):
		if not projectiles[index].alive:
			projectiles.remove_at(index)

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

func _character_for(peer_id: int) -> CharacterDef:
	var pick: StringName = character_ids.get(peer_id, catalog.default_character())
	var entry := catalog.character(pick)
	if entry == null:
		push_warning("Unknown character id: %s" % pick)
		entry = catalog.character(catalog.default_character())
	return entry

## [임시] Characters can move differently, so the blast lines follow the best recovery
## among the participants: nobody is ringed out while they could still return.
func _farthest_reach() -> Vector2:
	if fighters.is_empty():
		return CombatRules.recovery_reach(movement)
	var reach := Vector2.ZERO
	for fighter in fighters:
		var own := CombatRules.recovery_reach(fighter.movement)
		reach = Vector2(maxf(reach.x, own.x), maxf(reach.y, own.y))
	return reach

func _spawn_location(fighter: Fighter) -> Vector2:
	var candidates: Array[Vector2] = []
	for surface in platforms:
		var x := surface.position.x + fighter.half_size.x + 8.0
		while x <= surface.end.x - fighter.half_size.x - 8.0:
			var candidate := Vector2(x, surface.position.y - fighter.half_size.y)
			var occupied := false
			for other in fighters:
				if other != fighter and other.life_state == Fighter.LifeState.ACTIVE:
					var separation := (other.position - candidate).abs()
					var clearance := other.half_size + fighter.half_size + Vector2(8.0, 8.0)
					if separation.x < clearance.x and separation.y < clearance.y:
						occupied = true
			if not occupied:
				candidates.append(candidate)
			x += 48.0
	# No free platform position: remain waiting and retry, never spawn in another fighter.
	return Vector2.INF if candidates.is_empty() else candidates[rng.randi_range(0, candidates.size() - 1)]

func _update_hud() -> void:
	if hud == null:
		return
	var instructions := "A/D move · Space jump · S drop · J attack · K skill (W/S/A/D aim)"
	if standalone:
		instructions += " | P2: Arrows + , jump + . attack + / skill | R restart"
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
			"facing": fighter.facing, "kind": fighter.attack_slot, "skill": fighter.attack_is_skill,
			"visual": fighter.attack_visual, "flash": fighter.attack_flash_left,
			"phase": fighter.move_phase, "move_frame": fighter.move_frame, "hit_mask": fighter.hit_mask,
			"move": fighter.moves.find(fighter.active_move), "kit": fighter.kit_state.duplicate(true),
			"kills": fighter.kills, "dealt": fighter.dealt_percent, "out": fighter.eliminated_frame,
			"jump_down": fighter.jump_was_down, "attack_down": fighter.attack_was_down,
			"skill_down": fighter.skill_was_down, "skill_cooldowns": fighter.skill_cooldown_state(),
			"down_down": fighter.down_was_down, "attack_requested": fighter.attack_requested,
			"last_input": fighter.last_input_mask, "last_attacker": fighter.last_attacker_id,
			"drop": fighter.drop_left})
	var shots: Array[Dictionary] = []
	for shot in projectiles:
		shots.append(shot.snapshot())
	return {"players": players, "ended": ended, "result": result, "winner": winner_id,
		"countdown": countdown_left, "frame": frame, "rng": rng.state,
		"projectiles": shots, "next_projectile": next_projectile_id}

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
			# Replicas that only display snapshots keep their collision off (Session).
			if authoritative:
				fighter.update_collision()
			fighter.invulnerability_left = data.invulnerability
			fighter.respawn_left = data.respawn
			fighter.hitstun_left = data.hitstun
			fighter.attack_cooldown = data.cooldown
			fighter.jumps_left = data.jumps
			fighter.facing = data.facing
			fighter.restore_move_state(data.kind, data.skill, int(data.get("move", -1)), data.get("skill_cooldowns", {}))
			fighter.move_phase = data.get("phase", Fighter.MovePhase.NONE) if fighter.active_move != null else Fighter.MovePhase.NONE
			fighter.move_frame = int(data.get("move_frame", 0))
			fighter.hit_mask = int(data.get("hit_mask", 0))
			var saved_kit: Dictionary = data.get("kit", {})
			fighter.kit_state = saved_kit.duplicate(true)
			fighter.attack_visual = data.visual
			fighter.attack_flash_left = float(data.get("flash", 0.0))
			fighter.kills = data.kills
			fighter.dealt_percent = data.dealt
			fighter.eliminated_frame = data.out
			fighter.jump_was_down = bool(data.get("jump_down", false))
			fighter.attack_was_down = bool(data.get("attack_down", false))
			fighter.skill_was_down = bool(data.get("skill_down", false))
			fighter.down_was_down = bool(data.get("down_down", false))
			fighter.attack_requested = bool(data.get("attack_requested", false))
			fighter.last_input_mask = int(data.get("last_input", 0))
			fighter.last_attacker_id = int(data.get("last_attacker", 0))
			fighter.restore_drop_state(float(data.get("drop", 0.0)))
			fighter.tag_emphasis = countdown_left > 0.0
			fighter.visible = fighter.life_state == Fighter.LifeState.ACTIVE
			fighter.queue_redraw()
	if emphasis_changed:
		_set_tag_emphasis(countdown_left > 0.0)
	projectiles.clear()
	for value: Variant in state.get("projectiles", []):
		var shot := Projectile.from_snapshot(value, projectile_types)
		if shot != null:
			projectiles.append(shot)
	next_projectile_id = int(state.get("next_projectile", next_projectile_id))
	projectile_view.queue_redraw()
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
