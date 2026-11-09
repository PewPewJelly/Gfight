extends SceneTree
## Move timing, per-character bodies and art, projectiles, kits, and the character validator.

const TICK := 1.0 / 60.0
const FLOOR_Y := 540.0
const SIDE_ATTACK := Fighter.INPUT_RIGHT | Fighter.INPUT_ATTACK

class SplitShot extends ProjectileBehavior:
	@export var piece: ProjectileData

	func on_expire(shot: Projectile, stage: FightArena) -> void:
		var shooter := stage.fighter_by_id(shot.owner_id)
		stage.spawn_projectile(piece, shooter, shot.position, Vector2(100, 0))
		stage.spawn_projectile(piece, shooter, shot.position, Vector2(-100, 0))

class ComboKit extends CharacterKit:
	@export var first: AttackData
	@export var second: AttackData
	@export var finisher: SkillData

	func initial_state() -> Dictionary:
		return {"step": 0, "frozen": false}

	func choose_move(fighter: Fighter, slot: CharacterDef.Slot, is_skill: bool, move: AttackData) -> AttackData:
		if is_skill or slot != CharacterDef.Slot.SIDE:
			return move
		var step: int = fighter.kit_state.step
		fighter.kit_state.step = (step + 1) % 2
		return second if step == 1 else first

	func handle_press(fighter: Fighter, _mask: int, attack_pressed: bool, skill_pressed: bool, _airborne: bool) -> bool:
		if attack_pressed and skill_pressed:
			fighter.start_move(finisher)
			return true
		return false

	func body_frozen(fighter: Fighter) -> bool:
		return fighter.kit_state.frozen

	func on_hit_taken(fighter: Fighter, _hit: HitData) -> void:
		fighter.kit_state.frozen = false

class LeakyKit extends CharacterKit:
	var counter: int = 0

var failures: int = 0
var inputs: Dictionary = {}
var arena: FightArena
var player: Fighter
var other: Fighter
var base: CharacterDef

func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error(description)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	arena = preload("res://arena.tscn").instantiate()
	arena.standalone = false
	arena.simulation_seed = 7
	arena.rules = arena.rules.duplicate()
	arena.participant_ids.assign([1, 2])
	arena.input_provider = func(id: int) -> int: return int(inputs.get(id, 0))
	root.add_child(arena)
	arena.set_physics_process(false)
	arena.countdown_left = 0.0
	for _frame in range(3):
		await physics_frame
	player = arena.fighters[0]
	other = arena.fighters[1]
	base = arena.catalog.character(&"test_fighter")
	test_default_timing()
	test_move_timing()
	test_interrupted_move()
	test_move_lock_and_facing()
	test_cooldown_override()
	test_body_size()
	test_looks()
	test_projectile_flight_and_hit()
	test_projectile_limits()
	test_projectile_pierce_and_terrain()
	test_launch_trigger()
	test_behaviors()
	test_reflection()
	test_projectile_rollback()
	test_kit()
	test_validator()
	print("Character framework checks complete: %d failures" % failures)
	quit(1 if failures > 0 else 0)

func tick(player_mask: int = 0, other_mask: int = 0) -> void:
	inputs[1] = player_mask
	inputs[2] = other_mask
	arena.simulate_tick(TICK)

func ticks(count: int) -> void:
	for _i in range(count):
		tick()

func place(fighter: Fighter, x: float) -> void:
	fighter.reset_round(Vector2(x, FLOOR_Y - fighter.half_size.y))

func setup(player_character: CharacterDef, player_x: float = 400.0, other_x: float = 450.0, other_character: CharacterDef = null) -> void:
	player.use_character(player_character)
	other.use_character(other_character if other_character != null else base)
	arena.projectiles.clear()
	place(player, player_x)
	place(other, other_x)

func character_with(side: AttackData) -> CharacterDef:
	var entry := CharacterDef.new()
	entry.id = &"framework_test"
	entry.display_name = "시험"
	entry.side_attack = side
	entry.up_attack = AttackData.new()
	entry.down_attack = AttackData.new()
	return entry

func shooter_of(projectile: ProjectileData, frame: int = 0, recovery: int = 0) -> CharacterDef:
	var move := AttackData.new()
	move.reach = 0.0
	move.cooldown_override = 0.0
	move.recovery_frames = recovery
	var spawn := ProjectileSpawn.new()
	spawn.projectile = projectile
	spawn.frame = frame
	spawn.offset = Vector2(30, 0)
	move.spawns.append(spawn)
	return character_with(move)

