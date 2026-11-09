extends SceneTree
## Every character in the catalog must pass this. It checks the character's data, then plays a
## four-way mirror match with random inputs, rewinds to a saved tick, replays the same inputs
## and requires the exact same state. A kit or behavior that keeps state outside kit_state or
## Projectile.vars fails here.

const TICK := 1.0 / 60.0
const SAVE_TICK := 180
const END_TICK := 420
const PLAYERS: Array[int] = [1, 2, 3, 4]

## Exercises the parts the shipped characters may not use yet.
class GimmickKit extends CharacterKit:
	@export var charged_shot: SkillData

	func initial_state() -> Dictionary:
		return {"charge": 0.0, "hits": 0, "held": Vector2.ZERO}

	func tick(fighter: Fighter, delta: float) -> void:
		fighter.kit_state.charge = float(fighter.kit_state.charge) + delta
		fighter.kit_state.held = fighter.position

	func handle_press(fighter: Fighter, _mask: int, attack_pressed: bool, skill_pressed: bool, _airborne: bool) -> bool:
		if attack_pressed and skill_pressed and float(fighter.kit_state.charge) > 1.0:
			fighter.kit_state.charge = 0.0
			fighter.start_move(charged_shot)
			return true
		return false

	func on_hit_dealt(fighter: Fighter, _target: Fighter, _hit: HitData) -> void:
		fighter.kit_state.hits = int(fighter.kit_state.hits) + 1

var failures: int = 0
var saw_projectile: bool = false

func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error(description)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var catalog: ContentCatalog = load("res://resources/content_catalog.tres")
	var ids: Array[StringName] = []
	for entry in catalog.characters:
		check(not ids.has(entry.id), "Duplicate character id %s" % entry.id)
		ids.append(entry.id)
		for problem in CharacterValidator.problems(entry):
			check(false, "%s: %s" % [entry.id, problem])
		await check_replay(entry)
	saw_projectile = false
	await check_replay(gimmick_character())
	check(saw_projectile, "The gimmick character launched projectiles during the replay")
	print("Character contract checks complete: %d failures" % failures)
	quit(1 if failures > 0 else 0)

func check_replay(entry: CharacterDef) -> void:
	var only_entry := ContentCatalog.new()
	only_entry.characters.append(entry)
	var inputs := random_inputs()
	var arena: FightArena = preload("res://arena.tscn").instantiate()
	arena.standalone = false
	arena.simulation_seed = 99
	arena.starting_stocks = 99
	arena.catalog = only_entry
	arena.participant_ids.assign(PLAYERS)
	arena.input_provider = func(id: int) -> int: return int(inputs[arena.frame][id - 1])
	root.add_child(arena)
	arena.set_physics_process(false)
	arena.countdown_left = 0.0
	for _frame in range(3):
		await physics_frame
	var saved: Dictionary
	while arena.frame < END_TICK:
		arena.simulate_tick(TICK)
		saw_projectile = saw_projectile or not arena.projectiles.is_empty()
		if arena.frame == SAVE_TICK:
			saved = arena.snapshot().duplicate(true)
	var first := arena.snapshot().duplicate(true)
	arena.restore_snapshot(saved)
	while arena.frame < END_TICK:
		arena.simulate_tick(TICK)
	var second := arena.snapshot().duplicate(true)
	var difference := first_difference(first, second, "state")
	check(difference.is_empty(), "%s does not replay the same: %s" % [entry.id, difference])
	check(not holds_object(saved), "%s: a snapshot holds an object, which cannot cross the network" % entry.id)
	var session: Node = root.get_node("Session")
	check(session._rollback_state_hash(first) == session._rollback_state_hash(second), "%s: state hashes differ after replay" % entry.id)
	arena.queue_free()
	await process_frame

## Each player holds a random mask for a few ticks, so presses and releases both happen.
func random_inputs() -> Array[Array]:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261109
	var table: Array[Array] = []
	var held: Array[int] = [0, 0, 0, 0]
	var left: Array[int] = [0, 0, 0, 0]
	for _tick in range(END_TICK + 1):
		for index in range(PLAYERS.size()):
			if left[index] <= 0:
				held[index] = rng.randi() & Fighter.INPUT_ALL
				left[index] = rng.randi_range(2, 12)
			left[index] -= 1
		table.append(held.duplicate())
	return table

