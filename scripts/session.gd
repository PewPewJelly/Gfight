extends Node

signal changed
signal match_started
enum JoinRejection { FULL, IN_PROGRESS, VERSION }
const MAX_PLAYERS: int = 4
const DEFAULT_PORT: int = 27840
const DEFAULT_ADDRESS := "127.0.0.1"
const JOIN_TIMEOUT_MSEC: int = 8000
## Lets the room-closed notice reach clients before the host socket closes.
const CLOSE_FLUSH_SECONDS: float = 0.2
const SETTINGS_PATH := "user://settings.cfg"
var roster: Dictionary = {}
## Participant readiness by peer id. The host is never listed: pressing start is its ready.
var ready_states: Dictionary = {}
## Result confirmations (S4 Enter) by peer id.
var confirmed: Dictionary = {}
var phase: String = "menu"
var message: String = ""
## S1 toast (create failure, host lost, room closed). Cleared when read by the UI.
var toast: String = ""
## S1-1 popup error; the popup stays open with the address kept.
var join_error: String = ""
var room_address: String = ""
var last_address: String = ""
var local_mode: bool = false
var local_name: String = "Player"
var arena: FightArena
var generation: int = 0
var input_masks: Dictionary = {}
var input_times: Dictionary = {}
var join_started: int = 0
var _pending_address: String = ""

func _ready() -> void:
	multiplayer.peer_connected.connect(_peer_joined)
	multiplayer.peer_disconnected.connect(_peer_left)
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(_connection_failed)
	multiplayer.server_disconnected.connect(_server_left)
	var settings := ConfigFile.new()
	if settings.load(SETTINGS_PATH) == OK:
		last_address = str(settings.get_value("network", "last_address", ""))

static func game_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))

## Parses "IP" or "IP:port" (S1-1). Empty input means the local default address.
static func parse_address(text: String) -> Dictionary:
	var value := text.strip_edges()
	if value.is_empty():
		return {"ok": true, "host": DEFAULT_ADDRESS, "port": DEFAULT_PORT}
	var host := value
	var port := DEFAULT_PORT
	if value.count(":") == 1:
		host = value.get_slice(":", 0)
		var port_text := value.get_slice(":", 1)
		if not port_text.is_valid_int() or int(port_text) < 1 or int(port_text) > 65535:
			return {"ok": false}
		port = int(port_text)
	elif value.count(":") > 1:
		return {"ok": false}
	if host.is_empty() or not (host.is_valid_ip_address() or _is_host_name(host)):
		return {"ok": false}
	return {"ok": true, "host": host, "port": port}

static func _is_host_name(host: String) -> bool:
	var pattern := RegEx.create_from_string("^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$")
	return pattern.search(host) != null and not host.is_valid_float()

## Same-network IPv4 shown in the lobby so other computers can join.
static func local_ipv4() -> String:
	var fallback := DEFAULT_ADDRESS
	for address in IP.get_local_addresses():
		if not address.is_valid_ip_address() or address.contains(":") or address.begins_with("127.") or address.begins_with("169.254."):
			continue
		if address.begins_with("192.168.") or address.begins_with("10.") or address.begins_with("172."):
			return address
		fallback = address
	return fallback

func host_game(player_name: String, port: int = DEFAULT_PORT) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	# One spare slot so a fifth client can be told the room is full instead of timing out.
	var error := peer.create_server(port, MAX_PLAYERS)
	if error != OK:
		toast = UiStyle.CREATE_FAILED
		push_warning("create_server failed: %s" % error_string(error))
		changed.emit()
		return error
	multiplayer.multiplayer_peer = peer
	local_name = clean_name(player_name)
	roster = {1: local_name}
	ready_states.clear()
	room_address = "%s:%d" % [local_ipv4(), port]
	phase = "lobby"
	message = ""
	changed.emit()
	return OK

func join_address(text: String, player_name: String = "Player") -> Error:
	var parsed := parse_address(text)
	if not parsed.ok:
		join_error = UiStyle.BAD_ADDRESS
		changed.emit()
		return ERR_INVALID_PARAMETER
	return join_game(parsed.host, parsed.port, player_name)