func test_default_timing() -> void:
	setup(base)
	tick(SIDE_ATTACK)
	check(other.percent == 12.0 and player.move_phase == Fighter.MovePhase.ACTIVE, "A move with default timing hits on the frame it starts")
	tick()
	check(player.move_phase == Fighter.MovePhase.NONE, "A move with default timing ends on the next tick")

func test_move_timing() -> void:
	var move := AttackData.new()
	move.percent_increase = 10.0
	move.startup_frames = 3
	move.active_frames = 4
	move.recovery_frames = 5
	setup(character_with(move))
	tick(SIDE_ATTACK)
	check(player.move_phase == Fighter.MovePhase.STARTUP and other.percent == 0.0, "Startup does not hit")
	ticks(2)
	check(other.percent == 0.0, "Still no hit on the last startup frame")
	tick()
	check(player.move_phase == Fighter.MovePhase.ACTIVE and other.percent == 10.0, "The hit area goes live after startup")
	ticks(3)
	check(player.move_phase == Fighter.MovePhase.ACTIVE and other.percent == 10.0, "Active frames hit each target once")
	tick()
	check(player.move_phase == Fighter.MovePhase.RECOVERY, "Recovery follows the active frames")
	player.attack_cooldown = 0.0
	tick(Fighter.INPUT_ATTACK)
	check(player.move_frame == 8, "A press during recovery does not start another move")
	ticks(4)
	check(player.move_phase == Fighter.MovePhase.NONE, "The move ends after recovery")

func test_interrupted_move() -> void:
	var move := AttackData.new()
	move.startup_frames = 5
	setup(character_with(move))
	tick(SIDE_ATTACK)
	check(player.receive_hit(AttackData.new(), Vector2.LEFT), "Fighter can be hit during startup")
	ticks(8)
	check(other.percent == 0.0 and player.move_phase == Fighter.MovePhase.NONE, "Getting hit cancels a move still in startup")

func test_move_lock_and_facing() -> void:
	var move := AttackData.new()
	move.startup_frames = 20
	move.move_lock = AttackData.MoveLock.ROOTED
	setup(character_with(move), 400.0, 900.0)
	tick(SIDE_ATTACK)
	var jumps := player.jumps_left
	for _i in range(4):
		tick(Fighter.INPUT_RIGHT)
	check(is_zero_approx(player.velocity.x), "A rooted move stops walking")
	tick(Fighter.INPUT_JUMP)
	check(player.jumps_left == jumps, "A rooted move blocks jumping")
	var free := AttackData.new()
	free.startup_frames = 20
	setup(character_with(free), 400.0, 900.0)
	tick(SIDE_ATTACK)
	tick(Fighter.INPUT_RIGHT)
	check(player.velocity.x > 0.0, "A free move keeps walking")
	tick(Fighter.INPUT_LEFT)
	check(is_equal_approx(player.facing, 1.0), "A running move keeps its facing")

func test_cooldown_override() -> void:
	var move := AttackData.new()
	move.cooldown_override = 0.1
	setup(character_with(move))
	tick(SIDE_ATTACK)
	check(is_equal_approx(player.attack_cooldown, 0.1), "A move can set its own cooldown")

func test_body_size() -> void:
	var big := character_with(AttackData.new())
	big.body_size = Vector2(80, 100)
	setup(big, 400.0, 480.0)
	check(player.half_size == Vector2(40, 50) and player.body_shape.size == Vector2(80, 100), "Characters set their own body size")
	check(is_equal_approx(player.ground_checker.target_position.y, 53.0), "The ground check follows the body height")
	ticks(2)
	check(player.grounded(), "A tall body stands on the floor")
	tick(SIDE_ATTACK)
	check(is_equal_approx(player.attack_box().position.x, 40.0), "Melee hit areas start at the character's own body edge")
	var spawn := arena._spawn_location(player)
	var on_surface := false
	for surface in arena.platforms:
		on_surface = on_surface or is_equal_approx(spawn.y + 50.0, surface.position.y)
	check(on_surface, "Spawns put a tall body's feet on a platform")
	setup(base, 400.0, 530.0, big)
	tick(SIDE_ATTACK)
	check(other.percent > 0.0, "Hits use the target's own body size")

