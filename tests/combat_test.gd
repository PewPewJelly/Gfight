extends SceneTree

var failures: int = 0

func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error(description)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var rules := CombatRules.new()
	var attack := AttackData.new()
	var fighter := Fighter.new()
	fighter.rules = rules
	root.add_child(fighter)
	fighter.set_physics_process(false)
	fighter.reset_round(Vector2.ZERO)
	fighter.set_physics_process(false)
	check(fighter.stocks == 3 and fighter.percent == 0.0, "Initial stocks/percent")
	check(fighter.receive_hit(attack, Vector2.LEFT), "First attack accepted")
	var first_speed := fighter.velocity.length()
	check(fighter.percent == 12.0 and fighter.velocity.x < 0.0, "Attack increment and direction")
	fighter.receive_hit(attack, Vector2.LEFT)
	check(fighter.percent == 24.0 and fighter.velocity.length() > first_speed, "Cumulative scaling")
	check(fighter.ring_out(), "First exit accepted")
	check(not fighter.ring_out() and fighter.stocks == 2 and fighter.percent == 0.0, "Duplicate exit rejected/reset percent")
	check(fighter.velocity == Vector2.ZERO and fighter.hitstun_left == 0.0, "Exit clears motion/hitstun")
	check(not fighter.receive_hit(attack, Vector2.RIGHT), "Waiting fighter cannot be hit")
	check(fighter.respawn(Vector2(10, 20)), "Respawn succeeds")
	check(fighter.invulnerability_left == 3.0, "Three seconds of protection")
	check(not fighter.receive_hit(attack, Vector2.RIGHT) and not fighter.apply_external_impulse(Vector2.ONE), "Protection blocks damage and impulses")
	check(fighter.percent == 0.0 and fighter.damage_received == 0.0 and fighter.velocity == Vector2.ZERO, "Protection has no side effects")
	fighter._physics_process(3.01)
	check(fighter.receive_hit(attack, Vector2.UP), "Protection expires")
	fighter.ring_out()
	fighter.respawn(Vector2.ZERO)
	fighter.ring_out()
	check(fighter.stocks == 0 and fighter.life_state == Fighter.LifeState.ELIMINATED, "Last stock eliminates")
	check(not fighter.respawn(Vector2.ZERO) and not fighter.ring_out(), "Eliminated fighter cannot return or lose again")
	var screen := Rect2(0, 0, 1280, 720)
	check(not rules.is_outside(Vector2(-159, 20), screen), "Inside margin")
	for point in [Vector2(-160, 20), Vector2(1440, 20), Vector2(20, -160), Vector2(20, 880)]:
		check(rules.is_outside(point, screen), "All four exact exit thresholds")
	var arena = load("res://arena.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	for player in arena.fighters:
		player.set_physics_process(false)
	for iteration in range(100):
		var spawn: Vector2 = arena._spawn_location(arena.fighters[0])
		var on_surface := false
		for surface in arena.platforms:
			if is_equal_approx(spawn.y + Fighter.HALF_SIZE.y, surface.position.y) and spawn.x >= surface.position.x + Fighter.HALF_SIZE.x and spawn.x <= surface.end.x - Fighter.HALF_SIZE.x:
				on_surface = true
		check(on_surface, "Random respawn touches a platform")
	var delay: float = arena.rules.respawn_delay
	arena.fighters[0].ring_out()
	arena._physics_process(delay * 0.5)
	check(arena.fighters[0].life_state == Fighter.LifeState.WAITING, "Respawn waits configured delay")
	arena._physics_process(delay * 0.5 + 0.01)
	check(arena.fighters[0].life_state == Fighter.LifeState.ACTIVE, "Respawn after delay")
	arena.fighters[1].stocks = 1
	arena.fighters[1].position = Vector2(-200, 0)
	arena._physics_process(0.01)
	check(arena.ended and arena.result.begins_with("P1 WINS"), "Last survivor wins")
	arena.restart()
	for player in arena.fighters:
		player.set_physics_process(false)
		player.stocks = 1
		player.position = Vector2(-200, 0)
	arena._physics_process(0.01)
	check(arena.ended and arena.result.begins_with("DRAW"), "Simultaneous final exits draw")
	print("Combat checks complete: %d failures" % failures)
	quit(1 if failures > 0 else 0)
