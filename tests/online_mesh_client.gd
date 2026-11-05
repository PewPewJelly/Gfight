extends SceneTree
## Headless smoke client. Run four processes with the same --room value.

var client: Node
var elapsed := 0.0
var sent_test := false
var ready_at := -1.0
var received_from: Dictionary = {}
var room_id := ""
var player_name := "MeshClient"
var server_url := "http://127.0.0.1:8787"

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--room="):
			room_id = argument.trim_prefix("--room=")
		elif argument.begins_with("--name="):
			player_name = argument.trim_prefix("--name=")
		elif argument.begins_with("--server="):
			server_url = argument.trim_prefix("--server=").trim_suffix("/")
	if room_id.is_empty():
		printerr("MESH_TEST missing --room")
		quit(2)
		return
	client = load("res://scripts/online_client.gd").new()
	client.http_base = server_url
	client.ws_base = server_url.replace("https://", "wss://").replace("http://", "ws://")
	root.add_child(client)
	client.data_received.connect(func(remote_id: String, _message: Variant) -> void: received_from[remote_id] = true)
	client.join_room(room_id, player_name)

func _process(delta: float) -> bool:
	elapsed += delta
	if client == null:
		return false
	if ready_at >= 0.0 and elapsed - ready_at >= 1.0:
		quit(0)
		return false
	var connections: Dictionary = client.connections
	var open_count := 0
	for entry: Dictionary in connections.values():
		var channel: WebRTCDataChannel = entry.channel
		if channel.get_ready_state() == WebRTCDataChannel.STATE_OPEN:
			open_count += 1
	if connections.size() == 3 and open_count == 3 and not sent_test:
		sent_test = true
		client.send_test_input(105, 16)
	if sent_test and received_from.size() == 3 and ready_at < 0.0:
		ready_at = elapsed
		print("MESH_READY name=%s peers=%d channels=%d inputs=%d" % [player_name, connections.size(), open_count, received_from.size()])
	elif elapsed > 20.0:
		printerr("MESH_TIMEOUT name=%s peers=%d channels=%d" % [player_name, connections.size(), open_count])
		quit(1)
	return false