func test_looks() -> void:
	var standing := PlaceholderTexture2D.new()
	var pose := PlaceholderTexture2D.new()
	var move := AttackData.new()
	move.active_frames = 4
	move.pose = pose
	var entry := character_with(move)
	entry.match_sprite = standing
	setup(entry, 400.0, 900.0)
	check(player.current_look() == standing, "The standing PNG is the default look")
	tick(SIDE_ATTACK)
	check(player.current_look() == pose, "A running move shows its pose")
	ticks(5)
	check(player.current_look() == standing, "The look returns after the move")
	setup(base)
	check(player.current_look() == null, "A character without PNG keeps the slot-colored box")

func test_projectile_flight_and_hit() -> void:
	var data := ProjectileData.new()
	data.speed = 600.0
	data.percent_increase = 15.0
	setup(shooter_of(data), 300.0, 700.0)
	tick(SIDE_ATTACK)
	check(arena.projectiles.size() == 1, "A move's trigger launches a projectile")
	check(is_equal_approx(arena.projectiles[0].position.x, 340.0), "A projectile starts at the offset and moves on the launch tick")
	for _i in range(60):
		if other.percent > 0.0:
			break
		tick()
	check(other.percent == 15.0 and arena.projectiles.is_empty(), "A hit applies the projectile's values and removes it")
	check(player.dealt_percent == 15.0 and other.last_attacker_id == player.player_id, "Projectile hits are credited to the shooter")
	check(other.velocity.x > 0.0, "Knockback follows the direction of travel")
	var short := ProjectileData.new()
	short.speed = 10.0
	short.lifetime_frames = 5
	setup(shooter_of(short), 300.0, 1000.0)
	tick(SIDE_ATTACK)
	ticks(3)
	check(arena.projectiles.size() == 1, "A projectile lives until its lifetime")
	ticks(2)
	check(arena.projectiles.is_empty(), "A projectile disappears when its lifetime ends")

func test_projectile_limits() -> void:
	var data := ProjectileData.new()
	data.speed = 0.0
	data.max_active = 1
	setup(shooter_of(data), 300.0, 1000.0)
	tick(SIDE_ATTACK)
	tick()
	tick(SIDE_ATTACK)
	check(arena.projectiles.size() == 1, "max_active limits one fighter's projectiles of a type")
	var free := ProjectileData.new()
	free.speed = 0.0
	setup(shooter_of(free), 300.0, 1000.0)
	arena.rules.max_projectiles = 1
	check(arena.spawn_projectile(free, player, Vector2(300, 300), Vector2.ZERO) != null, "Launches below the arena limit work")
	check(arena.spawn_projectile(free, player, Vector2(300, 300), Vector2.ZERO) == null, "Launches past the arena limit are dropped")
	arena.rules.max_projectiles = 40

func test_projectile_pierce_and_terrain() -> void:
	var data := ProjectileData.new()
	data.speed = 900.0
	data.after_hit = ProjectileData.AfterHit.PIERCE
	data.percent_increase = 5.0
	setup(shooter_of(data), 300.0, 450.0)
	tick(SIDE_ATTACK)
	ticks(30)
	check(other.percent == 5.0, "A piercing projectile hits a target once")
	check(arena.projectiles.size() == 1, "A piercing projectile keeps flying")
	var solid := ProjectileData.new()
	solid.hits_platforms = true
	setup(shooter_of(solid), 300.0, 1000.0)
	arena.spawn_projectile(solid, player, Vector2(300, 500), Vector2(0, 400))
	ticks(10)
	check(arena.projectiles.is_empty(), "A projectile set to hit platforms stops there")
	var endless := ProjectileData.new()
	endless.lifetime_frames = 0
	setup(shooter_of(endless), 300.0, 1000.0)
	arena.spawn_projectile(endless, player, Vector2(arena.blast_zone.end.x - 1.0, 300), Vector2(400, 0))
	ticks(2)
	check(arena.projectiles.is_empty(), "A projectile past the blast zone is removed")

func test_launch_trigger() -> void:
	var data := ProjectileData.new()
	data.speed = 100.0
	var entry := shooter_of(data, 2, 5)
	setup(entry, 300.0, 1000.0)
	tick(SIDE_ATTACK)
	tick()
	check(arena.projectiles.is_empty(), "A trigger waits for its frame")
	tick()
	check(arena.projectiles.size() == 1, "A trigger fires on its frame")
	var fan := entry.side_attack.spawns[0]
	fan.frame = 0
	fan.count = 3
	fan.spread_degrees = 40.0
	setup(entry, 300.0, 1000.0)
	tick(SIDE_ATTACK)
	check(arena.projectiles.size() == 3, "A trigger can launch several projectiles")
	var angles: Array[float] = []
	for shot in arena.projectiles:
		angles.append(rad_to_deg(shot.velocity.angle()))
	check(is_equal_approx(angles[0], -20.0) and is_zero_approx(snappedf(angles[1], 0.001)) and is_equal_approx(angles[2], 20.0), "Spread fans projectiles evenly (%s)" % [angles])