func first_difference(a: Variant, b: Variant, path: String) -> String:
	if a is Dictionary and b is Dictionary:
		for key: Variant in a:
			if not b.has(key):
				return "%s.%s is missing" % [path, key]
			var inner := first_difference(a[key], b[key], "%s.%s" % [path, key])
			if not inner.is_empty():
				return inner
		return "" if a.size() == b.size() else "%s has different keys" % path
	if a is Array and b is Array:
		if a.size() != b.size():
			return "%s has %d items, then %d" % [path, a.size(), b.size()]
		for index in range(a.size()):
			var inner := first_difference(a[index], b[index], "%s[%d]" % [path, index])
			if not inner.is_empty():
				return inner
		return ""
	return "" if a == b else "%s was %s, then %s" % [path, a, b]

func holds_object(value: Variant) -> bool:
	if value is Object:
		return true
	if value is Dictionary:
		for key: Variant in value:
			if holds_object(key) or holds_object(value[key]):
				return true
	elif value is Array:
		for item: Variant in value:
			if holds_object(item):
				return true
	return false

func projectile_with(behavior: ProjectileBehavior) -> ProjectileData:
	var data := ProjectileData.new()
	data.behavior = behavior
	data.speed = 350.0
	data.lifetime_frames = 50
	data.after_hit = ProjectileData.AfterHit.PIERCE
	return data

func spawn_of(projectile: ProjectileData, frame: int) -> ProjectileSpawn:
	var spawn := ProjectileSpawn.new()
	spawn.projectile = projectile
	spawn.frame = frame
	return spawn

func gimmick_character() -> CharacterDef:
	var arc := BasicShot.new()
	arc.gravity = 600.0
	var homing := HomingShot.new()
	var boomerang := BoomerangShot.new()
	var sweep := FollowOwnerShot.new()
	var lobbed := projectile_with(arc)
	lobbed.hits_platforms = true
	var entry := CharacterDef.new()
	entry.id = &"contract_gimmick"
	entry.display_name = "계약 시험"
	entry.body_size = Vector2(44, 64)
	entry.side_attack = AttackData.new()
	entry.side_attack.startup_frames = 4
	entry.side_attack.active_frames = 6
	entry.side_attack.recovery_frames = 8
	entry.side_attack.cooldown_override = 0.1
	entry.side_attack.spawns.append(spawn_of(projectile_with(sweep), 2))
	entry.up_attack = AttackData.new()
	entry.up_attack.reflects_projectiles = true
	entry.up_attack.active_frames = 5
	entry.up_attack.cooldown_override = 0.1
	entry.down_attack = AttackData.new()
	entry.down_attack.move_lock = AttackData.MoveLock.ROOTED
	entry.down_attack.recovery_frames = 10
	entry.down_attack.cooldown_override = 0.1
	entry.side_skill = SkillData.new()
	entry.side_skill.reach = 0.0
	entry.side_skill.cooldown = 0.3
	entry.side_skill.spawns.append(spawn_of(projectile_with(homing), 0))
	entry.up_skill = SkillData.new()
	entry.up_skill.reach = 0.0
	entry.up_skill.cooldown = 0.3
	entry.up_skill.self_velocity = Vector2(120, -300)
	var fan := spawn_of(lobbed, 0)
	fan.count = 3
	fan.spread_degrees = 50.0
	entry.up_skill.spawns.append(fan)
	entry.down_skill = SkillData.new()
	entry.down_skill.reach = 0.0
	entry.down_skill.cooldown = 0.3
	entry.down_skill.spawns.append(spawn_of(projectile_with(boomerang), 0))
	var kit := GimmickKit.new()
	kit.charged_shot = SkillData.new()
	kit.charged_shot.cooldown = 0.2
	kit.charged_shot.startup_frames = 3
	kit.charged_shot.spawns.append(spawn_of(projectile_with(homing), 3))
	entry.kit = kit
	return entry
