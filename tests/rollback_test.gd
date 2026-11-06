extends SceneTree
## Deterministic rollback core: restore an old tick and replay to the same present tick.

var failures: int = 0
var inputs: Dictionary = {}
var arena: FightArena

func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error(description)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	arena = preload("res://arena.tscn").instantiate()
	arena.standalone = false
	arena.authoritative = true
	arena.simulation_seed = 424242
	arena.participant_ids.assign([1, 2])
	arena.input_provider = func(id: int) -> int:
		var tick_inputs: Dictionary = inputs.get(arena.frame, {})
		return int(tick_inputs.get(id, 0))
	root.add_child(arena)
	arena.set_physics_process(false)
	arena.countdown_left = 0.0

	for tick: int in range(6):
		inputs[tick] = {1: 2, 2: 0}
	var state_at_two: Dictionary
	for tick: int in range(6):
		arena.simulate_tick(1.0 / 60.0)
		if arena.frame == 2:
			state_at_two = arena.snapshot().duplicate(true)
	var predicted_position := arena.fighters[0].position
	check(arena.frame == 6 and not state_at_two.is_empty(), "Six predicted ticks and tick-two snapshot exist")

	for tick: int in range(2, 6):
		inputs[tick] = {1: 1, 2: 0}
	arena.restore_snapshot(state_at_two)
	while arena.frame < 6:
		arena.simulate_tick(1.0 / 60.0)
	var corrected_position := arena.fighters[0].position
	var corrected_state := arena.snapshot().duplicate(true)
	check(arena.frame == 6, "Rollback replay reaches the original present tick")
	check(not corrected_position.is_equal_approx(predicted_position), "Corrected remote input changes the replayed result")

	arena.restore_snapshot(state_at_two)
	while arena.frame < 6:
		arena.simulate_tick(1.0 / 60.0)
	check(arena.fighters[0].position.is_equal_approx(corrected_position), "Same state and inputs replay deterministically")
	check(arena.snapshot().players.size() == corrected_state.players.size(), "Rollback snapshot retains the full roster")

	print("Rollback checks complete: %d failures" % failures)
	quit(1 if failures > 0 else 0)