func test_behaviors() -> void:
	var arc := BasicShot.new()
	arc.gravity = 980.0
	var falling := ProjectileData.new()
	falling.behavior = arc
	setup(shooter_of(falling), 300.0, 1000.0)
	var shot := arena.spawn_projectile(falling, player, Vector2(300, 100), Vector2(100, 0))
	ticks(10)
	check(shot.velocity.y > 150.0, "BasicShot gravity pulls the projectile down")
	var slowing := BasicShot.new()
	slowing.deceleration = 6000.0
	slowing.vanish_when_stopped = true
	var stopper := ProjectileData.new()
	stopper.behavior = slowing
	setup(shooter_of(stopper), 300.0, 1000.0)
	arena.spawn_projectile(stopper, player, Vector2(300, 100), Vector2(100, 0))
	ticks(2)
	check(arena.projectiles.is_empty(), "BasicShot can vanish once it has stopped")

	var seeker := ProjectileData.new()
	seeker.behavior = HomingShot.new()
	seeker.speed = 400.0
	setup(shooter_of(seeker), 300.0, 700.0)
	shot = arena.spawn_projectile(seeker, player, Vector2(300, 300), Vector2(0, -400))
	ticks(30)
	check(shot.velocity.x > 100.0 and shot.velocity.y > -100.0, "HomingShot turns toward the opponent")

	var boomerang := ProjectileData.new()
	var returning := BoomerangShot.new()
	returning.outbound_frames = 20
	boomerang.behavior = returning
	boomerang.speed = 600.0
	boomerang.after_hit = ProjectileData.AfterHit.PIERCE
	boomerang.lifetime_frames = 0
	boomerang.percent_increase = 5.0
	setup(shooter_of(boomerang), 300.0, 400.0)
	shot = arena.spawn_projectile(boomerang, player, Vector2(340, 514), Vector2(600, 0))
	ticks(10)
	check(other.percent == 5.0, "A boomerang hits on the way out")
	place(other, 1000.0)
	ticks(12)
	place(other, 400.0)
	var turned_back := false
	for _i in range(40):
		tick()
		turned_back = turned_back or shot.velocity.x < 0.0
	check(turned_back and other.percent == 5.0, "A boomerang hits again on the way back")
	check(arena.projectiles.is_empty(), "A boomerang disappears when it returns")

	var swing := ProjectileData.new()
	var sweep := FollowOwnerShot.new()
	swing.behavior = sweep
	swing.speed = 0.0
	swing.lifetime_frames = 30
	setup(shooter_of(swing), 400.0, 1000.0)
	shot = arena.spawn_projectile(swing, player, player.position, Vector2.ZERO)
	tick()
	var first := shot.position
	check(is_equal_approx(first.distance_to(player.position), sweep.radius), "FollowOwnerShot stays at its radius")
	ticks(10)
	check(shot.position.y > first.y, "FollowOwnerShot sweeps along its arc")
	check(player.receive_hit(AttackData.new(), Vector2.LEFT), "The holder can be hit mid-swing")
	tick()
	check(arena.projectiles.is_empty(), "Getting hit ends a FollowOwnerShot")

	var piece := ProjectileData.new()
	piece.speed = 100.0
	var splitting := SplitShot.new()
	splitting.piece = piece
	var parent := ProjectileData.new()
	parent.behavior = splitting
	parent.lifetime_frames = 2
	parent.speed = 0.0
	setup(shooter_of(parent), 300.0, 1000.0)
	check(arena.projectile_types.has(piece), "A projectile exported by a behavior is registered")
	arena.spawn_projectile(parent, player, Vector2(300, 300), Vector2.ZERO)
	ticks(2)
	check(arena.projectiles.size() == 2 and arena.projectiles[0].data == piece, "A behavior can launch new projectiles when it expires")

