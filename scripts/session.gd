extends Node

signal changed
signal match_started
const MAX_PLAYERS: int = 4
const DEFAULT_PORT: int = 27840
var roster: Dictionary = {}
var phase: String = "menu"
var message: String = ""
var local_mode: bool = false
var local_name: String = "Player"
var arena: FightArena
var generation: int = 0
var input_masks: Dictionary = {}
var input_times: Dictionary = {}
var join_started: int = 0

func _ready() -> void:
	multiplayer.peer_connected.connect(_peer_joined)
	multiplayer.peer_disconnected.connect(_peer_left)
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(_connection_failed)
	multiplayer.server_disconnected.connect(_server_left)

func host_game(player_name: String, port: int = DEFAULT_PORT) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, MAX_PLAYERS - 1)
	if error != OK:
		message = "방을 만들 수 없습니다. 포트를 확인하세요. (%s)" % error_string(error)
		changed.emit()
		return error
	multiplayer.multiplayer_peer = peer
	local_name = clean_name(player_name)
	roster = {1: local_name}
	phase = "lobby"
	message = "방 생성 완료 · 포트 %d · 2명 이상이면 시작할 수 있습니다." % port
	changed.emit()
	return OK

func join_game(address: String, port: int, player_name: String) -> Error:
	leave()
	if address.strip_edges().is_empty():
		message = "접속 주소를 입력하세요."
		changed.emit()
		return ERR_INVALID_PARAMETER
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address.strip_edges(), port)
	if error != OK:
		message = "접속을 시작할 수 없습니다. (%s)" % error_string(error)
		changed.emit()
		return error
	multiplayer.multiplayer_peer = peer
	local_name = clean_name(player_name)
	phase = "connecting"
	join_started = Time.get_ticks_msec()
	message = "접속 중…"
	changed.emit()
	return OK

static func clean_name(value: String) -> String:
	var name_value := value.strip_edges().replace("\n", " ").replace("\r", " ").left(20)
	return name_value if not name_value.is_empty() else "Player"

func local_game() -> void:
	leave()
	local_mode = true
	roster = {1: "P1", 2: "P2"}
	phase = "lobby"
	message = "로컬 2인 · 시작을 누르세요."
	changed.emit()

func can_start() -> bool:
	return phase == "lobby" and roster.size() >= 2 and (local_mode or multiplayer.is_server())

func start_game() -> bool:
	if not can_start():
		return false
	generation += 1
	if local_mode:
		_begin_match(roster, generation)
	else:
		_begin_match.rpc(roster, generation)
	return true

func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if is_instance_valid(arena):
		arena.queue_free()
	arena = null
	roster.clear()
	input_masks.clear()
	input_times.clear()
	phase = "menu"
	local_mode = false
	message = ""
	changed.emit()

func _process(_delta: float) -> void:
	if phase == "connecting" and Time.get_ticks_msec() - join_started > 8000:
		_connection_failed()

func _connected() -> void:
	_register.rpc_id(1, local_name)

func _peer_joined(id: int) -> void:
	if multiplayer.is_server() and phase != "lobby":
		var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
		peer.disconnect_peer(id)

func _connection_failed() -> void:
	leave()
	message = "접속 실패: 주소·포트와 방 생성 여부를 확인하세요."
	changed.emit()

func _server_left() -> void:
	leave()
	message = "호스트와 연결이 끊겼습니다."
	changed.emit()

@rpc("any_peer", "call_remote", "reliable")
func _register(player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if phase != "lobby" or roster.size() >= MAX_PLAYERS or sender <= 1 or roster.has(sender):
		return
	roster[sender] = clean_name(player_name)
	_publish_lobby()

func _publish_lobby() -> void:
	changed.emit()
	if not local_mode:
		_lobby_state.rpc(roster, message)

@rpc("authority", "call_remote", "reliable")
func _lobby_state(players: Dictionary, notice: String) -> void:
	roster = players
	phase = "lobby"
	message = notice
	changed.emit()

@rpc("authority", "call_local", "reliable")
func _begin_match(players: Dictionary, round_generation: int) -> void:
	roster = players.duplicate()
	generation = round_generation
	phase = "playing"
	input_masks.clear()
	input_times.clear()
	if is_instance_valid(arena):
		remove_child(arena)
		arena.queue_free()
	arena = preload("res://arena.tscn").instantiate()
	arena.name = "Arena"
	arena.standalone = false
	arena.authoritative = local_mode or multiplayer.is_server()
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
	if not local_mode and multiplayer.get_peers().size() > 0:
		_final_state.rpc(arena.snapshot(), generation)
	changed.emit()

@rpc("authority", "call_remote", "reliable")
func _final_state(state: Dictionary, round_generation: int) -> void:
	if is_instance_valid(arena) and generation == round_generation:
		arena.apply_snapshot(state)
		phase = "result"
		changed.emit()

func return_to_lobby() -> void:
	if phase != "result" or (not local_mode and not multiplayer.is_server()):
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
	input_masks.clear()
	input_times.clear()
	changed.emit()

func _peer_left(id: int) -> void:
	if not multiplayer.is_server() or not roster.has(id):
		return
	roster.erase(id)
	input_masks.erase(id)
	input_times.erase(id)
	if phase == "lobby":
		_publish_lobby()
	elif is_instance_valid(arena):
		_roster_update.rpc(roster)
		changed.emit()
		for fighter in arena.fighters:
			if fighter.player_id == id:
				fighter.stocks = 1
				fighter.life_state = Fighter.LifeState.ACTIVE
				fighter.ring_out()
		if not arena.ended:
			arena._resolve_result()

@rpc("authority", "call_remote", "reliable")
func _roster_update(players: Dictionary) -> void:
	roster = players.duplicate()
	changed.emit()
