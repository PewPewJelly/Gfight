extends SceneTree
## Fixed match slots, scheduled departure, and confirmed-state hash checks.

var failures := 0
var session: Node
var online_client: Node
var arena: FightArena

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	session = root.get_node("Session")
	online_client = root.get_node("OnlineClient")
	session.leave()
	online_client.disconnect_room()
	online_client.local_player_id = "p1"
	online_client.room_state = {
		"host_id": "p1",
		"status": "in_game",
		"players": [
			{"player_id": "p1", "slot": 1},
			{"player_id": "p2", "slot": 2},
			{"player_id": "p3", "slot": 3},
		],
	}
	online_client._remember_match_slots(online_client.room_state.players)
	online_client.room_state.players = [
		{"player_id": "p1", "slot": 1},
		{"player_id": "p3", "slot": 2},
	]
	check(online_client.match_slot_for_player_id("p3") == 3, "A remaining player keeps the original match slot")

	session.cloud_room = true
	session.phase = session.Phase.PLAYING
	session._cloud_match_id = "departure-test"
	session._reset_rollback()
	arena = preload("res://arena.tscn").instantiate()
	arena.standalone = false
	arena.authoritative = true
	arena.simulation_seed = 24680
	arena.participant_ids.assign([1, 2, 3])
	arena.input_provider = session.input_for
	session.arena = arena
	session.add_child(arena)
	arena.set_physics_process(false)
	arena.countdown_left = 0.0
	arena.tick_completed.connect(session._on_cloud_tick_completed)
	session._rollback_states[0] = arena.snapshot().duplicate(true)
	session._initialize_match_inputs()

	for input_tick: int in range(session.ROLLBACK_INPUT_DELAY, 30):
		session._store_rollback_input(input_tick, 1, 0, true)
		if input_tick < 5:
			session._store_rollback_input(input_tick, 2, 0, true)
		if input_tick != 29:
			session._store_rollback_input(input_tick, 3, 0, true)

	session._on_cloud_data_received("p3", {
		"type": "input", "match_id": "departure-test",
		"latest_tick": 4, "input_start_tick": 4,
		"input_buttons": PackedByteArray([2]),
	})
	check(int((session._rollback_inputs[4] as Dictionary).get(3, -1)) == 2, "P3 input still maps to fixed slot 3")
	session._store_rollback_input(4, 3, 0, true)

	session._on_cloud_player_left("departure-test", "p2", 2, 5)
	while arena.frame < 30 and session.phase == session.Phase.PLAYING:
		session._prepare_cloud_tick(arena.frame)
		arena.simulate_tick(session.FIXED_TICK_SECONDS)
	var departed := arena.fighter_for_id(2)
	check(departed != null and departed.stocks == 0 and departed.life_state == Fighter.LifeState.ELIMINATED, "Departed P2 is removed from combat at the scheduled tick")
	check(arena.fighters.size() == 3 and arena.fighter_for_id(3).life_state == Fighter.LifeState.ACTIVE, "Rollback keeps the fighter node while P3 remains active")
	check(session._last_confirmed_hash_sent_tick < 30, "A predicted state hash is not sent before every input is confirmed")

	session._store_rollback_input(29, 3, 0, true)
	session._prepare_cloud_tick(arena.frame)
	arena.simulate_tick(session.FIXED_TICK_SECONDS)
	check(session._confirmed_input_tick >= 29, "Confirmed input frontier advances after the missing input arrives")
	check(session._last_confirmed_hash_sent_tick == 30, "The tick-30 hash is sent only after confirmation")

	session.leave()
	await process_frame
	print("Cloud departure checks finished with %d failure(s)." % failures)
	quit(1 if failures > 0 else 0)

func check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		failures += 1
		printerr("FAIL: %s" % label)

