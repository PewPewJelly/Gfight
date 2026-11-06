extends SceneTree
## Cloud clock pacing, extended history, and authoritative state repair checks.

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
	session.cloud_room = true
	session.phase = session.Phase.PLAYING
	session._cloud_match_id = "sync-test"
	session._reset_rollback()
	online_client._time_sync_samples = 1
	online_client._server_time_offset_msec = 0.0
	online_client._record_received_input("peer-test", {"latest_tick": 10})
	online_client._record_received_input("peer-test", {"latest_tick": 14})
	check(online_client._input_tick_gap_events.get("peer-test", 0) == 1, "Input tick jumps are counted per peer")
	check(online_client._input_tick_gap_total.get("peer-test", 0) == 3, "Skipped input ticks are counted per peer")
	online_client._peer_ping_sequence["peer-test"] = 1
	online_client._peer_ping_sent_msec["peer-test"] = Time.get_ticks_msec() - 20
	online_client._handle_peer_pong("peer-test", {"sequence": 1})
	check(online_client._peer_latest_rtt_msec.get("peer-test", -1) >= 20, "Peer diagnostic pong records application RTT")

	arena = preload("res://arena.tscn").instantiate()
	arena.standalone = false
	arena.authoritative = true
	arena.simulation_seed = 12345
	arena.participant_ids.assign([1, 2])
	arena.input_provider = func(_id: int) -> int: return 0
	session.arena = arena
	session.add_child(arena)
	arena.set_physics_process(false)
	arena.countdown_left = 0.0
	arena.tick_completed.connect(session._on_cloud_tick_completed)

	session._cloud_match_start_msec = online_client.server_time_msec() - 10.0 * session.FIXED_TICK_SECONDS * 1000.0
	session._advance_to_cloud_tick()
	check(arena.frame == session.CLOCK_MAX_CATCHUP_TICKS, "Clock catch-up is bounded per physics frame")
	while arena.frame < 140:
		arena.simulate_tick(session.FIXED_TICK_SECONDS)
	check(session._rollback_states.has(20), "Extended sync history keeps two seconds of states")
	check(not session._rollback_states.has(19), "Sync history removes states older than its limit")

	var repair_state: Dictionary = session._rollback_states[100].duplicate(true)
	session._apply_state_repair(repair_state)
	check(arena.frame == 100, "Authoritative repair applies the supplied current state")
	check(session.repair_count == 1, "Repair count is recorded")
	check(session._rollback_states.size() == 1 and session._rollback_states.has(100), "Repair resets stale rollback history")

	session.leave()
	print("Cloud sync checks finished with %d failure(s)." % failures)
	quit(1 if failures > 0 else 0)

func check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		failures += 1
		printerr("FAIL: %s" % label)