func join_game(address: String, port: int, player_name: String) -> Error:
	leave()
	if address.strip_edges().is_empty():
		join_error = UiStyle.BAD_ADDRESS
		changed.emit()
		return ERR_INVALID_PARAMETER
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address.strip_edges(), port)
	if error != OK:
		join_error = UiStyle.NOT_FOUND
		push_warning("create_client failed: %s" % error_string(error))
		changed.emit()
		return error
	multiplayer.multiplayer_peer = peer
	local_name = clean_name(player_name)
	phase = "connecting"
	join_error = ""
	_pending_address = address.strip_edges() if port == DEFAULT_PORT else "%s:%d" % [address.strip_edges(), port]
	room_address = "%s:%d" % [address.strip_edges(), port]
	join_started = Time.get_ticks_msec()
	changed.emit()
	return OK

static func clean_name(value: String) -> String:
	var name_value := value.strip_edges().replace("\n", " ").replace("\r", " ").left(20)
	return name_value if not name_value.is_empty() else "Player"

func local_game() -> void:
	leave()
	local_mode = true
	roster = {1: "P1", 2: "P2"}
	room_address = ""
	phase = "lobby"
	changed.emit()

func is_host() -> bool:
	return local_mode or multiplayer.is_server()

## Ready count excludes the host (design: pressing start is the host's ready).
func ready_count() -> int:
	var count := 0
	for id in roster:
		if id != 1 and ready_states.get(id, false):
			count += 1
	return count

func all_ready() -> bool:
	return local_mode or ready_count() == roster.size() - 1

func can_start() -> bool:
	return phase == "lobby" and roster.size() >= 2 and all_ready() and is_host()

func start_game() -> bool:
	if not can_start():
		return false
	generation += 1
	if local_mode:
		_begin_match(roster, generation)
	else:
		_begin_match.rpc(roster, generation)
	return true

func set_ready(value: bool) -> void:
	if phase != "lobby" or is_host():
		return
	ready_states[multiplayer.get_unique_id()] = value
	changed.emit()
	_request_ready.rpc_id(1, value)

