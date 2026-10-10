extends SceneTree

var failures: int = 0

func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error(description)

func _initialize() -> void:
	call_deferred("run")

func frames(count: int) -> void:
	for index in range(count):
		await physics_frame
		await process_frame

func run() -> void:
	var session = root.get_node("Session")
	var main = load("res://main.tscn").instantiate()
	main.result_delay = 0.0
	root.add_child(main)
	check(main.menu.visible and not main.lobby.visible, "Game opens on menu")
	session.roster = {1: "One"}
	session.phase = "lobby"
	check(not session.start_game(), "One participant cannot start")
	session.local_game()
	check(main.lobby.visible and session.can_start(), "Local lobby has independent participants")
	check(session.start_game(), "Two participants start")
	await frames(3)
	check(session.input_for(1) == 0 and session.input_for(2) == 0, "Local keyboard bindings return valid input masks")
	var arena: FightArena = session.arena
	arena.set_physics_process(false)
	var player := arena.fighters[0]
	var other := arena.fighters[1]
	await frames(3)
	check(player.grounded() and other.grounded(), "Distinct platform start contact via GroundChecker")
	check(player.position != other.position and player.stocks == 3 and other.stocks == 3, "Distinct start positions and stocks")
	player.simulate(1.0 / 60.0, 4)
	check(player.jumps_left == 1 and player.velocity.y < 0, "First jump consumes one opportunity")
	player.simulate(1.0 / 60.0, 0)
	player.simulate(1.0 / 60.0, 4)
	check(player.jumps_left == 0, "Second jump consumes last opportunity")
	player.simulate(1.0 / 60.0, 0)
	var before_y := player.velocity.y
	player.simulate(1.0 / 60.0, 4)
	check(player.jumps_left == 0 and player.velocity.y > before_y, "Third jump is blocked")
	player.hitstun_left = 0.3
	player.jumps_left = 1
	player.velocity = Vector2(400, -100)
	player.jump_was_down = false
	player.attack_was_down = false
	player.simulate(1.0 / 60.0, 1 | 4 | 16)
	check(player.velocity.x == 400 and player.jumps_left == 1 and not player.attack_requested, "Knockback blocks movement/jump/attack without spending jump")
	player.reset_round(Vector2(320, 334))
	await frames(3)
	check(player.grounded(), "Reset restores ground contact")
	player.simulate(1.0 / 60.0, 8)
	check(player.drop_left > 0.0 and not player.grounded(), "S starts drop-through on upper platform")
	for index in range(30):
		player.simulate(1.0 / 60.0, 0)
		await frames(1)
	check(player.position.y > 400.0, "Player actually traverses one-way platform")
	for index in range(40):
		player.simulate(1.0 / 60.0, 0)
		await frames(1)
	check(player.grounded() and player.jumps_left == 2, "Landing replenishes both jumps")
	player.simulate(1.0 / 60.0, 8)
	check(player.drop_left == 0.0, "Solid bottom ground cannot be dropped through")
	# Attack selection, differing hitboxes, misses and immunity.
	player.reset_round(Vector2(400, 250))
	other.reset_round(Vector2(455, 250))
	player.simulate(1.0 / 60.0, 16)
	check(player.attack_requested and player.attack_kind == "forward", "J selects forward attack")
	arena._resolve_attacks()
	check(other.percent == 12.0 and player.percent == 0.0, "Only hit victim gains percent")
	player.reset_round(Vector2(400, 300))
	other.reset_round(Vector2(400, 220))
	player.simulate(1.0 / 60.0, 4 | 16)
	check(player.attack_kind == "up", "W+J selects upward attack")
	arena._resolve_attacks()
	check(other.percent == 10.0 and other.velocity.y < 0.0, "Upward hit uses own growth and direction")
	player.reset_round(Vector2(400, 250))
	other.reset_round(Vector2(400, 330))
	player.simulate(1.0 / 60.0, 8 | 16)
	check(player.attack_kind == "down", "S+J selects downward attack")
	arena._resolve_attacks()
	check(other.percent == 15.0 and other.velocity.y > 0.0, "Downward hit uses own growth and direction")
	player.reset_round(Vector2(400, 250))
	other.reset_round(Vector2(800, 250))
	player.simulate(1.0 / 60.0, 16)
	arena._resolve_attacks()
	check(other.percent == 0.0, "Miss has no effect")
	player.reset_round(Vector2(400, 514))
	other.reset_round(Vector2(440, 514))
	await frames(3)
	for index in range(60):
		player.simulate(1.0 / 60.0, 2)
		other.simulate(1.0 / 60.0, 1)
		await frames(1)
	check(absf(player.position.x - other.position.x) >= Fighter.HALF_SIZE.x * 2.0 - 0.1, "Opposing movement does not overlap fighters")
	# Landing on another fighter slides off sideways; nobody can stand on a head.
	for offset in [6.0, 0.0]:
		other.reset_round(Vector2(640, 514))
		player.reset_round(Vector2(640 + offset, 400))
		await frames(2)
		var touched_head := false
		for index in range(90):
			player.simulate(1.0 / 60.0, 0)
			other.simulate(1.0 / 60.0, 0)
			if absf(player.position.x - other.position.x) < Fighter.HALF_SIZE.x * 2.0 and player.position.y < other.position.y - Fighter.HALF_SIZE.y:
				touched_head = true
			await frames(1)
		check(touched_head, "Stomp test actually lands on the other head (offset %.0f)" % offset)
		check(absf(player.position.x - other.position.x) >= Fighter.HALF_SIZE.x * 2.0 - 0.5, "Stomping fighter slid off to the side (offset %.0f)" % offset)
		check(player.grounded() and absf(player.position.y - other.position.y) < 1.0, "Stomping fighter ends on the floor, not on the head (offset %.0f: %s vs %s)" % [offset, player.position, other.position])
	player.reset_round(Vector2(600, 514))
	other.reset_round(Vector2(640, 514))
	await frames(2)
	# Inactive fighters must not leave invisible colliders behind.
	var vacated_x := other.position.x
	other.ring_out()
	check(other.collision_layer == 0 and other.collision_mask == 0, "Waiting fighter collider disabled")
	other.simulate(1.0 / 60.0, 4 | 16)
	other.respawn(Vector2(900, 200))
	other.simulate(1.0 / 60.0, 4 | 16)
	check(other.jumps_left == 2 and not other.attack_requested, "Held remote keys do not become fresh presses on respawn")
	other.ring_out()
	for index in range(80):
		player.simulate(1.0 / 60.0, 2)
		await frames(1)
	check(player.position.x > vacated_x + Fighter.HALF_SIZE.x, "Movement passes vacated position (%s vs %.0f)" % [player.position, vacated_x])
	# Server snapshots reproduce all shared combat state on a rendering-only arena.
	var replica := preload("res://arena.tscn").instantiate() as FightArena
	replica.authoritative = false
	replica.standalone = false
	root.add_child(replica)
	replica.apply_snapshot(arena.snapshot())
	check(replica.fighters[0].position == player.position and replica.fighters[1].stocks == other.stocks, "Snapshot copies positions and stocks")
	check(replica.fighters[1].life_state == other.life_state and not replica.fighters[1].visible, "Snapshot copies waiting lifecycle")
	replica.queue_free()
	other.stocks = 0
	arena._resolve_result()
	await frames(2)
	check(session.phase == "result" and main.result_panel.visible, "Victory opens result panel")
	session.return_to_lobby()
	check(session.phase == "lobby" and main.lobby.visible, "Host can return to lobby")
	check(session.start_game(), "Rematch starts")
	check(session.arena.fighters[0].stocks == 3 and session.arena.fighters[1].percent == 0.0, "Rematch resets stocks and percent")
	session.leave()
	session.local_game()
	session.roster = {1: "P1", 2: "P2", 3: "P3", 4: "P4"}
	check(session.start_game(), "Four-person roster starts")
	session.arena.set_physics_process(false)
	await frames(3)
	for index in range(4):
		var current: Fighter = session.arena.fighters[index]
		check(current.grounded(), "Every four-player start touches platform")
		for next in range(index + 1, 4):
			var neighbor: Fighter = session.arena.fighters[next]
			check(not Rect2(current.position - Fighter.HALF_SIZE, Fighter.HALF_SIZE * 2.0).intersects(Rect2(neighbor.position - Fighter.HALF_SIZE, Fighter.HALF_SIZE * 2.0)), "Four-player starts do not overlap")
	session.leave()
	check(main.menu.visible and session.arena == null, "Leave clears arena and returns to menu")
	print("Gameplay checks complete: %d failures" % failures)
	quit(1 if failures > 0 else 0)
