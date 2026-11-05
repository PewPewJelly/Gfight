extends Node
## Cloudflare public lobby + room signaling + full-mesh WebRTC prototype.

signal rooms_updated(rooms: Array)
signal room_state_updated(state: Dictionary)
signal connection_changed(connected: bool)
signal data_received(remote_id: String, message: Variant)
signal request_failed(message: String)
signal chat_received(remote_id: String, text: String)
signal match_started(data: Dictionary)
signal match_connection_progress(ready_count: int, total_count: int)
signal match_connection_failed
signal mesh_status_changed(ready_count: int, total_count: int, failed: bool)
signal kicked
signal lobby_returned
signal server_error(code: String)

const DEFAULT_HTTP_BASE := "https://gfight-multi-server.gfight-multi-server.workers.dev"
const DEFAULT_WS_BASE := "wss://gfight-multi-server.gfight-multi-server.workers.dev"
const LOG_LIMIT := 40
const MATCH_CONNECT_TIMEOUT_MSEC := 15000
const DEBUG_REFRESH_MSEC := 250
const TIME_SYNC_INTERVAL_MSEC := 1000
const TIME_SYNC_TIMEOUT_MSEC := 3000
const ICE_CONFIGURATION := {
	"iceServers": [
		{"urls": ["stun:stun.cloudflare.com:3478"]}
	]
}

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
var _pending_match_start: Dictionary = {}
var _match_connect_deadline_msec := 0
var _last_match_progress := ""
var _last_mesh_status := ""
var _sent_input_packets := 0
var _last_sent_input_tick := -1
var _received_input_packets: Dictionary = {}
var _last_received_input_tick: Dictionary = {}
var _last_received_input_msec: Dictionary = {}
var _last_debug_refresh_msec := 0
var _time_sync_pending := false
var _time_sync_sent_ticks_msec := 0
var _time_sync_sent_unix_msec := 0.0
var _next_time_sync_ticks_msec := 0
var _server_time_offset_msec := 0.0
var _best_time_sync_rtt_msec := 2147483647
var _time_sync_samples := 0
var _local_game_tick := -1
var _expected_game_tick := -1
var _desync_count := 0
var _repair_count := 0

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
				request_failed.emit("방을 만들지 못했습니다. 잠시 후 다시 시도해 주세요.")
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
		request_failed.emit("방 연결을 시작하지 못했습니다.")
		return
	_log("connecting room %s" % room_id.left(8))

func disconnect_room() -> void:
	_clear_pending_match()
	_last_mesh_status = ""
	_sent_input_packets = 0
	_last_sent_input_tick = -1
	_received_input_packets.clear()
	_last_received_input_tick.clear()
	_last_received_input_msec.clear()
	_time_sync_pending = false
	_time_sync_sent_ticks_msec = 0
	_time_sync_sent_unix_msec = 0.0
	_next_time_sync_ticks_msec = 0
	_server_time_offset_msec = 0.0
	_best_time_sync_rtt_msec = 2147483647
	_time_sync_samples = 0
	_local_game_tick = -1
	_expected_game_tick = -1
	_desync_count = 0
	_repair_count = 0
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

func set_display_name(display_name: String) -> void:
	_send_signal_message({"type": "set_name", "payload": {"display_name": display_name}})

func update_room(patch: Dictionary) -> void:
	_send_signal_message({"type": "update_room", "payload": patch})

func send_chat(text: String) -> void:
	_send_signal_message({"type": "chat", "payload": {"text": text}})

func kick_player(player_id: String) -> void:
	_send_signal_message({"type": "kick", "payload": {"player_id": player_id}})

func start_match() -> void:
	_send_signal_message({"type": "start_match", "payload": {}})

func return_lobby() -> void:
	_send_signal_message({"type": "return_lobby", "payload": {}})

func send_game_packet(message: Dictionary) -> void:
	if str(message.get("type", "")) == "input":
		_sent_input_packets += 1
		_last_sent_input_tick = int(message.get("latest_tick", -1))
	var packet := var_to_bytes(message)
	for remote_id: String in connections:
		var channel: WebRTCDataChannel = connections[remote_id].channel
		if channel.get_ready_state() == WebRTCDataChannel.STATE_OPEN:
			channel.put_packet(packet)

func send_test_input(tick: int, buttons: int) -> void:
	send_game_packet({"type": "input", "tick": tick, "buttons": buttons})