@rpc("any_peer", "call_remote", "reliable")
func _request_ready(value: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if phase != "lobby" or not roster.has(sender) or sender == 1:
		return
	ready_states[sender] = value
	_publish_lobby()

## S2 [나가기]. The host closes the room for everyone; a participant just leaves.
func leave_room() -> void:
	if phase != "lobby" or local_mode or not multiplayer.is_server() or multiplayer.get_peers().is_empty():
		leave()
		return
	_room_closed.rpc()
	phase = "closing"
	changed.emit()
	await get_tree().create_timer(CLOSE_FLUSH_SECONDS).timeout
	if phase == "closing":
		leave()

@rpc("authority", "call_remote", "reliable")
func _room_closed() -> void:
	leave()
	toast = UiStyle.ROOM_CLOSED
	changed.emit()

func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if is_instance_valid(arena):
		arena.queue_free()
	arena = null
	roster.clear()
	ready_states.clear()
	confirmed.clear()
	input_masks.clear()
	input_times.clear()
	phase = "menu"
	local_mode = false
	message = ""
	room_address = ""
	changed.emit()

func cancel_join() -> void:
	join_error = ""
	if phase == "connecting":
		leave()

func _process(_delta: float) -> void:
	if phase == "connecting" and Time.get_ticks_msec() - join_started > JOIN_TIMEOUT_MSEC:
		_connection_failed()

func _connected() -> void:
	_register.rpc_id(1, local_name, game_version())

func _peer_joined(id: int) -> void:
	if not multiplayer.is_server():
		return
	if phase != "lobby":
		_reject(id, JoinRejection.IN_PROGRESS)
	elif multiplayer.get_peers().size() >= MAX_PLAYERS:
		_reject(id, JoinRejection.FULL)

func _reject(id: int, reason: JoinRejection) -> void:
	_join_rejected.rpc_id(id, reason)
	# disconnect_later lets the queued rejection reason reach the client first.
	var packet_peer := (multiplayer.multiplayer_peer as ENetMultiplayerPeer).get_peer(id)
	if packet_peer != null:
		packet_peer.peer_disconnect_later()

@rpc("authority", "call_remote", "reliable")
func _join_rejected(reason: int) -> void:
	if phase != "connecting":
		return
	leave()
	match reason:
		JoinRejection.FULL:
			join_error = UiStyle.ROOM_FULL
		JoinRejection.IN_PROGRESS:
			join_error = UiStyle.IN_PROGRESS
		JoinRejection.VERSION:
			join_error = UiStyle.VERSION_MISMATCH
		_:
			join_error = UiStyle.NOT_FOUND
	changed.emit()

func _connection_failed() -> void:
	leave()
	join_error = UiStyle.NOT_FOUND
	changed.emit()

func _server_left() -> void:
	var was_connecting := phase == "connecting"
	leave()
	if was_connecting:
		join_error = UiStyle.NOT_FOUND
	else:
		toast = UiStyle.HOST_LOST
	changed.emit()

@rpc("any_peer", "call_remote", "reliable")
func _register(player_name: String, version: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 1 or roster.has(sender):
		return
	if phase != "lobby":
		_reject(sender, JoinRejection.IN_PROGRESS)
		return
	if roster.size() >= MAX_PLAYERS:
		_reject(sender, JoinRejection.FULL)
		return
	if version != game_version():
		_reject(sender, JoinRejection.VERSION)
		return
	roster[sender] = clean_name(player_name)
	ready_states[sender] = false
	message = UiStyle.JOINED % slot_of(sender)
	_publish_lobby()

## Slot numbers follow sorted peer ids, matching arena fighter order.
func slot_of(id: int) -> int:
	var ids := roster.keys()
	ids.sort()
	return ids.find(id) + 1

func sorted_ids() -> Array:
	var ids := roster.keys()
	ids.sort()
	return ids

func _publish_lobby() -> void:
	changed.emit()
	if not local_mode:
		_lobby_state.rpc(roster, ready_states, message)

@rpc("authority", "call_remote", "reliable")
func _lobby_state(players: Dictionary, readiness: Dictionary, notice: String) -> void:
	if phase == "connecting":
		_remember_address(_pending_address)
	roster = players
	ready_states = readiness
	phase = "lobby"
	message = notice
	changed.emit()

func _remember_address(address: String) -> void:
	last_address = address
	var settings := ConfigFile.new()
	settings.load(SETTINGS_PATH)
	settings.set_value("network", "last_address", address)
	var error := settings.save(SETTINGS_PATH)
	if error != OK:
		push_warning("Could not save last address: %s" % error_string(error))

@rpc("authority", "call_local", "reliable")
func _begin_match(players: Dictionary, round_generation: int) -> void:
	roster = players.duplicate()
	generation = round_generation
	phase = "playing"
	message = ""
	confirmed.clear()
	input_masks.clear()
	input_times.clear()
	if is_instance_valid(arena):
		remove_child(arena)
		arena.queue_free()
	arena = preload("res://arena.tscn").instantiate()
	arena.name = "Arena"
	arena.standalone = false
	arena.authoritative = local_mode or multiplayer.is_server()
	arena.local_player_id = 0 if local_mode else multiplayer.get_unique_id()
	arena.participant_ids.assign(roster.keys())
	arena.participant_ids.sort()
	arena.input_provider = input_for
	add_child(arena)
	if arena.authoritative:
		arena.snapshot_ready.connect(_broadcast_snapshot)
		arena.match_finished.connect(_finished)
	else:
		# Client physics must never produce combat outcomes.
		for fighter in arena.fighters:
			fighter.collision_layer = 0
			fighter.collision_mask = 0
	match_started.emit()
	changed.emit()

func submit_local_input(mask: int) -> void:
	if phase != "playing":
		return
	if local_mode or multiplayer.is_server():
		_store_input(1, mask)
	else:
		_submit_input.rpc_id(1, mask, generation)

@rpc("any_peer", "call_remote", "reliable", 2)
func _submit_input(mask: int, round_generation: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if multiplayer.is_server() and phase == "playing" and round_generation == generation and roster.has(sender):
		_store_input(sender, mask)

func _store_input(id: int, mask: int) -> void:
	input_masks[id] = mask & 31
	input_times[id] = Time.get_ticks_msec()

func input_for(id: int) -> int:
	if local_mode:
		var keys: Array[Key] = [KEY_A, KEY_D, KEY_W, KEY_J]
		if id == 2:
			keys = [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_K]
		return Fighter.read_keyboard(keys, KEY_S if id == 1 else KEY_DOWN)
	if Time.get_ticks_msec() - int(input_times.get(id, 0)) > 500:
		return 0
	return int(input_masks.get(id, 0))

func _broadcast_snapshot(state: Dictionary) -> void:
	if not local_mode and multiplayer.get_peers().size() > 0:
		_world_state.rpc(state, generation)

@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _world_state(state: Dictionary, round_generation: int) -> void:
	if is_instance_valid(arena) and generation == round_generation:
		arena.apply_snapshot(state)

func _finished(_winner_id: int) -> void:
	phase = "result"
	confirmed.clear()
	if not local_mode and multiplayer.get_peers().size() > 0:
		_final_state.rpc(arena.snapshot(), generation)
	changed.emit()

@rpc("authority", "call_remote", "reliable")
func _final_state(state: Dictionary, round_generation: int) -> void:
	if is_instance_valid(arena) and generation == round_generation:
		arena.apply_snapshot(state)
		phase = "result"
		confirmed.clear()
		changed.emit()

## S4 Enter. Everyone still in the room must confirm before the shared return to S2.
func confirm_result() -> void:
	if phase != "result":
		return
	if local_mode:
		return_to_lobby()
	elif multiplayer.is_server():
		_record_confirm(1)
	elif not confirmed.get(multiplayer.get_unique_id(), false):
		confirmed[multiplayer.get_unique_id()] = true
		changed.emit()
		_request_confirm.rpc_id(1, generation)

@rpc("any_peer", "call_remote", "reliable")
func _request_confirm(round_generation: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if phase == "result" and round_generation == generation and roster.has(sender):
		_record_confirm(sender)

func _record_confirm(id: int) -> void:
	confirmed[id] = true
	_check_confirmations()

func _check_confirmations() -> void:
	if phase != "result":
		return
	for id in roster:
		if not confirmed.get(id, false):
			changed.emit()
			if not local_mode:
				_confirm_state.rpc(confirmed, generation)
			return
	return_to_lobby()

@rpc("authority", "call_remote", "reliable")
func _confirm_state(states: Dictionary, round_generation: int) -> void:
	if phase == "result" and round_generation == generation:
		confirmed = states
		changed.emit()

## Host-only shared return to the same room's lobby with readiness cleared.
func return_to_lobby() -> void:
	if phase != "result" or not is_host():
		return
	if local_mode:
		_back_to_lobby(roster)
	else:
		_back_to_lobby.rpc(roster)

@rpc("authority", "call_local", "reliable")
func _back_to_lobby(players: Dictionary) -> void:
	roster = players.duplicate()
	if is_instance_valid(arena):
		arena.queue_free()
	arena = null
	phase = "lobby"
	message = ""
	ready_states.clear()
	for id in roster:
		if id != 1:
			ready_states[id] = false
	confirmed.clear()
	input_masks.clear()
	input_times.clear()
	changed.emit()

func _peer_left(id: int) -> void:
	if not multiplayer.is_server() or not roster.has(id):
		return
	var slot := slot_of(id)
	roster.erase(id)
	ready_states.erase(id)
	confirmed.erase(id)
	input_masks.erase(id)
	input_times.erase(id)
	if phase == "lobby":
		message = UiStyle.LEFT % slot
		_publish_lobby()
	elif phase == "result":
		_roster_update.rpc(roster)
		_check_confirmations()
	elif is_instance_valid(arena):
		_roster_update.rpc(roster)
		changed.emit()
		for fighter in arena.fighters:
			if fighter.player_id == id:
				fighter.stocks = 1
				fighter.last_attacker_id = 0
				fighter.life_state = Fighter.LifeState.ACTIVE
				fighter.ring_out()
		if not arena.ended:
			arena._resolve_result()

@rpc("authority", "call_remote", "reliable")
func _roster_update(players: Dictionary) -> void:
	roster = players.duplicate()
	changed.emit()
