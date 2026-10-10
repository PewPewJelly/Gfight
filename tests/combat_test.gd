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
	# Blast lines sit past the two-jump recovery reach of the default movement.
	var screen := Rect2(0, 0, 1280, 720)
	var movement := MovementSettings.new()
	var reach := CombatRules.recovery_reach(movement)
	check(is_equal_approx(reach.x, movement.speed * 4.0 * movement.jump_speed / movement.gravity), "Recovery reach uses two full jumps of air time")
	check(is_equal_approx(reach.y, movement.jump_speed * movement.jump_speed / movement.gravity), "Recovery rise is two jump heights")
	var stage := Rect2(180, 360, 920, 210)
	var zone := rules.blast_zone(stage, 540.0, screen, movement)
	var margin := rules.blast_safety_margin
	check(is_equal_approx(zone.position.x, 180.0 - reach.x - margin) and is_equal_approx(zone.end.x, 1100.0 + reach.x + margin), "Side lines past recovery reach")
	check(is_equal_approx(zone.end.y, 540.0 + reach.y + margin) and is_equal_approx(zone.position.y, -rules.ring_out_margin), "Bottom line past recovery rise, top line above screen")
	check(not rules.is_outside(Vector2(zone.position.x + 1.0, 300), zone), "Inside blast lines")
	for point in [Vector2(zone.position.x, 300), Vector2(zone.end.x, 300), Vector2(500, zone.position.y), Vector2(500, zone.end.y)]:
		check(rules.is_outside(point, zone), "All four exact blast lines")
	check(not rules.is_outside(Vector2(1441, 300), zone), "Old screen-margin line no longer kills")
	# Simulated recovery: from just inside the side line, two jumps reach the stage edge.
	var x := 1100.0 + reach.x * 0.95
	var vy := -movement.jump_speed
	var y := 0.0
	var jumped_twice := false
	var t := 0.0
	while t < 5.0 and x > 1100.0:
		x -= movement.speed / 60.0
		vy += movement.gravity / 60.0
		y += vy / 60.0
		if y >= 0.0 and not jumped_twice:
			vy = -movement.jump_speed
			jumped_twice = true
		t += 1.0 / 60.0
	check(x <= 1100.0 and y <= 0.0, "Recoverable just inside the reach (x %.1f y %.1f t %.2f)" % [x, y, t])
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
	arena.fighters[1].position = Vector2(-1000, 0)
	arena._physics_process(0.01)
	check(arena.ended and arena.result.begins_with("P1 WINS"), "Last survivor wins")
	arena.restart()
	for player in arena.fighters:
		player.set_physics_process(false)
		player.stocks = 1
		player.position = Vector2(-1000, 0)
	arena._physics_process(0.01)
	check(arena.ended and arena.result.begins_with("DRAW"), "Simultaneous final exits draw")
	print("Combat checks complete: %d failures" % failures)
	quit(1 if failures > 0 else 0)
