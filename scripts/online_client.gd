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
const PEER_DIAGNOSTIC_INTERVAL_MSEC := 1000
const PEER_DIAGNOSTIC_TIMEOUT_MSEC := 3000
const NET_PROTOCOL_VERSION := 2
const NET_BUILD_TAG := "rollback30-packed15"
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
var _input_tick_gap_events: Dictionary = {}
var _input_tick_gap_total: Dictionary = {}
var _last_debug_refresh_msec := 0
var _time_sync_pending := false
var _time_sync_sent_ticks_msec := 0
var _time_sync_sent_unix_msec := 0.0
var _next_time_sync_ticks_msec := 0
var _server_time_offset_msec := 0.0
var _best_time_sync_rtt_msec := 2147483647
var _latest_time_sync_rtt_msec := -1
var _time_sync_timeout_count := 0
var _time_sync_samples := 0
var _next_peer_diagnostic_msec := 0
var _peer_ping_sequence: Dictionary = {}
var _peer_ping_sent_msec: Dictionary = {}
var _peer_rtt_msec: Dictionary = {}
var _peer_latest_rtt_msec: Dictionary = {}
var _peer_jitter_msec: Dictionary = {}
var _peer_ping_timeouts: Dictionary = {}
var _local_game_tick := -1
var _expected_game_tick := -1
var _input_delay_ticks := 0
var _input_redundancy_ticks := 0
var _max_rollback_ticks := 0
var _rollback_count := 0
var _rollback_depth_counts: Array[int] = [0, 0, 0, 0]
var _max_rollback_depth := 0
var _late_input_counts: Dictionary = {}
var _late_input_max_ticks: Dictionary = {}
var _last_rollback_source := 0
var _last_rollback_depth := 0
var _catchup_event_count := 0
var _catchup_extra_ticks := 0
var _max_catchup_steps := 0
var _desync_count := 0
var _repair_count := 0
var _last_repair_tick := -1
var _last_repair_age_ticks := 0
var _last_repair_replayed_ticks := 0

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
	_input_tick_gap_events.clear()
	_input_tick_gap_total.clear()
	_time_sync_pending = false
	_time_sync_sent_ticks_msec = 0
	_time_sync_sent_unix_msec = 0.0
	_next_time_sync_ticks_msec = 0
	_server_time_offset_msec = 0.0
	_best_time_sync_rtt_msec = 2147483647
	_latest_time_sync_rtt_msec = -1
	_time_sync_timeout_count = 0
	_time_sync_samples = 0
	_next_peer_diagnostic_msec = 0
	_peer_ping_sequence.clear()
	_peer_ping_sent_msec.clear()
	_peer_rtt_msec.clear()
	_peer_latest_rtt_msec.clear()
	_peer_jitter_msec.clear()
	_peer_ping_timeouts.clear()
	_local_game_tick = -1
	_expected_game_tick = -1
	_input_delay_ticks = 0
	_input_redundancy_ticks = 0
	_max_rollback_ticks = 0
	_rollback_count = 0
	_rollback_depth_counts = [0, 0, 0, 0]
	_max_rollback_depth = 0
	_late_input_counts.clear()
	_late_input_max_ticks.clear()
	_last_rollback_source = 0
	_last_rollback_depth = 0
	_catchup_event_count = 0
	_catchup_extra_ticks = 0
	_max_catchup_steps = 0
	_desync_count = 0
	_repair_count = 0
	_last_repair_tick = -1
	_last_repair_age_ticks = 0
	_last_repair_replayed_ticks = 0
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

