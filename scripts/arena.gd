extends Node2D

signal match_finished(winner_id: int)
@export var rules: CombatRules = preload("res://resources/combat_rules.tres")
@export var attack: AttackData = preload("res://resources/basic_attack.tres")
var fighters: Array[Fighter] = []
var platforms: Array[Rect2] = [Rect2(180, 540, 920, 30), Rect2(260, 360, 260, 20), Rect2(760, 360, 260, 20)]
var screen_bounds := Rect2(0, 0, 1280, 720)
var result: String = ""
var ended: bool = false
var hud: Label
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()
	for surface in platforms:
		var body := StaticBody2D.new()
		body.position = surface.get_center()
		var collider := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = surface.size
		collider.shape = shape
		body.add_child(collider)
		add_child(body)
	for id in range(2):
		var fighter := Fighter.new()
		fighter.rules = rules
		fighter.player_id = id + 1
		fighter.tint = Color("58c7ff") if id == 0 else Color("ffb75b")
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
	restart()

func restart() -> void:
	ended = false
	result = ""
	for index in range(fighters.size()):
		fighters[index].input_enabled = true
		fighters[index].reset_round(Vector2(370 if index == 0 else 890, 360 - Fighter.HALF_SIZE.y))

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		restart()

func _physics_process(delta: float) -> void:
	if not ended:
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

func _resolve_attacks() -> void:
	# Snapshot first: simultaneous attacks may both land; per target hits are ordered by player ID.
	var hits: Array[Dictionary] = []
	for source in fighters:
		if not source.attack_requested or source.life_state != Fighter.LifeState.ACTIVE:
			continue
		source.attack_requested = false
		var direction := Vector2(source.facing, -0.35).normalized()
		for target in fighters:
			if target == source or target.life_state != Fighter.LifeState.ACTIVE:
				continue
			var offset := target.position - source.position
			if offset.x * source.facing >= 0.0 and absf(offset.x) <= attack.reach and absf(offset.y) <= 52.0:
				hits.append({"target": target, "direction": direction})
	for hit in hits:
		hit.target.receive_hit(attack, hit.direction)

func _resolve_result() -> void:
	var survivors: Array[Fighter] = []
	for fighter in fighters:
		if fighter.stocks > 0:
			survivors.append(fighter)
	if survivors.size() > 1:
		return
	ended = true
	var winner_id := survivors[0].player_id if survivors.size() == 1 else 0
	result = "P%d WINS — R: Restart" % winner_id if winner_id > 0 else "DRAW — R: Restart"
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
	var lines := PackedStringArray(["P1: A/D move · W jump · J attack    |    P2: ←/→ move · ↑ jump · K attack    |    R restart"])
	for fighter in fighters:
		var status := ""
		if fighter.life_state == Fighter.LifeState.WAITING:
			status = "Respawn %.1fs" % fighter.respawn_left
		elif fighter.life_state == Fighter.LifeState.ELIMINATED:
			status = "Eliminated"
		elif fighter.invulnerability_left > 0.0:
			status = "Invulnerable %.1fs" % fighter.invulnerability_left
		lines.append("P%d    Stocks %d    %.0f%%    %s" % [fighter.player_id, fighter.stocks, fighter.percent, status])
	if ended:
		lines.append(result)
	hud.text = "\n".join(lines)

func _draw() -> void:
	draw_rect(screen_bounds, Color("101927"))
	for surface in platforms:
		draw_rect(surface, Color("637890"))
		draw_line(surface.position, Vector2(surface.end.x, surface.position.y), Color("c5d6e7"), 3.0)