func is_mesh_ready() -> bool:
	var remote_ids := _remote_ids_from_players(room_state.get("players", []))
	if remote_ids.is_empty():
		return false
	for remote_id: String in remote_ids:
		if not _channel_is_open(remote_id):
			return false
	return true

func has_server_time_sync() -> bool:
	return _time_sync_samples > 0

func server_time_msec() -> float:
	return Time.get_unix_time_from_system() * 1000.0 + _server_time_offset_msec

func update_game_sync_stats(local_tick: int, expected_tick: int, desyncs: int, repairs: int) -> void:
	_local_game_tick = local_tick
	_expected_game_tick = expected_tick
	_desync_count = desyncs
	_repair_count = repairs

func report_sync_event(text: String) -> void:
	_log(text)

func _process(_delta: float) -> void:
	socket.poll()
	var state := socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _socket_was_open:
			_socket_was_open = true
			_next_time_sync_ticks_msec = 0
			_log("WebSocket connected")
			connection_changed.emit(true)
		while socket.get_available_packet_count() > 0:
			_handle_server_message(socket.get_packet().get_string_from_utf8())
		_poll_server_time_sync()
	elif _socket_was_open and state == WebSocketPeer.STATE_CLOSED:
		_socket_was_open = false
		_log("WebSocket closed code=%d" % socket.get_close_code())
		connection_changed.emit(false)

	for remote_id: String in connections.keys():
		var entry: Dictionary = connections[remote_id]
		var peer: WebRTCPeerConnection = entry.peer
		peer.poll()
		var connection_state := int(peer.get_connection_state())
		if connection_state != int(entry.get("connection_state", -1)):
			entry.connection_state = connection_state
			connections[remote_id] = entry
			_log("Peer %s: %s" % [remote_id.left(6), _peer_state_name(connection_state)])
		var channel: WebRTCDataChannel = entry.channel
		if channel.get_ready_state() == WebRTCDataChannel.STATE_OPEN and not entry.open_logged:
			entry.open_logged = true
			connections[remote_id] = entry
			_log("DataChannel OPEN <-> %s" % remote_id.left(6))
		while channel.get_available_packet_count() > 0:
			var packet := channel.get_packet()
			var message: Variant = bytes_to_var(packet)
			var message_type := ""
			if message is Dictionary:
				var message_dict: Dictionary = message
				message_type = str(message_dict.get("type", ""))
				if message_type == "input":
					_record_received_input(remote_id, message_dict)
			if message_type not in ["input", "state_hash"]:
				_log("data <- %s %s" % [remote_id.left(6), str(message).left(80)])
			data_received.emit(remote_id, message)
	_emit_mesh_status_if_changed()
	_update_pending_match()
	_update_debug_stats_if_due()

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
		"chat":
			chat_received.emit(str(message.get("from_id", "")), str(message.get("text", "")))
		"match_start":
			_queue_match_start(message)
		"kicked":
			_clear_pending_match()
			kicked.emit()
		"lobby_returned":
			_clear_pending_match()
			lobby_returned.emit()
		"error":
			var code := str(message.get("code", "UNKNOWN"))
			_log("server error: %s" % code)
			server_error.emit(code)
		"pong":
			_handle_pong(message)

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
	var error := peer.initialize(ICE_CONFIGURATION)
	if error != OK:
		_log("WebRTC init failed: %s" % error_string(error))
		return
	peer.session_description_created.connect(_on_description_created.bind(remote_id))
	peer.ice_candidate_created.connect(_on_ice_candidate.bind(remote_id))
	var channel := peer.create_data_channel("game", {"negotiated": true, "id": 1})
	connections[remote_id] = {
		"peer": peer,
		"channel": channel,
		"open_logged": false,
		"connection_state": int(peer.get_connection_state())
	}
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

func _queue_match_start(message: Dictionary) -> void:
	_pending_match_start = message.duplicate(true)
	_match_connect_deadline_msec = Time.get_ticks_msec() + MATCH_CONNECT_TIMEOUT_MSEC
	_last_match_progress = ""
	_log("Match start received; waiting for P2P channels")
	_update_pending_match()

