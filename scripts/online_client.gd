extends Node
## Cloudflare public lobby + room signaling + full-mesh WebRTC prototype.

signal rooms_updated(rooms: Array)
signal room_state_updated(state: Dictionary)
signal connection_changed(connected: bool)
signal data_received(remote_id: String, message: Variant)

const DEFAULT_HTTP_BASE := "https://gfight-multi-server.gfight-multi-server.workers.dev"
const DEFAULT_WS_BASE := "wss://gfight-multi-server.gfight-multi-server.workers.dev"
const LOG_LIMIT := 40

var http_base := DEFAULT_HTTP_BASE
var ws_base := DEFAULT_WS_BASE
var rooms: Array = []
var room_id := ""
var local_player_id := ""
var room_state: Dictionary = {}
var socket := WebSocketPeer.new()
var connections: Dictionary = {}
var _socket_was_open := false
var _logs: Array[String] = []
var _debug_label: Label
var _debug_panel: PanelContainer

func _ready() -> void:
	_build_debug_overlay()
	set_process(true)
	_log("OnlineClient ready")

func list_rooms() -> void:
	_http_request(http_base + "/rooms", HTTPClient.METHOD_GET, {}, _on_rooms_received)

func create_room(room_name: String, display_name: String) -> void:
	var body := {"name": room_name, "host_name": display_name}
	_http_request(http_base + "/rooms", HTTPClient.METHOD_POST, body,
		func(code: int, data: Variant) -> void:
			if code != 201 or not data is Dictionary or not data.has("room"):
				_log("create room failed: HTTP %d" % code)
				return
			var created: Dictionary = data.room
			_log("room created: %s" % created.get("name", ""))
			join_room(str(created.get("room_id", "")), display_name)
	)

func join_room(target_room_id: String, display_name: String) -> void:
	disconnect_room()
	room_id = target_room_id
	var url := "%s/rooms/%s/connect?name=%s" % [ws_base, room_id, display_name.uri_encode()]
	var error := socket.connect_to_url(url)
	if error != OK:
		_log("WebSocket start failed: %s" % error_string(error))
		return
	_log("connecting room %s" % room_id.left(8))

func disconnect_room() -> void:
	for remote_id: String in connections.keys():
		_close_peer(remote_id)
	connections.clear()
	if socket.get_ready_state() in [WebSocketPeer.STATE_CONNECTING, WebSocketPeer.STATE_OPEN]:
		socket.close(1000, "leave room")
	socket = WebSocketPeer.new()
	room_id = ""
	local_player_id = ""
	room_state.clear()
	_socket_was_open = false

func set_ready(ready: bool) -> void:
	_send_signal_message({"type": "set_ready", "payload": {"ready": ready}})

func set_character(character_id: String) -> void:
	_send_signal_message({"type": "set_character", "payload": {"character_id": character_id}})

func send_test_input(tick: int, buttons: int) -> void:
	var packet := JSON.stringify({"type": "input", "tick": tick, "buttons": buttons}).to_utf8_buffer()
	for remote_id: String in connections:
		var channel: WebRTCDataChannel = connections[remote_id].channel
		if channel.get_ready_state() == WebRTCDataChannel.STATE_OPEN:
			channel.put_packet(packet)
			_log("input -> %s tick=%d buttons=%d" % [remote_id.left(6), tick, buttons])

func _process(_delta: float) -> void:
	socket.poll()
	var state := socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _socket_was_open:
			_socket_was_open = true
			_log("WebSocket connected")
			connection_changed.emit(true)
		while socket.get_available_packet_count() > 0:
			_handle_server_message(socket.get_packet().get_string_from_utf8())
	elif _socket_was_open and state == WebSocketPeer.STATE_CLOSED:
		_socket_was_open = false
		_log("WebSocket closed code=%d" % socket.get_close_code())
		connection_changed.emit(false)

	for remote_id: String in connections.keys():
		var entry: Dictionary = connections[remote_id]
		var peer: WebRTCPeerConnection = entry.peer
		peer.poll()
		var channel: WebRTCDataChannel = entry.channel
		if channel.get_ready_state() == WebRTCDataChannel.STATE_OPEN and not entry.open_logged:
			entry.open_logged = true
			connections[remote_id] = entry
			_log("DataChannel OPEN <-> %s" % remote_id.left(6))
		while channel.get_available_packet_count() > 0:
			var text := channel.get_packet().get_string_from_utf8()
			_log("data <- %s %s" % [remote_id.left(6), text.left(80)])
			data_received.emit(remote_id, JSON.parse_string(text))

func _handle_server_message(text: String) -> void:
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		_log("invalid server JSON")
		return
	var message: Dictionary = parsed
	match str(message.get("type", "")):
		"welcome":
			local_player_id = str(message.get("player_id", ""))
			_log("welcome id=%s" % local_player_id.left(6))
		"room_state":
			room_state = message
			room_state_updated.emit(room_state)
			_log("room state players=%d" % (message.get("players", []) as Array).size())
			_sync_mesh(message.get("players", []))
		"signal":
			_handle_signal(str(message.get("from_id", "")), message.get("payload", {}))
		"error":
			_log("server error: %s" % message.get("code", "UNKNOWN"))
		"pong":
			pass