func update_game_sync_stats(stats: Dictionary) -> void:
	_local_game_tick = int(stats.get("local_tick", -1))
	_expected_game_tick = int(stats.get("expected_tick", -1))
	_input_delay_ticks = int(stats.get("input_delay", 0))
	_input_redundancy_ticks = int(stats.get("input_redundancy", 0))
	_max_rollback_ticks = int(stats.get("max_rollback", 0))
	_rollback_count = int(stats.get("rollbacks", 0))
	var depth_counts: Variant = stats.get("depth_counts", [])
	if depth_counts is Array and depth_counts.size() == 4:
		_rollback_depth_counts.assign(depth_counts)
	_max_rollback_depth = int(stats.get("max_depth", 0))
	var late_counts: Variant = stats.get("late_counts", {})
	_late_input_counts = late_counts.duplicate() if late_counts is Dictionary else {}
	var late_max: Variant = stats.get("late_max", {})
	_late_input_max_ticks = late_max.duplicate() if late_max is Dictionary else {}
	_last_rollback_source = int(stats.get("last_rollback_source", 0))
	_last_rollback_depth = int(stats.get("last_rollback_depth", 0))
	_catchup_event_count = int(stats.get("catchup_events", 0))
	_catchup_extra_ticks = int(stats.get("catchup_extra", 0))
	_max_catchup_steps = int(stats.get("max_catchup_steps", 0))
	_desync_count = int(stats.get("desyncs", 0))
	_repair_count = int(stats.get("repairs", 0))
	_last_repair_tick = int(stats.get("last_repair_tick", -1))
	_last_repair_age_ticks = int(stats.get("last_repair_age", 0))
	_last_repair_replayed_ticks = int(stats.get("last_repair_replayed", 0))

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
				elif message_type == "diagnostic_ping":
					_handle_peer_ping(remote_id, message_dict)
					continue
				elif message_type == "diagnostic_pong":
					_handle_peer_pong(remote_id, message_dict)
					continue
			if message_type not in ["input", "state_hash"]:
				_log("data <- %s %s" % [remote_id.left(6), str(message).left(80)])
			data_received.emit(remote_id, message)
	_emit_mesh_status_if_changed()
	_update_pending_match()
	_poll_peer_diagnostics()
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
	_peer_ping_sequence.erase(remote_id)
	_peer_ping_sent_msec.erase(remote_id)
	_peer_rtt_msec.erase(remote_id)
	_peer_latest_rtt_msec.erase(remote_id)
	_peer_jitter_msec.erase(remote_id)
	_peer_ping_timeouts.erase(remote_id)
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
	var latest_tick := int(message.get("latest_tick", -1))
	var previous_tick := int(_last_received_input_tick.get(remote_id, -1))
	if previous_tick >= 0 and latest_tick > previous_tick + 1:
		_input_tick_gap_events[remote_id] = int(_input_tick_gap_events.get(remote_id, 0)) + 1
		_input_tick_gap_total[remote_id] = int(_input_tick_gap_total.get(remote_id, 0)) + latest_tick - previous_tick - 1
	_received_input_packets[remote_id] = int(_received_input_packets.get(remote_id, 0)) + 1
	_last_received_input_tick[remote_id] = latest_tick
	_last_received_input_msec[remote_id] = Time.get_ticks_msec()

func _poll_peer_diagnostics() -> void:
	var now := Time.get_ticks_msec()
	if now < _next_peer_diagnostic_msec:
		return
	_next_peer_diagnostic_msec = now + PEER_DIAGNOSTIC_INTERVAL_MSEC
	for remote_id: String in connections.keys():
		if not _channel_is_open(remote_id):
			continue
		if _peer_ping_sent_msec.has(remote_id):
			var pending_age := now - int(_peer_ping_sent_msec[remote_id])
			if pending_age < PEER_DIAGNOSTIC_TIMEOUT_MSEC:
				continue
			_peer_ping_timeouts[remote_id] = int(_peer_ping_timeouts.get(remote_id, 0)) + 1
			_peer_ping_sent_msec.erase(remote_id)
		var sequence := int(_peer_ping_sequence.get(remote_id, 0)) + 1
		_peer_ping_sequence[remote_id] = sequence
		_peer_ping_sent_msec[remote_id] = now
		_send_peer_packet(remote_id, {"type": "diagnostic_ping", "sequence": sequence})

func _handle_peer_ping(remote_id: String, message: Dictionary) -> void:
	var sequence_value: Variant = message.get("sequence")
	if not sequence_value is int:
		return
	_send_peer_packet(remote_id, {"type": "diagnostic_pong", "sequence": sequence_value})