func _update_pending_match() -> void:
	if _pending_match_start.is_empty():
		return
	var remote_ids := _remote_ids_from_players(_pending_match_start.get("players", []))
	var open_count := 0
	var failed := false
	for remote_id: String in remote_ids:
		if _channel_is_open(remote_id):
			open_count += 1
		elif connections.has(remote_id):
			var peer: WebRTCPeerConnection = connections[remote_id].peer
			failed = failed or peer.get_connection_state() == WebRTCPeerConnection.STATE_FAILED
	var progress := "%d/%d" % [open_count, remote_ids.size()]
	if progress != _last_match_progress:
		_last_match_progress = progress
		_log("P2P ready %s" % progress)
		match_connection_progress.emit(open_count, remote_ids.size())
	if not remote_ids.is_empty() and open_count == remote_ids.size() and has_server_time_sync():
		var message := _pending_match_start.duplicate(true)
		_clear_pending_match()
		_log("P2P mesh ready; entering match")
		match_started.emit(message)
	elif failed or Time.get_ticks_msec() >= _match_connect_deadline_msec:
		_fail_pending_match()

func _fail_pending_match() -> void:
	if _pending_match_start.is_empty():
		return
	_clear_pending_match()
	_log("P2P connection failed")
	match_connection_failed.emit()

func _clear_pending_match() -> void:
	_pending_match_start.clear()
	_match_connect_deadline_msec = 0
	_last_match_progress = ""

func _remote_ids_from_players(players_value: Variant) -> Array[String]:
	var remote_ids: Array[String] = []
	if not players_value is Array:
		return remote_ids
	for value: Variant in players_value:
		if not value is Dictionary:
			continue
		var remote_id := str((value as Dictionary).get("player_id", ""))
		if not remote_id.is_empty() and remote_id != local_player_id:
			remote_ids.append(remote_id)
	return remote_ids

func _channel_is_open(remote_id: String) -> bool:
	if not connections.has(remote_id):
		return false
	var channel: WebRTCDataChannel = connections[remote_id].channel
	return channel.get_ready_state() == WebRTCDataChannel.STATE_OPEN

func _emit_mesh_status_if_changed() -> void:
	var remote_ids := _remote_ids_from_players(room_state.get("players", []))
	var open_count := 0
	var failed := false
	for remote_id: String in remote_ids:
		if _channel_is_open(remote_id):
			open_count += 1
		elif connections.has(remote_id):
			var peer: WebRTCPeerConnection = connections[remote_id].peer
			failed = failed or peer.get_connection_state() == WebRTCPeerConnection.STATE_FAILED
	var status := "%d/%d/%s" % [open_count, remote_ids.size(), failed]
	if status == _last_mesh_status:
		return
	_last_mesh_status = status
	mesh_status_changed.emit(open_count, remote_ids.size(), failed)

func _peer_state_name(state: int) -> String:
	match state:
		WebRTCPeerConnection.STATE_NEW:
			return "NEW"
		WebRTCPeerConnection.STATE_CONNECTING:
			return "CONNECTING"
		WebRTCPeerConnection.STATE_CONNECTED:
			return "CONNECTED"
		WebRTCPeerConnection.STATE_DISCONNECTED:
			return "DISCONNECTED"
		WebRTCPeerConnection.STATE_FAILED:
			return "FAILED"
		WebRTCPeerConnection.STATE_CLOSED:
			return "CLOSED"
	return "UNKNOWN(%d)" % state

func _record_received_input(remote_id: String, message: Dictionary) -> void:
	_received_input_packets[remote_id] = int(_received_input_packets.get(remote_id, 0)) + 1
	_last_received_input_tick[remote_id] = int(message.get("latest_tick", -1))
	_last_received_input_msec[remote_id] = Time.get_ticks_msec()

func _poll_server_time_sync() -> void:
	var now := Time.get_ticks_msec()
	if _time_sync_pending and now - _time_sync_sent_ticks_msec >= TIME_SYNC_TIMEOUT_MSEC:
		_time_sync_pending = false
		_next_time_sync_ticks_msec = now
		_log("Cloudflare time sync timeout")
	if _time_sync_pending or now < _next_time_sync_ticks_msec:
		return
	_time_sync_pending = true
	_time_sync_sent_ticks_msec = now
	_time_sync_sent_unix_msec = Time.get_unix_time_from_system() * 1000.0
	_next_time_sync_ticks_msec = now + TIME_SYNC_INTERVAL_MSEC
	_send_signal_message({"type": "ping"})

