class_name FightArena
extends Node2D

signal match_finished(winner_id: int)
signal snapshot_ready(state: Dictionary)
var participant_ids: Array[int] = [1, 2]
var standalone: bool = true
var authoritative: bool = true
var input_provider: Callable
var frame: int = 0
@export var rules: CombatRules = preload("res://resources/combat_rules.tres")
@export var attack: AttackData = preload("res://resources/basic_attack.tres")
var fighters: Array[Fighter] = []
var platforms: Array[Rect2] = [Rect2(180, 540, 920, 30), Rect2(260, 360, 260, 20), Rect2(760, 360, 260, 20)]
var screen_bounds := Rect2(0, 0, 1280, 720)
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
	rng.randomize()
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
		fighter.tint = UiStyle.slot_color(id + 1)
		fighter.is_local = fighter.player_id == local_player_id
		fighter.stock_lost.connect(_on_stock_lost)
		if id == 1:
			fighter.controls = [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_K]
		add_child(fighter)
		fighters.append(fighter)
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(24, 18)
	hud.add_theme_font_size_override("font_size", 22)
	layer.add_child(hud)
	hud.visible = standalone
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
		fighter.tag_emphasis = countdown_left > 0.0
		fighter.queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
	if standalone and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		restart()

func _physics_process(delta: float) -> void:
	if not authoritative:
		_update_hud()
		return
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
			if fighter.life_state == Fighter.LifeState.ACTIVE and rules.is_outside(fighter.position, screen_bounds):
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
		var data: AttackData = source.attacks[source.attack_kind]
		for target in fighters:
			if target == source or target.life_state != Fighter.LifeState.ACTIVE:
				continue
			if box.intersects(Rect2(target.position - Fighter.HALF_SIZE, Fighter.HALF_SIZE * 2.0)):
				hits.append({"source": source, "target": target, "direction": direction, "attack": data})
	for hit in hits:
		var target: Fighter = hit.target
		var before := target.percent
		if target.receive_hit(hit.attack, hit.direction):
			var source: Fighter = hit.source
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
	if not standalone:
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
			"kills": fighter.kills, "dealt": fighter.dealt_percent, "out": fighter.eliminated_frame})
	return {"players": players, "ended": ended, "result": result, "winner": winner_id,
		"countdown": countdown_left, "frame": frame}

func apply_snapshot(state: Dictionary) -> void:
	if int(state.get("frame", -1)) < frame:
		return
	frame = state.frame
	ended = state.ended
	result = state.result
	winner_id = state.winner
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
			fighter.tag_emphasis = countdown_left > 0.0
			fighter.visible = fighter.life_state == Fighter.LifeState.ACTIVE
			fighter.queue_redraw()
	if emphasis_changed:
		_set_tag_emphasis(countdown_left > 0.0)
	_update_hud()

func _draw() -> void:
	draw_rect(screen_bounds, Color("101927"))
	for surface in platforms:
		draw_rect(surface, Color("637890"))
		draw_line(surface.position, Vector2(surface.end.x, surface.position.y), Color("c5d6e7"), 3.0)