func _sync_mesh(players_value: Variant) -> void:
	if local_player_id.is_empty() or not players_value is Array:
		return
	var wanted: Dictionary = {}
	for value: Variant in players_value:
		if not value is Dictionary:
			continue
		var remote_id := str((value as Dictionary).get("player_id", ""))
		if remote_id.is_empty() or remote_id == local_player_id:
			continue
		wanted[remote_id] = true
		if not connections.has(remote_id):
			_create_peer(remote_id, local_player_id < remote_id)
	for remote_id: String in connections.keys():
		if not wanted.has(remote_id):
			_close_peer(remote_id)
			connections.erase(remote_id)

func _create_peer(remote_id: String, offerer: bool) -> void:
	var peer := WebRTCPeerConnection.new()
	var error := peer.initialize({})
	if error != OK:
		_log("WebRTC init failed: %s" % error_string(error))
		return
	peer.session_description_created.connect(_on_description_created.bind(remote_id))
	peer.ice_candidate_created.connect(_on_ice_candidate.bind(remote_id))
	var channel := peer.create_data_channel("game", {"negotiated": true, "id": 1})
	connections[remote_id] = {"peer": peer, "channel": channel, "open_logged": false}
	_log("peer created %s offerer=%s" % [remote_id.left(6), offerer])
	if offerer:
		peer.create_offer()

func _on_description_created(kind: String, sdp: String, remote_id: String) -> void:
	if not connections.has(remote_id):
		return
	var peer: WebRTCPeerConnection = connections[remote_id].peer
	peer.set_local_description(kind, sdp)
	_send_signal_message({
		"type": "signal",
		"target_id": remote_id,
		"payload": {"kind": kind, "sdp": sdp}
	})
	_log("%s -> %s" % [kind, remote_id.left(6)])

func _on_ice_candidate(media: String, index: int, candidate: String, remote_id: String) -> void:
	_send_signal_message({
		"type": "signal",
		"target_id": remote_id,
		"payload": {"kind": "ice", "media": media, "index": index, "candidate": candidate}
	})

func _handle_signal(remote_id: String, payload_value: Variant) -> void:
	if remote_id.is_empty() or not payload_value is Dictionary:
		return
	if not connections.has(remote_id):
		_create_peer(remote_id, false)
	var peer: WebRTCPeerConnection = connections[remote_id].peer
	var payload: Dictionary = payload_value
	var kind := str(payload.get("kind", ""))
	if kind in ["offer", "answer"]:
		peer.set_remote_description(kind, str(payload.get("sdp", "")))
		_log("%s <- %s" % [kind, remote_id.left(6)])
	elif kind == "ice":
		peer.add_ice_candidate(str(payload.get("media", "")), int(payload.get("index", 0)), str(payload.get("candidate", "")))

func _close_peer(remote_id: String) -> void:
	if not connections.has(remote_id):
		return
	var peer: WebRTCPeerConnection = connections[remote_id].peer
	peer.close()
	_log("peer removed %s" % remote_id.left(6))

func _send_signal_message(value: Dictionary) -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	socket.send_text(JSON.stringify(value))

func _on_rooms_received(code: int, data: Variant) -> void:
	if code != 200 or not data is Dictionary or not data.get("rooms", []) is Array:
		_log("room list failed: HTTP %d" % code)
		return
	rooms = data.rooms
	rooms_updated.emit(rooms)
	_log("rooms received: %d" % rooms.size())

func _http_request(url: String, method: HTTPClient.Method, body: Dictionary, callback: Callable) -> void:
	var request := HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(func(_result: int, code: int, _headers: PackedStringArray, bytes: PackedByteArray) -> void:
		var text := bytes.get_string_from_utf8()
		var data: Variant = JSON.parse_string(text) if not text.is_empty() else {}
		callback.call(code, data)
		request.queue_free()
	)
	var headers := PackedStringArray(["Content-Type: application/json"])
	var text_body := JSON.stringify(body) if method != HTTPClient.METHOD_GET else ""
	var error := request.request(url, headers, method, text_body)
	if error != OK:
		_log("HTTP start failed: %s" % error_string(error))
		request.queue_free()

func _build_debug_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_debug_panel = PanelContainer.new()
	_debug_panel.position = Vector2(12, 12)
	_debug_panel.custom_minimum_size = Vector2(470, 210)
	_debug_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_debug_panel)
	_debug_label = Label.new()
	_debug_label.add_theme_font_size_override("font_size", 13)
	_debug_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_debug_panel.add_child(_debug_label)
	_update_debug_text()

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_F3:
		_debug_panel.visible = not _debug_panel.visible

func _log(text: String) -> void:
	var stamp := Time.get_time_string_from_system()
	_logs.append("[%s] %s" % [stamp, text])
	if _logs.size() > LOG_LIMIT:
		_logs.pop_front()
	_update_debug_text()

func _update_debug_text() -> void:
	if _debug_label == null:
		return
	var header := "MULTIPLAYER DEBUG [F3]\nroom=%s  me=%s  peers=%d" % [room_id.left(8), local_player_id.left(6), connections.size()]
	_debug_label.text = header + "\n" + "\n".join(_logs.slice(maxi(0, _logs.size() - 10)))
