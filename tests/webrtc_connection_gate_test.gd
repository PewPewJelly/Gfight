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

	var ice_servers: Array = client.ICE_CONFIGURATION.get("iceServers", [])
	check(not ice_servers.is_empty(), "WebRTC has an ICE server configuration")
	check(str(ice_servers[0]).contains("stun.cloudflare.com:3478"), "Cloudflare STUN is configured")

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
