extends SceneTree
## Deterministic four-Junbae stress battle using test-only input bots.

const MAX_TICKS: int = 36000
const STEP: float = 1.0 / 60.0

var arena: FightArena
var input_counts: Dictionary = {}
var attack_counts: Dictionary = {}
var special_counts: Dictionary = {}
var battle_seed: int = 1337

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="):
			battle_seed = int(argument.trim_prefix("--seed="))
	call_deferred("run")

func run() -> void:
	arena = preload("res://arena.tscn").instantiate() as FightArena
	arena.participant_ids.assign([1, 2, 3, 4])
	arena.character_picks = {1: &"junbae", 2: &"junbae", 3: &"junbae", 4: &"junbae"}
	arena.simulation_seed = battle_seed
	arena.standalone = false
	arena.input_provider = _bot_input
	root.add_child(arena)
	arena.set_physics_process(false)
	await process_frame
	for fighter: Fighter in arena.fighters:
		if fighter.character_id != &"junbae":
			push_error("P%d did not spawn as Junbae" % fighter.player_slot)
			quit(1)
			return
	var started_msec: int = Time.get_ticks_msec()
	while not arena.ended and arena.frame < MAX_TICKS:
		arena.simulate_tick(STEP)
		if arena.frame % 120 == 0:
			await process_frame
	var elapsed_msec: int = Time.get_ticks_msec() - started_msec
	var summaries: Array[String] = []
	for fighter: Fighter in arena.fighters:
		summaries.append("P%d stocks=%d kills=%d percent=%.1f dealt=%.1f inputs=%d attacks=%d specials=%d" % [
			fighter.player_slot, fighter.stocks, fighter.kills, fighter.percent,
			fighter.dealt_percent, int(input_counts.get(fighter.player_id, 0)),
			int(attack_counts.get(fighter.player_id, 0)), int(special_counts.get(fighter.player_id, 0))])
	print("JUNBAE_AI_RESULT seed=%d ended=%s winner=P%d ticks=%d game_seconds=%.1f runtime_ms=%d" % [
		battle_seed, arena.ended, arena.winner_id, arena.frame, float(arena.frame) / 60.0, elapsed_msec])
	for summary: String in summaries:
		print("JUNBAE_AI_PLAYER %s" % summary)
	if not arena.ended or arena.winner_id <= 0:
		push_error("Four-Junbae AI battle did not produce a winner within %d ticks" % MAX_TICKS)
		quit(1)
		return
	quit(0)

func _bot_input(player_id: int) -> int:
	var fighter: Fighter = arena.fighter_for_id(player_id)
	if fighter == null or fighter.life_state != Fighter.LifeState.ACTIVE:
		return 0
	var target: Fighter = _nearest_target(fighter)
	if target == null:
		return 0
	var mask: int = 0
	var center_x: float = arena.platforms[0].get_center().x
	var recovering: bool = fighter.position.y > 470.0 or fighter.position.x < 230.0 or fighter.position.x > 1050.0
	var desired_x: float = center_x if recovering else target.position.x
	var distance_x: float = desired_x - fighter.position.x
	if distance_x < -28.0:
		mask |= 1
	elif distance_x > 28.0:
		mask |= 2
	var phase: int = arena.frame + player_id * 17
	if recovering and phase % 18 == 0:
		mask |= 4
	var target_dx: float = target.position.x - fighter.position.x
	var target_dy: float = target.position.y - fighter.position.y
	if absf(target_dx) < 115.0 and absf(target_dy) < 95.0 and phase % 22 == 0:
		mask |= 16
		if target_dy < -35.0:
			mask |= 4
		elif target_dy > 35.0:
			mask |= 8
	elif phase % 181 == 0:
		mask |= 32
		match player_id:
			1:
				mask |= 4
			2:
				mask |= 8
			3:
				mask |= 2 if target_dx >= 0.0 else 1
	elif absf(target_dx) < 75.0 and phase % 257 == 0:
		mask |= 16 | 32
	if mask != 0:
		input_counts[player_id] = int(input_counts.get(player_id, 0)) + 1
	if (mask & 16) != 0:
		attack_counts[player_id] = int(attack_counts.get(player_id, 0)) + 1
	if (mask & 32) != 0:
		special_counts[player_id] = int(special_counts.get(player_id, 0)) + 1
	return mask

func _nearest_target(source: Fighter) -> Fighter:
	var nearest: Fighter
	var nearest_distance: float = INF
	for candidate: Fighter in arena.fighters:
		if candidate == source or candidate.life_state != Fighter.LifeState.ACTIVE:
			continue
		var distance: float = source.position.distance_squared_to(candidate.position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = candidate
	return nearest