func _handle_peer_pong(remote_id: String, message: Dictionary) -> void:
	var sequence_value: Variant = message.get("sequence")
	if not sequence_value is int or not _peer_ping_sent_msec.has(remote_id):
		return
	if int(sequence_value) != int(_peer_ping_sequence.get(remote_id, -1)):
		return
	var now := Time.get_ticks_msec()
	var rtt := maxi(0, now - int(_peer_ping_sent_msec[remote_id]))
	var previous_latest := int(_peer_latest_rtt_msec.get(remote_id, rtt))
	var previous_smoothed := float(_peer_rtt_msec.get(remote_id, rtt))
	var previous_jitter := float(_peer_jitter_msec.get(remote_id, 0.0))
	_peer_latest_rtt_msec[remote_id] = rtt
	_peer_rtt_msec[remote_id] = lerpf(previous_smoothed, float(rtt), 0.25)
	_peer_jitter_msec[remote_id] = lerpf(previous_jitter, float(absi(rtt - previous_latest)), 0.25)
	_peer_ping_sent_msec.erase(remote_id)

func _send_peer_packet(remote_id: String, message: Dictionary) -> void:
	if not _channel_is_open(remote_id):
		return
	var channel: WebRTCDataChannel = connections[remote_id].channel
	channel.put_packet(var_to_bytes(message))

func _poll_server_time_sync() -> void:
	var now := Time.get_ticks_msec()
	if _time_sync_pending and now - _time_sync_sent_ticks_msec >= TIME_SYNC_TIMEOUT_MSEC:
		_time_sync_pending = false
		_time_sync_timeout_count += 1
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
	_latest_time_sync_rtt_msec = rtt
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
	_debug_panel.custom_minimum_size = Vector2(760, 320)
	_debug_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_debug_panel.visible = false
	layer.add_child(_debug_panel)
	_debug_label = Label.new()
	_debug_label.add_theme_font_size_override("font_size", 14)
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
	var cloud_latest := "측정 전" if _latest_time_sync_rtt_msec < 0 else "%dms" % _latest_time_sync_rtt_msec
	var cloud_best := "-" if _best_time_sync_rtt_msec == 2147483647 else "%dms" % _best_time_sync_rtt_msec
	var build_version := str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	var host_slot := slot_for_player_id(str(room_state.get("host_id", "")))
	var host_text := "-" if host_slot < 1 else "P%d" % host_slot
	var physics_rate := int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 60))
	var lines: Array[String] = [
		"멀티플레이 진단  [L: 숨기기/표시]",
		"BUILD %s  |  NET v%d %s" % [build_version, NET_PROTOCOL_VERSION, NET_BUILD_TAG],
		"━━━━━━━━ 연결 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
		"방 %s  |  내 ID %s  |  HOST %s  |  P2P %d/%d OPEN" % [room_id.left(8), local_player_id.left(6), host_text, open_count, connections.size()],
		"Cloudflare  RTT %s (최저 %s)  |  시계차 %+dms  |  타임아웃 %d" % [cloud_latest, cloud_best, roundi(_server_time_offset_msec), _time_sync_timeout_count],
		"FPS %d  |  물리 %dHz  |  따라잡기 %d회/+%dt (최대 %dt/frame)" % [Engine.get_frames_per_second(), physics_rate, _catchup_event_count, _catchup_extra_ticks, _max_catchup_steps],
		"━━━━━━━━ 플레이어별 P2P ━━━━━━━━━━━━━━━━━━━━━━━"
	]
	var remote_ids: Array[String] = []
	for remote_id: String in connections.keys():
		remote_ids.append(remote_id)
	remote_ids.sort_custom(func(a: String, b: String) -> bool: return slot_for_player_id(a) < slot_for_player_id(b))
	var now := Time.get_ticks_msec()
	for remote_id: String in remote_ids:
		lines.append(_peer_debug_line(remote_id, now))
	if remote_ids.is_empty():
		lines.append("상대 연결 없음")
	lines.append("━━━━━━━━ 경기 동기화 ━━━━━━━━━━━━━━━━━━━━━━━━━")
	lines.append("송신 입력 %d  |  마지막 tick %d" % [_sent_input_packets, _last_sent_input_tick])
	if _local_game_tick >= 0 and _expected_game_tick >= 0:
		lines.append("tick 현재 %d / 목표 %d / 차이 %+d  |  ROLLBACK %d  DESYNC %d  REPAIR %d" % [
			_local_game_tick, _expected_game_tick, _expected_game_tick - _local_game_tick,
			_rollback_count, _desync_count, _repair_count
		])
		lines.append("입력 지연 %dt  |  중복 %dt  |  최대 롤백 %dt" % [_input_delay_ticks, _input_redundancy_ticks, _max_rollback_ticks])
		lines.append("롤백 깊이  일반 1~6:%d  주의 7~12:%d  큼 13~20:%d  긴급 21~30:%d  |  최대 %dt" % [
			int(_rollback_depth_counts[0]), int(_rollback_depth_counts[1]),
			int(_rollback_depth_counts[2]), int(_rollback_depth_counts[3]), _max_rollback_depth
		])
		var rollback_text := "없음" if _last_rollback_source < 1 else "P%d %dt" % [_last_rollback_source, _last_rollback_depth]
		var repair_text := "없음" if _last_repair_tick < 0 else "tick %d / age %dt / replayed %dt" % [_last_repair_tick, _last_repair_age_ticks, _last_repair_replayed_ticks]
		lines.append("마지막 롤백 %s  |  마지막 복구 %s" % [rollback_text, repair_text])
	lines.append("━━━━━━━━ 최근 사건 ━━━━━━━━━━━━━━━━━━━━━━━━━━━")
	lines.append_array(_logs.slice(maxi(0, _logs.size() - 5)))
	_debug_label.text = "\n".join(lines)

