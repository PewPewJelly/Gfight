extends SceneTree
## Two-process end-to-end cloud match check. P1 must connect first and becomes host.

var room_id := ""
var player_name := "P1"
var server_url := "http://127.0.0.1:8787"
var expect_host := false
var elapsed := 0.0
var opened_room := false
var sent_ready := false
var requested_start := false
var finished := false
var session: Node
var client: Node

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--room="):
			room_id = argument.trim_prefix("--room=")
		elif argument.begins_with("--name="):
			player_name = argument.trim_prefix("--name=")
		elif argument == "--host":
			expect_host = true
		elif argument.begins_with("--server="):
			server_url = argument.trim_prefix("--server=").trim_suffix("/")
	if room_id.is_empty():
		quit(2)
		return
	call_deferred("start")

func start() -> void:
	session = root.get_node("Session")
	client = root.get_node("OnlineClient")
	session.local_name = player_name
	client.http_base = server_url
	client.ws_base = server_url.replace("https://", "wss://").replace("http://", "ws://")
	client.room_state_updated.connect(_on_room_state)
	client.join_room(room_id, player_name)

func _on_room_state(state: Dictionary) -> void:
	if not opened_room and not client.local_player_id.is_empty():
		opened_room = true
		session.open_cloud_room("Rollback E2E", state)
	if not opened_room or state.get("players", []).size() < 2:
		return
	if not session.is_host() and not sent_ready:
		sent_ready = true
		session.set_ready(true)
	if session.is_host() and session.all_ready() and not requested_start:
		requested_start = true
		client.start_match()

func _process(delta: float) -> bool:
	elapsed += delta
	if session != null and session.phase == session.Phase.PLAYING and is_instance_valid(session.arena):
		var tick: int = session.arena.frame
		var mask := 0
		if tick < 75:
			mask = 2 if session.my_id() == 1 else 1
		if tick in [25, 55]:
			mask |= 16
		session.submit_local_input(mask)
		if tick >= 240 and not finished:
			finished = true
			var state_hash: int = session._rollback_state_hash(session.arena.snapshot())
			print("CLOUD_MATCH_READY name=%s host=%s frame=%d hash=%d rollbacks=%d peers=%d" % [
				player_name, session.is_host(), tick, state_hash, session.rollback_count, client.connections.size()])
			quit(0)
	elif session != null and session.phase == session.Phase.RESULT and not finished:
		finished = true
		var state_hash: int = session._rollback_state_hash(session.arena.snapshot())
		print("CLOUD_MATCH_READY name=%s host=%s frame=%d hash=%d rollbacks=%d peers=%d result=true" % [
			player_name, session.is_host(), session.arena.frame, state_hash, session.rollback_count, client.connections.size()])
		quit(0)
	if elapsed > 30.0:
		printerr("CLOUD_MATCH_TIMEOUT name=%s phase=%s room=%s peers=%d" % [player_name, session.phase if session != null else -1, opened_room, client.connections.size() if client != null else 0])
		quit(1)
	return false
