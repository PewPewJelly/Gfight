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
	for input_tick: int in range(15):
		session._rollback_inputs[input_tick] = {1: input_tick & 63}
	var packed_inputs: Dictionary = session._pack_recent_inputs(14, 1)
	check((packed_inputs.input_buttons as PackedByteArray).size() == 15, "Fifteen recent inputs are packed into bytes")
	session._rollback_inputs.clear()
	session._store_remote_input_packet(2, {
		"latest_tick": 14,
		"input_start_tick": packed_inputs.input_start_tick,
		"input_buttons": packed_inputs.input_buttons
	})
	check(int((session._rollback_inputs[14] as Dictionary).get(2, -1)) == 14, "Packed input window restores the matching ticks")
	session._reset_rollback()

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
	check(session.catchup_event_count == 1 and session.catchup_extra_ticks == 3, "Multi-tick catch-up is counted")
	check(session.max_catchup_steps == session.CLOCK_MAX_CATCHUP_TICKS, "Maximum catch-up steps are recorded")
	while arena.frame < 140:
		arena.simulate_tick(session.FIXED_TICK_SECONDS)
	check(session._rollback_states.has(20), "Extended sync history keeps two seconds of states")
	check(not session._rollback_states.has(19), "Sync history removes states older than its limit")
	check(session.ROLLBACK_MAX_TICKS == 30, "Rollback accepts corrections up to thirty ticks")
	session._rollback_inputs = {0: {1: 2}}
	check(session._predicted_input(1, 12) == 2, "Input prediction can reuse an input within twelve ticks")
	check(session._predicted_input(1, 13) == 0, "Input prediction stops before the thirty-tick rollback limit")
	session._store_rollback_input(129, 2, 0, true)
	session._store_rollback_input(129, 2, 0, true)
	check(int(session.late_input_counts.get(2, 0)) == 1, "Redundant copies do not double-count a late input")
	check(int(session.late_input_max_ticks.get(2, 0)) == 11, "Maximum input lateness is recorded per player")
	session._pending_rollback_tick = 115
	session._pending_rollback_source = 2
	session._apply_pending_rollback()
	check(arena.frame == 140, "Twenty-five-tick rollback replays to the original present")
	check(session.rollback_depth_counts[session.RollbackDepthTier.CRITICAL] == 1, "Twenty-five-tick rollback is classified as critical")
	check(session.max_rollback_depth == 25, "Maximum rollback depth is recorded")
	check(session.last_rollback_source == 2 and session.last_rollback_depth == 25, "Last rollback source and depth are recorded")

	session._rollback_inputs[130] = {1: 2, 2: 0}
	var repair_state: Dictionary = session._rollback_states[100].duplicate(true)
	session._apply_state_repair(repair_state)
	check(arena.frame == 140, "Authoritative repair replays from the snapshot to the previous present")
	check(session._rollback_inputs.has(130), "Authoritative repair preserves inputs newer than the snapshot")
	check(session.repair_count == 1, "Repair count is recorded")
	check(session.last_repair_snapshot_tick == 100, "Last repair snapshot tick is recorded")
	check(session.last_repair_age_ticks == 40 and session.last_repair_replayed_ticks == 40, "Repair age and replay distance are recorded")
	check(session._rollback_states.has(100) and session._rollback_states.has(140), "Repair rebuilds rollback history through the replayed present")
	session._advance_to_cloud_tick()
	online_client._update_debug_text()
	check(int(online_client._late_input_counts.get(2, 0)) == 1, "Late-input diagnostics reach the overlay")
	check(online_client._debug_label.text.contains("NET v3 fixedslots-confirmedhash"), "Overlay shows the network build identifier")
	check(online_client._debug_label.text.contains("마지막 롤백 P2 25t"), "Overlay shows the last rollback source")
	check(online_client._debug_label.text.contains("age 40t / replayed 40t"), "Overlay shows the last repair distance")

	session.leave()
	await process_frame
	print("Cloud sync checks finished with %d failure(s)." % failures)
	quit(1 if failures > 0 else 0)

func check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		failures += 1
		printerr("FAIL: %s" % label)