func _peer_debug_line(remote_id: String, now: int) -> String:
	var slot := slot_for_player_id(remote_id)
	var player_name := _display_name_for_player_id(remote_id)
	var state := "OPEN" if _channel_is_open(remote_id) else _connection_state_for_peer(remote_id)
	var rtt := "측정 전"
	if _peer_rtt_msec.has(remote_id):
		rtt = "%dms ±%d" % [roundi(float(_peer_rtt_msec[remote_id])), roundi(float(_peer_jitter_msec.get(remote_id, 0.0)))]
	var rx_age := -1
	if _last_received_input_msec.has(remote_id):
		rx_age = now - int(_last_received_input_msec[remote_id])
	var age_text := "없음" if rx_age < 0 else "%dms" % rx_age
	var buffered_bytes := 0
	if connections.has(remote_id):
		var channel: WebRTCDataChannel = (connections[remote_id] as Dictionary).channel
		buffered_bytes = channel.get_buffered_amount()
	return "P%d %s  |  %s  |  RTT %s  |  늦음 %d회/최대 %dt  |  대기 %s  |  ping 실패 %d\n    입력 %d개  |  최근 %s  |  tick %d  |  건너뜀 %d회/%dt" % [
		slot, player_name.left(8), state, rtt, int(_late_input_counts.get(slot, 0)), int(_late_input_max_ticks.get(slot, 0)),
		_format_bytes(buffered_bytes), int(_peer_ping_timeouts.get(remote_id, 0)),
		int(_received_input_packets.get(remote_id, 0)), age_text, int(_last_received_input_tick.get(remote_id, -1)),
		int(_input_tick_gap_events.get(remote_id, 0)), int(_input_tick_gap_total.get(remote_id, 0)),
	]

func _format_bytes(byte_count: int) -> String:
	if byte_count < 1024:
		return "%dB" % byte_count
	return "%.1fKB" % (float(byte_count) / 1024.0)

func _display_name_for_player_id(player_id: String) -> String:
	for value: Variant in room_state.get("players", []):
		if value is Dictionary:
			var player: Dictionary = value
			if str(player.get("player_id", "")) == player_id:
				return str(player.get("display_name", player_id.left(6)))
	return player_id.left(6)

func _connection_state_for_peer(remote_id: String) -> String:
	if not connections.has(remote_id):
		return "없음"
	return _peer_state_name(int((connections[remote_id] as Dictionary).get("connection_state", -1)))

func _update_debug_stats_if_due() -> void:
	if not _debug_panel.visible:
		return
	var now := Time.get_ticks_msec()
	if now - _last_debug_refresh_msec < DEBUG_REFRESH_MSEC:
		return
	_last_debug_refresh_msec = now
	_update_debug_text()