func test_reflection() -> void:
	var data := ProjectileData.new()
	data.speed = 600.0
	data.percent_increase = 9.0
	var mirror := AttackData.new()
	mirror.reflects_projectiles = true
	mirror.reach = 80.0
	mirror.width = 70.0
	setup(shooter_of(data), 300.0, 500.0, character_with(mirror))
	var shot := arena.spawn_projectile(data, player, Vector2(440, 514), Vector2(600, 0))
	tick(0, Fighter.INPUT_LEFT | Fighter.INPUT_ATTACK)
	check(shot.owner_id == other.player_id and shot.velocity.x < 0.0, "A reflecting move turns the projectile back and takes it over")
	for _i in range(30):
		if player.percent > 0.0:
			break
		tick()
	check(player.percent == 9.0 and other.dealt_percent == 9.0, "A reflected projectile hits its original shooter")

func test_projectile_rollback() -> void:
	var data := ProjectileData.new()
	data.speed = 200.0
	setup(shooter_of(data), 300.0, 1000.0)
	tick(SIDE_ATTACK)
	var saved := arena.snapshot().duplicate(true)
	var position_then := arena.projectiles[0].position
	ticks(5)
	arena.spawn_projectile(data, player, Vector2(500, 300), Vector2.ZERO)
	arena.restore_snapshot(saved)
	check(arena.projectiles.size() == 1 and arena.projectiles[0].position == position_then and arena.projectiles[0].data == data, "Rollback restores the projectile list")

func test_kit() -> void:
	var kit := ComboKit.new()
	kit.first = AttackData.new()
	kit.first.percent_increase = 1.0
	kit.second = AttackData.new()
	kit.second.percent_increase = 2.0
	kit.finisher = SkillData.new()
	kit.finisher.percent_increase = 30.0
	var entry := character_with(AttackData.new())
	entry.kit = kit
	setup(entry, 400.0, 450.0)
	check(player.moves.has(kit.finisher), "Moves exported by a kit can be looked up")
	tick(SIDE_ATTACK)
	check(player.active_move == kit.first, "A kit can pick the move for a press")
	player.attack_cooldown = 0.0
	tick()
	tick(SIDE_ATTACK)
	check(player.active_move == kit.second, "A kit can step through a combo")
	var saved := arena.snapshot().duplicate(true)
	player.attack_cooldown = 0.0
	tick()
	tick(SIDE_ATTACK)
	check(int(player.kit_state.step) == 1, "The combo counter advanced")
	arena.restore_snapshot(saved)
	check(int(player.kit_state.step) == 0 and player.active_move == kit.second, "Rollback restores kit state and the running move")
	setup(entry, 400.0, 450.0)
	tick(Fighter.INPUT_RIGHT | Fighter.INPUT_ATTACK | Fighter.INPUT_SKILL)
	check(player.active_move == kit.finisher and other.percent == 30.0, "A kit can take over a press and start its own move")
	setup(entry, 400.0, 900.0)
	player.reset_round(Vector2(400, 300))
	player.kit_state.frozen = true
	ticks(10)
	check(is_equal_approx(player.position.y, 300.0) and player.velocity == Vector2.ZERO, "A kit can hold the body in place")
	check(player.receive_hit(AttackData.new(), Vector2.LEFT) and not player.kit_state.frozen, "A kit reacts to being hit")
	tick()
	check(player.velocity.x < 0.0, "A frozen fighter is knocked away")
	player.kit_state.step = 1
	check(player.ring_out() and int(player.kit_state.step) == 0, "Kit state resets on ring-out")

func has_problem(entry: CharacterDef, text: String) -> bool:
	for problem in CharacterValidator.problems(entry):
		if problem.contains(text):
			return true
	return false

func test_validator() -> void:
	check(CharacterValidator.problems(base).is_empty(), "The test fighter passes validation")
	var entry := character_with(AttackData.new())
	entry.id = &"Bad Id"
	check(has_problem(entry, "소문자"), "A bad id is reported")
	entry.id = &"framework_test"
	check(has_problem(entry, "그림"), "Missing art is reported")
	entry.side_attack = null
	check(has_problem(entry, "SIDE"), "An empty required slot is reported")
	var late := ProjectileData.new()
	var shooter := shooter_of(late, 5)
	check(has_problem(shooter, "발사 프레임"), "A trigger outside the move is reported")
	var leaky := character_with(AttackData.new())
	leaky.kit = LeakyKit.new()
	check(has_problem(leaky, "counter"), "A kit with a plain member variable is reported")
