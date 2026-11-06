extends SceneTree
## Verifies that cloud matches wait for P2P channels and fail with a bounded timeout.

var failures := 0
var match_started := false
var match_failed := false
var progress_ready := -1
var progress_total := -1

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var client: Node = load("res://scripts/online_client.gd").new()
	root.add_child(client)
	client.local_player_id = "local-player"
	client.room_state = {
		"players": [
			{"player_id": "local-player", "slot": 1},
			{"player_id": "remote-player", "slot": 2}
		]
	}
	client.match_started.connect(func(_data: Dictionary) -> void: match_started = true)
	client.match_connection_failed.connect(func() -> void: match_failed = true)
	client.match_connection_progress.connect(func(ready: int, total: int) -> void:
		progress_ready = ready
		progress_total = total
	)
	check(not client._debug_panel.visible, "Multiplayer log is hidden by default")
	var toggle_key := InputEventKey.new()
	toggle_key.physical_keycode = KEY_L
	toggle_key.pressed = true
	client._unhandled_key_input(toggle_key)
	check(client._debug_panel.visible, "L shows the multiplayer log")
	client._unhandled_key_input(toggle_key)
	check(not client._debug_panel.visible, "L hides the multiplayer log again")

	var ice_servers: Array = client.ICE_CONFIGURATION.get("iceServers", [])
	check(not ice_servers.is_empty(), "WebRTC has an ICE server configuration")
	check(str(ice_servers[0]).contains("stun.cloudflare.com:3478"), "Cloudflare STUN is configured")
	client.send_game_packet({"type": "input", "latest_tick": 12, "recent": []})
	check(client._sent_input_packets == 1 and client._last_sent_input_tick == 12, "Input send stats are recorded")
	client._time_sync_pending = true
	client._time_sync_sent_ticks_msec = Time.get_ticks_msec() - 20
	client._time_sync_sent_unix_msec = Time.get_unix_time_from_system() * 1000.0 - 20.0
	client._handle_pong({"type": "pong", "time": Time.get_unix_time_from_system() * 1000.0})
	check(client.has_server_time_sync(), "Cloudflare pong establishes a server clock sample")
	check(absi(roundi(client._server_time_offset_msec)) < 100, "Server clock offset uses the RTT midpoint")

	client._queue_match_start({
		"type": "match_start",
		"match_id": "gate-test",
		"players": client.room_state.players
	})
	check(not match_started, "Match waits while the remote DataChannel is closed")
	check(progress_ready == 0 and progress_total == 1, "Connection progress reports 0/1")

	client._match_connect_deadline_msec = 0
	client._update_pending_match()
	check(match_failed, "Closed P2P path reaches the bounded failure state")
	check(not match_started, "Failed P2P path never enters the match")

	client.queue_free()
	print("WebRTC connection gate checks finished with %d failure(s)." % failures)
	quit(1 if failures > 0 else 0)

func check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		failures += 1
		printerr("FAIL: %s" % label)