func _handle_pong(message: Dictionary) -> void:
	if not _time_sync_pending or not message.get("time") is float and not message.get("time") is int:
		return
	var received_ticks := Time.get_ticks_msec()
	var rtt := maxi(0, received_ticks - _time_sync_sent_ticks_msec)
	var midpoint_unix := _time_sync_sent_unix_msec + float(rtt) / 2.0
	var sample_offset := float(message.time) - midpoint_unix
	if _time_sync_samples == 0:
		_server_time_offset_msec = sample_offset
	elif rtt <= _best_time_sync_rtt_msec + 20:
		_server_time_offset_msec = lerpf(_server_time_offset_msec, sample_offset, 0.25)
	_best_time_sync_rtt_msec = mini(_best_time_sync_rtt_msec, rtt)
	_time_sync_samples += 1
	_time_sync_pending = false
	if _time_sync_samples == 1:
		_log("Cloudflare clock synced offset=%dms rtt=%dms" % [roundi(_server_time_offset_msec), rtt])

func _send_signal_message(value: Dictionary) -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	socket.send_text(JSON.stringify(value))

func player_id_for_slot(slot: int) -> String:
	for value: Variant in room_state.get("players", []):
		if value is Dictionary:
			var player: Dictionary = value
			if int(player.get("slot", 0)) == slot:
				return str(player.get("player_id", ""))
	return ""

func slot_for_player_id(player_id: String) -> int:
	for value: Variant in room_state.get("players", []):
		if value is Dictionary:
			var player: Dictionary = value
			if str(player.get("player_id", "")) == player_id:
				return int(player.get("slot", 0))
	return 0

func _on_rooms_received(code: int, data: Variant) -> void:
	if code != 200 or not data is Dictionary or not data.get("rooms", []) is Array:
		_log("room list failed: HTTP %d" % code)
		request_failed.emit("공개 방 목록을 불러오지 못했습니다.")
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
	_debug_panel.visible = true
	layer.add_child(_debug_panel)
	_debug_label = Label.new()
	_debug_label.add_theme_font_size_override("font_size", 13)
	_debug_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_debug_panel.add_child(_debug_label)
	_update_debug_text()

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_L:
		_debug_panel.visible = not _debug_panel.visible
		if _debug_panel.visible:
			_update_debug_text()

func _log(text: String) -> void:
	var stamp := Time.get_time_string_from_system()
	_logs.append("[%s] %s" % [stamp, text])
	if _logs.size() > LOG_LIMIT:
		_logs.pop_front()
	_update_debug_text()

func _update_debug_text() -> void:
	if _debug_label == null:
		return
	var open_count := 0
	for entry: Dictionary in connections.values():
		var channel: WebRTCDataChannel = entry.channel
		if channel.get_ready_state() == WebRTCDataChannel.STATE_OPEN:
			open_count += 1
	var lines: Array[String] = [
		"MULTIPLAYER LOG [L: 숨기기/표시]",
		"room=%s  me=%s  P2P=%d/%d" % [room_id.left(8), local_player_id.left(6), open_count, connections.size()],
		"CLOCK offset=%dms  rtt=%dms  samples=%d" % [roundi(_server_time_offset_msec), 0 if _best_time_sync_rtt_msec == 2147483647 else _best_time_sync_rtt_msec, _time_sync_samples],
		"TX input=%d  last_tick=%d" % [_sent_input_packets, _last_sent_input_tick]
	]
	if _local_game_tick >= 0 and _expected_game_tick >= 0:
		lines.append("TICK local=%d expected=%d delta=%+d  DESYNC=%d REPAIR=%d" % [
			_local_game_tick, _expected_game_tick, _expected_game_tick - _local_game_tick, _desync_count, _repair_count
		])
	var now := Time.get_ticks_msec()
	for remote_id: String in _received_input_packets.keys():
		var age := now - int(_last_received_input_msec.get(remote_id, now))
		lines.append("RX %s input=%d  tick=%d  age=%dms" % [
			remote_id.left(6),
			int(_received_input_packets[remote_id]),
			int(_last_received_input_tick.get(remote_id, -1)),
			age
		])
	lines.append_array(_logs.slice(maxi(0, _logs.size() - 8)))
	_debug_label.text = "\n".join(lines)

func _update_debug_stats_if_due() -> void:
	if not _debug_panel.visible:
		return
	var now := Time.get_ticks_msec()
	if now - _last_debug_refresh_msec < DEBUG_REFRESH_MSEC:
		return
	_last_debug_refresh_msec = now
	_update_debug_text()
