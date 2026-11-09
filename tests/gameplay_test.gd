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
	check(session.phase == session.Phase.MENU and session.arena == null, "Game opens outside any room")
	session._open_room(ScreenTypes.RoomMode.ONLINE, "")
	check(not session.start_game(), "One participant cannot start")
	session.local_game()
	check(session.phase == session.Phase.LOBBY and session.can_start(), "Local lobby has independent participants")
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
	player.simulate(1.0 / 60.0, Fighter.INPUT_UP)
	check(player.jumps_left == 2 and player.velocity.y >= 0.0, "W is up, not jump")
	player.simulate(1.0 / 60.0, Fighter.INPUT_JUMP)
	check(player.jumps_left == 1 and player.velocity.y < 0, "First jump consumes one opportunity")
	player.simulate(1.0 / 60.0, 0)
	player.simulate(1.0 / 60.0, Fighter.INPUT_JUMP)
	check(player.jumps_left == 0, "Second jump consumes last opportunity")
	player.simulate(1.0 / 60.0, 0)
	var before_y := player.velocity.y
	player.simulate(1.0 / 60.0, Fighter.INPUT_JUMP)
	check(player.jumps_left == 0 and player.velocity.y > before_y, "Third jump is blocked")
	player.hitstun_left = 0.3
	player.jumps_left = 1
	player.velocity = Vector2(400, -100)
	player.jump_was_down = false
	player.attack_was_down = false
	player.simulate(1.0 / 60.0, Fighter.INPUT_LEFT | Fighter.INPUT_JUMP | Fighter.INPUT_ATTACK)
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
	# Move slots (Docs/gdd/characters/character-template.md §6): input rules without physics.
	check(Fighter.move_slot(0, false) == CharacterDef.Slot.UP and Fighter.move_slot(Fighter.INPUT_UP, false) == CharacterDef.Slot.UP, "No direction and up share the up/neutral slot on the ground")
	check(Fighter.move_slot(0, true) == CharacterDef.Slot.AIR_UP and Fighter.move_slot(Fighter.INPUT_UP, true) == CharacterDef.Slot.AIR_UP, "No direction and up share the air-up slot in the air")
	check(Fighter.move_slot(Fighter.INPUT_JUMP, false) == CharacterDef.Slot.UP, "The jump key does not aim")
	check(Fighter.move_slot(Fighter.INPUT_RIGHT, false) == CharacterDef.Slot.SIDE and Fighter.move_slot(Fighter.INPUT_LEFT, true) == CharacterDef.Slot.SIDE, "Side is one slot on the ground and in the air")
	check(Fighter.move_slot(Fighter.INPUT_DOWN, false) == CharacterDef.Slot.DOWN and Fighter.move_slot(Fighter.INPUT_DOWN, true) == CharacterDef.Slot.AIR_DOWN, "Down splits into ground and air slots")
	check(Fighter.move_slot(Fighter.INPUT_UP | Fighter.INPUT_DOWN | Fighter.INPUT_RIGHT, true) == CharacterDef.Slot.AIR_UP and Fighter.move_slot(Fighter.INPUT_DOWN | Fighter.INPUT_RIGHT, false) == CharacterDef.Slot.DOWN, "Up beats down beats side")
	check(player.character.id == &"test_fighter" and player.movement == player.character.movement, "Fighters use their catalog character's values")
	# Attack selection, differing hitboxes, misses and immunity.
	player.reset_round(Vector2(400, 250))
	other.reset_round(Vector2(455, 250))
	player.simulate(1.0 / 60.0, Fighter.INPUT_RIGHT | Fighter.INPUT_ATTACK)
	check(player.attack_requested and player.attack_slot == CharacterDef.Slot.SIDE, "D+J selects the side attack")
	arena._resolve_attacks()
	check(other.percent == 12.0 and player.percent == 0.0, "Only hit victim gains percent")
	player.reset_round(Vector2(400, 514))
	other.reset_round(Vector2(455, 514))
	await frames(2)
	player.facing = 1.0
	player.simulate(1.0 / 60.0, Fighter.INPUT_ATTACK)
	check(player.attack_slot == CharacterDef.Slot.UP and player.active_move == player.character.up_attack, "J alone on the ground selects the up/neutral attack")
	arena._resolve_attacks()
	check(other.percent == 12.0, "Test fighter's up/neutral attack is the old forward hit (temporary)")
	player.reset_round(Vector2(400, 514))
	other.reset_round(Vector2(800, 514))
	await frames(2)
	player.simulate(1.0 / 60.0, Fighter.INPUT_UP | Fighter.INPUT_ATTACK)
	check(player.jumps_left == 2 and player.attack_slot == CharacterDef.Slot.UP and player.active_move == player.character.up_attack, "W+J on the ground stays grounded and is the same move as J alone")
	player.reset_round(Vector2(400, 514))
	await frames(2)
	player.simulate(1.0 / 60.0, Fighter.INPUT_JUMP | Fighter.INPUT_ATTACK)
	check(player.jumps_left == 1 and player.attack_slot == CharacterDef.Slot.AIR_UP, "Jump and J on the same frame jump and use the air-up attack")
	player.reset_round(Vector2(400, 334))
	await frames(2)
	player.simulate(1.0 / 60.0, Fighter.INPUT_DOWN | Fighter.INPUT_ATTACK)
	check(player.attack_slot == CharacterDef.Slot.DOWN and player.drop_left == 0.0, "S+J on the ground selects the down attack without dropping through")
	player.reset_round(Vector2(400, 250))
	player.simulate(1.0 / 60.0, Fighter.INPUT_ATTACK)
	check(player.attack_slot == CharacterDef.Slot.AIR_UP, "J alone in the air selects the air-up attack")
	player.reset_round(Vector2(400, 300))
	other.reset_round(Vector2(400, 220))
	player.simulate(1.0 / 60.0, Fighter.INPUT_UP | Fighter.INPUT_ATTACK)
	check(player.attack_slot == CharacterDef.Slot.AIR_UP, "W+J in the air selects the air-up attack")
	arena._resolve_attacks()
	check(other.percent == 10.0 and other.velocity.y < 0.0, "Upward hit uses own growth and direction")
	player.reset_round(Vector2(400, 250))
	other.reset_round(Vector2(400, 330))
	player.simulate(1.0 / 60.0, Fighter.INPUT_DOWN | Fighter.INPUT_ATTACK)
	check(player.attack_slot == CharacterDef.Slot.AIR_DOWN, "S+J in the air selects the air-down attack")
	arena._resolve_attacks()
	check(other.percent == 15.0 and other.velocity.y > 0.0, "Downward hit uses own growth and direction")
	player.reset_round(Vector2(400, 250))
	other.reset_round(Vector2(800, 250))
	player.simulate(1.0 / 60.0, Fighter.INPUT_RIGHT | Fighter.INPUT_ATTACK)
	arena._resolve_attacks()
	check(other.percent == 0.0, "Miss has no effect")
	# Skills: same slots on the skill key, own cooldown, optional self movement.
	player.reset_round(Vector2(400, 250))
	player.simulate(1.0 / 60.0, Fighter.INPUT_SKILL)
	check(not player.attack_requested, "Skill key does nothing for a character without skills")
	var custom := CharacterDef.new()
	custom.id = &"skill_test"
	custom.side_attack = AttackData.new()
	custom.up_attack = AttackData.new()
	var dash := SkillData.new()
	dash.cooldown = 2.0
	dash.percent_increase = 20.0
	dash.self_velocity = Vector2(500, 0)
	custom.side_skill = dash
	var lift := SkillData.new()
	lift.reach = 0.0
	lift.self_velocity = Vector2(0, -600)
	custom.up_skill = lift
	player.use_character(custom)
	check(player.movement == Fighter.DEFAULT_MOVEMENT, "A character without movement values uses the default movement")
	player.reset_round(Vector2(400, 250))
	other.reset_round(Vector2(455, 250))
	player.simulate(1.0 / 60.0, Fighter.INPUT_RIGHT | Fighter.INPUT_SKILL)
	check(player.attack_requested and player.attack_is_skill and player.active_move == dash, "D+K starts the side skill")
	check(player.velocity.x > 400.0, "Skill moves its user toward the facing side")
	arena._resolve_attacks()
	check(other.percent == 20.0, "Skill hit uses the skill's own values")
	player.simulate(1.0 / 60.0, 0)
	player.attack_cooldown = 0.0
	player.simulate(1.0 / 60.0, Fighter.INPUT_RIGHT | Fighter.INPUT_SKILL)
	check(not player.attack_requested, "Skill cannot be used again while cooling down")
	player.reset_round(Vector2(400, 250))
	other.reset_round(Vector2(400, 170))
	player.simulate(1.0 / 60.0, Fighter.INPUT_SKILL)
	check(player.active_move == lift and player.velocity.y < -500.0, "Empty air-up skill reuses the up skill and lifts its user")
	arena._resolve_attacks()
	check(other.percent == 0.0, "A movement-only skill hits nobody")
	player.use_character(session.catalog.character(&"test_fighter"))
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
	other.simulate(1.0 / 60.0, Fighter.INPUT_JUMP | Fighter.INPUT_ATTACK)
	other.respawn(Vector2(900, 200))
	other.simulate(1.0 / 60.0, Fighter.INPUT_JUMP | Fighter.INPUT_ATTACK)
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
	check(session.phase == session.Phase.RESULT and session.match_result().winner_id == 1, "Victory opens the result with P1 as winner")
	session.return_to_lobby()
	check(session.phase == session.Phase.LOBBY and session.arena == null, "Host can return to lobby")
	check(session.start_game(), "Rematch starts")
	check(session.arena.fighters[0].stocks == 3 and session.arena.fighters[1].percent == 0.0, "Rematch resets stocks and percent")
	session.leave()
	session.local_game()
	for id in [3, 4]:
		session.room.add_player(PlayerData.create(id, "P%d" % id, session.catalog.default_character()))
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
	check(session.phase == session.Phase.MENU and session.arena == null, "Leave clears arena and returns to menu")
	print("Gameplay checks complete: %d failures" % failures)
	quit(1 if failures > 0 else 0)
