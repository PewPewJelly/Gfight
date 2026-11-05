extends Node
## The only manager singleton (Docs/00 §4.2): ENet connection, room state, RPC validation.
## Screens read these values and call the public functions; they never write state directly.

signal changed
signal match_started
signal chat_received(peer_id: int, text: String)
## Docs/00 §3.5.
enum Phase { MENU, CONNECTING, LOBBY, CLOSING, PLAYING, RESULT }
enum JoinRejection { FULL, IN_PROGRESS, VERSION }
const MAX_PLAYERS: int = 4
const DEFAULT_PORT: int = 27840
const DEFAULT_ADDRESS := "127.0.0.1"
const JOIN_TIMEOUT_MSEC: int = 8000
## Lets the room-closed notice reach clients before the host socket closes.
const CLOSE_FLUSH_SECONDS: float = 0.2
const SETTINGS_PATH := "user://settings.cfg"
const CHAT_MAX_LENGTH: int = 40
const CHAT_MIN_INTERVAL_MSEC: int = 500
## Inputs older than this are released (a lost client must not keep running).
const INPUT_STALE_MSEC: int = 500
const ROLLBACK_INPUT_DELAY: int = 2
const ROLLBACK_MAX_TICKS: int = 12
const ROLLBACK_REDUNDANCY: int = 5
const ROLLBACK_HASH_INTERVAL: int = 30
const FIXED_TICK_SECONDS: float = 1.0 / 60.0
const SYNC_HISTORY_TICKS: int = 120
const CLOCK_MAX_CATCHUP_TICKS: int = 4
const STATE_REPAIR_COOLDOWN_MSEC: int = 1000
## Fighter id of the training dummy. Training runs offline, so no real peer can have it.
const TRAINING_DUMMY_ID: int = 2
## Audio defaults (Docs/02 §2.4), shared by the lobby personal tab and the main [설정].
const DEFAULT_BGM: int = 70
const DEFAULT_SFX: int = 80

var room: RoomState = RoomState.new()
var phase: Phase:
	get:
		return room.phase as Phase
	set(value):
		room.phase = value
## Training is an offline room: Session acts as host and calls host handlers directly.
var training_mode: bool:
	get:
		return room.mode == ScreenTypes.RoomMode.TRAINING
var catalog: ContentCatalog = preload("res://resources/content_catalog.tres")
## Set when a match starts, cleared on the return to the lobby.
var match_setup: MatchSetup
## Result confirmations (S4 Enter) by peer id.
var confirmed: Dictionary = {}
## Online screen toast (create failure, host lost, room closed, kicked). Cleared when read by the UI.
var toast: String = ""
## Join popup error; the popup stays open with the address kept.
var join_error: String = ""
var last_address: String = ""
## Two players on one keyboard, kept for tests (no menu button).
var local_mode: bool = false
## True while the room roster is owned by Cloudflare/WebRTC instead of ENet.
var cloud_room: bool = false
var _cloud_room_name: String = ""
var _cloud_match_id: String = ""
var _rollback_inputs: Dictionary = {}
var _rollback_used: Dictionary = {}
var _rollback_states: Dictionary = {}
var _rollback_hashes: Dictionary = {}
var _pending_rollback_tick: int = -1
var _resimulating: bool = false
var rollback_count: int = 0
var desync_count: int = 0
var repair_count: int = 0
var _cloud_match_start_msec := 0.0
var _last_repair_sent_msec: Dictionary = {}
var local_name: String = PlayerData.DEFAULT_NAME
var arena: FightArena
var input_masks: Dictionary = {}
var input_times: Dictionary = {}
var join_started: int = 0
var _pending_address: String = ""
## Host only: last accepted chat time per peer id.
var _chat_times: Dictionary = {}
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	multiplayer.peer_connected.connect(_peer_joined)
	multiplayer.peer_disconnected.connect(_peer_left)
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(_connection_failed)
	multiplayer.server_disconnected.connect(_server_left)
	OnlineClient.room_state_updated.connect(_sync_cloud_room)
	OnlineClient.chat_received.connect(_on_cloud_chat)
	OnlineClient.match_started.connect(_on_cloud_match_started)
	OnlineClient.match_connection_progress.connect(_on_cloud_match_connection_progress)
	OnlineClient.match_connection_failed.connect(_on_cloud_match_connection_failed)
	OnlineClient.mesh_status_changed.connect(_on_cloud_mesh_status_changed)
	OnlineClient.kicked.connect(_on_cloud_kicked)
	OnlineClient.lobby_returned.connect(_on_cloud_lobby_returned)
	OnlineClient.data_received.connect(_on_cloud_data_received)
	OnlineClient.connection_changed.connect(_on_cloud_connection_changed)
	_rng.randomize()
	last_address = str(load_setting("network", "last_address", ""))
	local_name = PlayerData.clean_name(str(load_setting("player", "name", PlayerData.DEFAULT_NAME)))

static func game_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))

## Parses "IP" or "IP:port". Empty input means the local default address; the online
## screen rejects empty input itself before calling this (Docs/01 §2.4).
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

static func clean_name(value: String) -> String:
	return PlayerData.clean_name(value)

func load_setting(section: String, key: String, default_value: Variant) -> Variant:
	var settings := ConfigFile.new()
	if settings.load(SETTINGS_PATH) != OK:
		return default_value
	return settings.get_value(section, key, default_value)

func save_setting(section: String, key: String, value: Variant) -> void:
	var settings := ConfigFile.new()
	settings.load(SETTINGS_PATH)
	settings.set_value(section, key, value)
	var error := settings.save(SETTINGS_PATH)
	if error != OK:
		push_warning("Could not save %s/%s: %s" % [section, key, error_string(error)])

# Rooms -----------------------------------------------------------------------

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
	_open_room(ScreenTypes.RoomMode.ONLINE, "%s:%d" % [local_ipv4(), port])
	changed.emit()
	return OK

## Training room (Docs/01 §4.2): offline, alone, no invites.
func start_training() -> void:
	leave()
	_open_room(ScreenTypes.RoomMode.TRAINING, "")
	changed.emit()

## Two players on one keyboard (test helper; P1 WASD/J, P2 arrows/K).
func local_game() -> void:
	leave()
	local_mode = true
	_open_room(ScreenTypes.RoomMode.ONLINE, "")
	room.players[0].display_name = "P1"
	room.add_player(PlayerData.create(2, "P2", catalog.default_character()))
	changed.emit()

func _open_room(mode: ScreenTypes.RoomMode, address: String) -> void:
	var round_generation := room.generation
	room = RoomState.new()
	room.mode = mode
	room.address = address
	room.generation = round_generation
	room.map = catalog.default_map()
	room.add_player(PlayerData.create(1, local_name, catalog.default_character()))
	phase = Phase.LOBBY

## Opens the existing lobby UI from a Cloudflare room without starting an ENet server.
func open_cloud_room(room_name: String, state: Dictionary) -> void:
	leave()
	cloud_room = true
	_cloud_room_name = RoomState.clean_name(room_name)
	phase = Phase.LOBBY
	_sync_cloud_room(state)

func _sync_cloud_room(state: Dictionary) -> void:
	if not cloud_room or not state.get("players", []) is Array:
		return
	var previous_phase := phase
	var server_in_game := str(state.get("status", "lobby")) == "in_game"
	var next_room := RoomState.new()
	next_room.mode = ScreenTypes.RoomMode.ONLINE
	next_room.phase = previous_phase if server_in_game and previous_phase in [Phase.PLAYING, Phase.RESULT] else Phase.LOBBY
	next_room.address = OnlineClient.room_id
	next_room.name = RoomState.clean_name(str(state.get("name", _cloud_room_name)))
	next_room.max_players = clampi(int(state.get("max_players", MAX_PLAYERS)), RoomState.MIN_PLAYERS, MAX_PLAYERS)
	next_room.map = catalog.default_map()
	var map_id := StringName(str(state.get("map_id", next_room.map)))
	if catalog.is_valid_map(map_id):
		next_room.map = map_id
	next_room.stocks = clampi(int(state.get("stocks", CombatRules.INITIAL_STOCKS)), 1, 9)
	for value: Variant in state.get("players", []):
		if not value is Dictionary:
			continue
		var player: Dictionary = value
		var slot := clampi(int(player.get("slot", next_room.players.size() + 1)), 1, MAX_PLAYERS)
		var character := StringName(str(player.get("character_id", "")))
		if not catalog.is_valid_character(character):
			character = catalog.default_character()
		var entry := PlayerData.create(slot, str(player.get("display_name", PlayerData.DEFAULT_NAME)), character)
		entry.is_ready = bool(player.get("ready", false))
		next_room.add_player(entry)
	room = next_room
	phase = next_room.phase as Phase
	changed.emit()

func join_address(text: String, player_name: String = PlayerData.DEFAULT_NAME) -> Error:
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
	phase = Phase.CONNECTING
	join_error = ""
	_pending_address = address.strip_edges() if port == DEFAULT_PORT else "%s:%d" % [address.strip_edges(), port]
	room.address = "%s:%d" % [address.strip_edges(), port]
	join_started = Time.get_ticks_msec()
	changed.emit()
	return OK

## Offline rooms (training, local test) run the host handlers directly instead of RPCs.
func is_offline() -> bool:
	return local_mode or training_mode

func is_host() -> bool:
	if cloud_room:
		return not OnlineClient.local_player_id.is_empty() and str(OnlineClient.room_state.get("host_id", "")) == OnlineClient.local_player_id
	return is_offline() or multiplayer.is_server()

func my_id() -> int:
	if cloud_room:
		for value: Variant in OnlineClient.room_state.get("players", []):
			if value is Dictionary:
				var player: Dictionary = value
				if str(player.get("player_id", "")) == OnlineClient.local_player_id:
					return int(player.get("slot", 1))
		return 1
	return 1 if is_offline() else multiplayer.get_unique_id()

func slot_of(id: int) -> int:
	return room.slot_of(id)

## Ready count excludes the host (design: pressing start is the host's ready).
func ready_count() -> int:
	return room.ready_count()

func all_ready() -> bool:
	return is_offline() or ready_count() == room.players.size() - 1

## Online: two or more players and every participant ready. Training: always (Docs/02 §1.1).
func can_start() -> bool:
	if phase != Phase.LOBBY or not is_host() or catalog.characters.is_empty() or catalog.maps.is_empty():
		return false
	if training_mode:
		return true
	if room.players.size() < RoomState.MIN_PLAYERS or not all_ready():
		return false
	return not cloud_room or OnlineClient.is_mesh_ready()

func start_game() -> bool:
	if not can_start():
		return false
	if cloud_room:
		OnlineClient.start_match()
		return true
	room.generation += 1
	var setup := MatchSetup.new()
	setup.generation = room.generation
	setup.seed = _rng.randi()
	setup.room_mode = room.mode
	setup.map = _resolve_pick(room.map, catalog.maps.size())
	setup.participants = room.ids()
	for entry in room.players:
		setup.characters[entry.peer_id] = _resolve_character(entry.character)
	if training_mode:
		setup.participants.append(TRAINING_DUMMY_ID)
		setup.dummy_ids.append(TRAINING_DUMMY_ID)
		setup.characters[TRAINING_DUMMY_ID] = catalog.default_character()
	setup.participants.sort()
	if is_offline():
		_begin_match(setup.to_dict())
	else:
		_begin_match.rpc(setup.to_dict())
	return true

## Random picks are fixed here with the host RNG so every peer sees the same result.
func _resolve_character(pick: StringName) -> StringName:
	if pick != ContentCatalog.RANDOM:
		return pick
	return catalog.characters[_rng.randi_range(0, catalog.characters.size() - 1)].id

func _resolve_pick(pick: StringName, count: int) -> StringName:
	if pick != ContentCatalog.RANDOM or count == 0:
		return pick
	return catalog.maps[_rng.randi_range(0, count - 1)].id

func set_ready(value: bool) -> void:
	if phase != Phase.LOBBY or is_host():
		return
	var me := room.player(my_id())
	if me != null:
		me.is_ready = value
	changed.emit()
	if cloud_room:
		OnlineClient.set_ready(value)
		return
	_request_ready.rpc_id(1, value)

@rpc("any_peer", "call_remote", "reliable")
func _request_ready(value: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var entry := room.player(sender)
	if phase != Phase.LOBBY or entry == null or sender == 1:
		return
	entry.is_ready = value
	_publish_lobby()

func set_character(pick: StringName) -> void:
	if phase != Phase.LOBBY or not catalog.is_valid_character(pick):
		return
	if cloud_room:
		if _apply_character(my_id(), pick):
			changed.emit()
			OnlineClient.set_character(String(pick))
		return
	if is_host():
		if _apply_character(my_id(), pick):
			_publish_lobby()
	else:
		_request_character.rpc_id(1, String(pick))

@rpc("any_peer", "call_remote", "reliable")
func _request_character(pick: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if phase != Phase.LOBBY or not room.has_player(sender):
		return
	if _apply_character(sender, StringName(pick)):
		_publish_lobby()

func _apply_character(id: int, pick: StringName) -> bool:
	var entry := room.player(id)
	if entry == null or not catalog.is_valid_character(pick):
		push_warning("Rejected character %s for %d" % [pick, id])
		return false
	if entry.is_ready:
		# Ready players are locked (Docs/02 §5).
		return false
	entry.character = pick
	return true

## Host only. Keys: name (String, 12), max_players (2..4, >= players), map (catalog id or random).
func update_room(patch: Dictionary) -> void:
	if phase != Phase.LOBBY:
		return
	if not is_host():
		push_warning("Only the host can change room settings")
		return
	if cloud_room:
		var cloud_patch: Dictionary = {}
		if patch.has("name"):
			cloud_patch.name = RoomState.clean_name(str(patch.name))
		if patch.has("max_players"):
			cloud_patch.max_players = int(patch.max_players)
		if patch.has("map"):
			cloud_patch.map_id = String(patch.map)
		if patch.has("stocks"):
			cloud_patch.stocks = int(patch.stocks)
		OnlineClient.update_room(cloud_patch)
		return
	if _apply_room_patch(patch):
		_publish_lobby()

@rpc("any_peer", "call_remote", "reliable")
func _request_room_update(patch: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 1:
		push_warning("Room update from non-host %d ignored" % sender)
		return
	if phase == Phase.LOBBY and _apply_room_patch(patch):
		_publish_lobby()

func _apply_room_patch(patch: Dictionary) -> bool:
	var applied := false
	for key in patch:
		var value: Variant = patch[key]
		if key == "name" and value is String:
			room.name = RoomState.clean_name(value)
			applied = true
		elif key == "max_players" and value is int and value >= RoomState.MIN_PLAYERS and value <= RoomState.MAX_PLAYERS and value >= room.players.size():
			room.max_players = value
			applied = true
		elif key == "map" and (value is String or value is StringName) and catalog.is_valid_map(StringName(value)):
			room.map = StringName(value)
			applied = true
		else:
			push_warning("Ignored room setting %s = %s" % [key, value])
	return applied

func set_display_name(value: String) -> void:
	local_name = clean_name(value)
	save_setting("player", "name", local_name)
	if phase != Phase.LOBBY:
		return
	if cloud_room:
		OnlineClient.set_display_name(local_name)
		return
	if is_host():
		var me := room.player(my_id())
		if me != null:
			me.display_name = local_name
		_publish_lobby()
	else:
		_request_name.rpc_id(1, local_name)

@rpc("any_peer", "call_remote", "reliable")
func _request_name(value: String) -> void:
	if not multiplayer.is_server():
		return
	var entry := room.player(multiplayer.get_remote_sender_id())
	if phase != Phase.LOBBY or entry == null:
		return
	entry.display_name = clean_name(value)
	_publish_lobby()

## Speech bubble chat (online only). Not stored: late joiners never see earlier lines.
func send_chat(text: String) -> void:
	var clean := _clean_chat(text)
	if clean.is_empty() or phase != Phase.LOBBY or is_offline():
		return
	if cloud_room:
		OnlineClient.send_chat(clean)
		return
	if multiplayer.is_server():
		_accept_chat(1, clean)
	else:
		_request_chat.rpc_id(1, clean)

static func _clean_chat(text: String) -> String:
	return text.replace("\n", " ").replace("\r", " ").strip_edges().left(CHAT_MAX_LENGTH)

@rpc("any_peer", "call_remote", "reliable")
func _request_chat(text: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if phase != Phase.LOBBY or not room.has_player(sender):
		return
	var clean := _clean_chat(text)
	if not clean.is_empty():
		_accept_chat(sender, clean)

func _accept_chat(sender: int, text: String) -> void:
	var now := Time.get_ticks_msec()
	if _chat_times.has(sender) and now - int(_chat_times[sender]) < CHAT_MIN_INTERVAL_MSEC:
		return
	_chat_times[sender] = now
	_chat.rpc(sender, text)

@rpc("authority", "call_local", "reliable")
func _chat(peer_id: int, text: String) -> void:
	chat_received.emit(peer_id, text)

## Host removes a participant. Rejoining afterwards is allowed (Docs/02 decision 14).
func kick(peer_id: int) -> void:
	if cloud_room and phase == Phase.LOBBY and is_host() and peer_id != my_id():
		var player_id := OnlineClient.player_id_for_slot(peer_id)
		if not player_id.is_empty():
			OnlineClient.kick_player(player_id)
		return
	if phase != Phase.LOBBY or is_offline() or not multiplayer.is_server() or peer_id == 1 or not room.has_player(peer_id):
		return
	_kicked.rpc_id(peer_id)
	var packet_peer := (multiplayer.multiplayer_peer as ENetMultiplayerPeer).get_peer(peer_id)
	if packet_peer != null:
		packet_peer.peer_disconnect_later()

@rpc("authority", "call_remote", "reliable")
func _kicked() -> void:
	leave()
	toast = UiStyle.KICKED
	changed.emit()

## Lobby [나가기]. The host closes the room for everyone; a participant just leaves.
func leave_room() -> void:
	if cloud_room:
		OnlineClient.disconnect_room()
		leave()
		return
	if phase != Phase.LOBBY or is_offline() or not multiplayer.is_server() or multiplayer.get_peers().is_empty():
		leave()
		return
	_room_closed.rpc()
	phase = Phase.CLOSING
	changed.emit()
	await get_tree().create_timer(CLOSE_FLUSH_SECONDS).timeout
	if phase == Phase.CLOSING:
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
	var round_generation := room.generation
	room = RoomState.new()
	room.generation = round_generation
	phase = Phase.MENU
	match_setup = null
	confirmed.clear()
	input_masks.clear()
	input_times.clear()
	_reset_rollback()
	_chat_times.clear()
	local_mode = false
	cloud_room = false
	_cloud_room_name = ""
	_cloud_match_id = ""
	_cloud_match_start_msec = 0.0
	changed.emit()

func cancel_join() -> void:
	join_error = ""
	if phase == Phase.CONNECTING:
		leave()

func _process(_delta: float) -> void:
	if phase == Phase.CONNECTING and Time.get_ticks_msec() - join_started > JOIN_TIMEOUT_MSEC:
		_connection_failed()

func _connected() -> void:
	_register.rpc_id(1, local_name, game_version())

func _peer_joined(id: int) -> void:
	if not multiplayer.is_server():
		return
	if phase != Phase.LOBBY:
		_reject(id, JoinRejection.IN_PROGRESS)
	elif multiplayer.get_peers().size() >= room.max_players:
		_reject(id, JoinRejection.FULL)

func _reject(id: int, reason: JoinRejection) -> void:
	_join_rejected.rpc_id(id, reason)
	# disconnect_later lets the queued rejection reason reach the client first.
	var packet_peer := (multiplayer.multiplayer_peer as ENetMultiplayerPeer).get_peer(id)
	if packet_peer != null:
		packet_peer.peer_disconnect_later()

@rpc("authority", "call_remote", "reliable")
func _join_rejected(reason: int) -> void:
	if phase != Phase.CONNECTING:
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
	var was_connecting := phase == Phase.CONNECTING
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
	if sender <= 1 or room.has_player(sender):
		return
	if phase != Phase.LOBBY:
		_reject(sender, JoinRejection.IN_PROGRESS)
		return
	if room.players.size() >= room.max_players:
		_reject(sender, JoinRejection.FULL)
		return
	if version != game_version():
		_reject(sender, JoinRejection.VERSION)
		return
	room.add_player(PlayerData.create(sender, player_name, catalog.default_character()))
	room.notice = UiStyle.JOINED % room.slot_of(sender)
	_publish_lobby()

## The notice rides along once; later updates carry "" so the lobby toast is not repeated.
func _publish_lobby() -> void:
	changed.emit()
	if cloud_room:
		return
	if not is_offline():
		_lobby_state.rpc(room.to_dict())
	room.notice = ""

@rpc("authority", "call_remote", "reliable")
func _lobby_state(data: Dictionary) -> void:
	var parsed := RoomState.from_dict(data, catalog)
	if parsed == null:
		return
	if phase == Phase.CONNECTING:
		_remember_address(_pending_address)
	parsed.address = room.address
	room = parsed
	phase = Phase.LOBBY
	changed.emit()

func _remember_address(address: String) -> void:
	last_address = address
	save_setting("network", "last_address", address)

func _on_cloud_chat(remote_id: String, text: String) -> void:
	if not cloud_room or phase != Phase.LOBBY:
		return
	var slot := OnlineClient.slot_for_player_id(remote_id)
	if slot > 0:
		chat_received.emit(slot, _clean_chat(text))

func _on_cloud_kicked() -> void:
	if not cloud_room:
		return
	OnlineClient.disconnect_room()
	leave()
	toast = UiStyle.KICKED
	changed.emit()

func _on_cloud_connection_changed(connected: bool) -> void:
	if connected or not cloud_room or phase == Phase.MENU:
		return
	leave()
	toast = UiStyle.HOST_LOST
	changed.emit()

func _on_cloud_mesh_status_changed(_ready_count: int, _total_count: int, failed: bool) -> void:
	if not cloud_room or phase != Phase.LOBBY:
		return
	if failed:
		room.notice = UiStyle.P2P_CONNECTION_FAILED
	changed.emit()

func _on_cloud_match_connection_progress(ready_count: int, total_count: int) -> void:
	if not cloud_room or phase != Phase.LOBBY:
		return
	room.notice = UiStyle.P2P_CONNECTING % [ready_count, total_count]
	changed.emit()

func _on_cloud_match_connection_failed() -> void:
	if not cloud_room or phase != Phase.LOBBY:
		return
	room.notice = UiStyle.P2P_CONNECTION_FAILED
	changed.emit()
	if is_host():
		OnlineClient.return_lobby()

func _on_cloud_match_started(data: Dictionary) -> void:
	if not cloud_room or phase != Phase.LOBBY:
		return
	var match_id := str(data.get("match_id", ""))
	if match_id.is_empty() or match_id == _cloud_match_id or not data.get("players", []) is Array:
		return
	_cloud_match_id = match_id
	_cloud_match_start_msec = float(data.get("start_at_ms", 0))
	var setup := MatchSetup.new()
	setup.generation = room.generation + 1
	setup.seed = int(data.get("seed", 1))
	setup.room_mode = ScreenTypes.RoomMode.ONLINE
	setup.map = catalog.checked_map(StringName(str(data.get("map_id", room.map))))
	room.stocks = clampi(int(data.get("stocks", room.stocks)), 1, 9)
	for value: Variant in data.players:
		if not value is Dictionary:
			continue
		var player: Dictionary = value
		var slot := int(player.get("slot", 0))
		if slot < 1 or slot > MAX_PLAYERS:
			continue
		setup.participants.append(slot)
		var character := StringName(str(player.get("character_id", "")))
		setup.characters[slot] = character if catalog.is_valid_character(character) else catalog.default_character()
	if setup.participants.size() < RoomState.MIN_PLAYERS:
		return
	setup.participants.sort()
	var wait_seconds := maxf(0.0, (_cloud_match_start_msec - OnlineClient.server_time_msec()) / 1000.0)
	if wait_seconds > 0.0:
		await get_tree().create_timer(minf(wait_seconds, 2.0)).timeout
	if cloud_room and phase == Phase.LOBBY and _cloud_match_id == match_id:
		_begin_match(setup.to_dict())

func _on_cloud_lobby_returned() -> void:
	if not cloud_room:
		return
	_back_to_lobby(room.to_dict())

# Match -----------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _begin_match(setup_data: Dictionary) -> void:
	var setup := MatchSetup.from_dict(setup_data)
	if setup == null:
		push_error("Match start ignored: bad setup")
		return
	match_setup = setup
	room.generation = setup.generation
	phase = Phase.PLAYING
	room.notice = ""
	confirmed.clear()
	input_masks.clear()
	input_times.clear()
	_reset_rollback()
	if is_instance_valid(arena):
		remove_child(arena)
		arena.queue_free()
	arena = preload("res://arena.tscn").instantiate()
	arena.name = "Arena"
	arena.standalone = false
	arena.authoritative = cloud_room or is_host()
	arena.simulation_seed = setup.seed
	arena.starting_stocks = room.stocks
	arena.local_player_id = 0 if local_mode else my_id()
	arena.participant_ids.assign(setup.participants)
	arena.dummy_ids.assign(setup.dummy_ids)
	arena.input_provider = input_for
	add_child(arena)
	if cloud_room:
		arena.set_physics_process(false)
		arena.tick_completed.connect(_on_cloud_tick_completed)
		arena.match_finished.connect(_finished)
		_rollback_states[0] = arena.snapshot().duplicate(true)
	elif arena.authoritative:
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
	if phase != Phase.PLAYING:
		return
	if cloud_room and is_instance_valid(arena):
		var tick := arena.frame + ROLLBACK_INPUT_DELAY
		_store_rollback_input(tick, my_id(), mask & 63, true)
		var recent: Array[Dictionary] = []
		for past_tick: int in range(maxi(0, tick - ROLLBACK_REDUNDANCY + 1), tick + 1):
			var values: Dictionary = _rollback_inputs.get(past_tick, {})
			if values.has(my_id()):
				recent.append({"tick": past_tick, "buttons": int(values[my_id()])})
		OnlineClient.send_game_packet({"type": "input", "match_id": _cloud_match_id, "latest_tick": tick, "recent": recent})
		return
	if is_host():
		_store_input(my_id(), mask)
	else:
		_submit_input.rpc_id(1, mask, room.generation)

@rpc("any_peer", "call_remote", "reliable", 2)
func _submit_input(mask: int, round_generation: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if multiplayer.is_server() and phase == Phase.PLAYING and round_generation == room.generation and room.has_player(sender):
		_store_input(sender, mask)

func _store_input(id: int, mask: int) -> void:
	input_masks[id] = mask & 63
	input_times[id] = Time.get_ticks_msec()

func input_for(id: int) -> int:
	if cloud_room and is_instance_valid(arena):
		var tick := arena.frame
		var values: Dictionary = _rollback_inputs.get(tick, {})
		var mask := int(values.get(id, _predicted_input(id, tick)))
		var used: Dictionary = _rollback_used.get(tick, {})
		used[id] = mask
		_rollback_used[tick] = used
		return mask
	if local_mode:
		var keys: Array[Key] = [KEY_A, KEY_D, KEY_W, KEY_J]
		if id == 2:
			keys = [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_K]
		return Fighter.read_keyboard(keys, KEY_S if id == 1 else KEY_DOWN)
	if Time.get_ticks_msec() - int(input_times.get(id, 0)) > INPUT_STALE_MSEC:
		return 0
	return int(input_masks.get(id, 0))

func _reset_rollback() -> void:
	_rollback_inputs.clear()
	_rollback_used.clear()
	_rollback_states.clear()
	_rollback_hashes.clear()
	_pending_rollback_tick = -1
	_resimulating = false
	rollback_count = 0
	desync_count = 0
	repair_count = 0
	_last_repair_sent_msec.clear()

func _predicted_input(id: int, tick: int) -> int:
	for previous: int in range(tick - 1, maxi(-1, tick - ROLLBACK_MAX_TICKS - 1), -1):
		var values: Dictionary = _rollback_inputs.get(previous, {})
		if values.has(id):
			return int(values[id])
	return 0

func _store_rollback_input(tick: int, id: int, mask: int, actual: bool) -> void:
	if tick < 0 or id < 1 or id > MAX_PLAYERS:
		return
	var values: Dictionary = _rollback_inputs.get(tick, {})
	values[id] = mask & 63
	_rollback_inputs[tick] = values
	if actual and is_instance_valid(arena) and tick < arena.frame:
		var used: Dictionary = _rollback_used.get(tick, {})
		if used.has(id) and int(used[id]) != (mask & 63):
			if tick >= arena.frame - ROLLBACK_MAX_TICKS:
				_pending_rollback_tick = tick if _pending_rollback_tick < 0 else mini(_pending_rollback_tick, tick)
			else:
				push_warning("Rollback input arrived too late: tick %d, current %d" % [tick, arena.frame])

func _on_cloud_data_received(remote_id: String, message_value: Variant) -> void:
	if not cloud_room or not message_value is Dictionary:
		return
	var message: Dictionary = message_value
	var message_type := str(message.get("type", ""))
	if message_type in ["input", "state_hash", "state_repair", "result_confirm"] and str(message.get("match_id", "")) != _cloud_match_id:
		return
	match message_type:
		"input":
			var slot := OnlineClient.slot_for_player_id(remote_id)
			if slot < 1 or not message.get("recent", []) is Array:
				return
			for value: Variant in message.recent:
				if value is Dictionary:
					var entry: Dictionary = value
					_store_rollback_input(int(entry.get("tick", -1)), slot, int(entry.get("buttons", 0)), true)
		"state_hash":
			_handle_remote_state_hash(remote_id, message)
		"state_repair":
			if str(message.get("target", "")) == OnlineClient.local_player_id and remote_id == str(OnlineClient.room_state.get("host_id", "")) and message.get("state") is Dictionary:
				_apply_state_repair(message.state)
		"result_confirm":
			var slot := OnlineClient.slot_for_player_id(remote_id)
			if slot > 0:
				_record_confirm(slot)

func _on_cloud_tick_completed(state: Dictionary) -> void:
	var tick := int(state.get("frame", 0))
	_rollback_states[tick] = state.duplicate(true)
	var oldest := tick - SYNC_HISTORY_TICKS
	for history: Dictionary in [_rollback_states, _rollback_inputs, _rollback_used, _rollback_hashes]:
		for key: Variant in history.keys():
			if int(key) < oldest:
				history.erase(key)
	if tick > 0 and tick % ROLLBACK_HASH_INTERVAL == 0:
		var state_hash := _rollback_state_hash(state)
		_rollback_hashes[tick] = state_hash
		if not _resimulating:
			OnlineClient.send_game_packet({"type": "state_hash", "match_id": _cloud_match_id, "tick": tick, "hash": state_hash})

func _handle_remote_state_hash(remote_id: String, message: Dictionary) -> void:
	var tick := int(message.get("tick", -1))
	if tick < 0 or not is_instance_valid(arena):
		return
	var mismatch := false
	var reason := ""
	if _rollback_hashes.has(tick):
		mismatch = int(_rollback_hashes[tick]) != int(message.get("hash", 0))
		reason = "hash mismatch"
	elif is_host() and absi(arena.frame - tick) > ROLLBACK_MAX_TICKS:
		mismatch = true
		reason = "tick gap %d" % (arena.frame - tick)
	if not mismatch:
		return
	desync_count += 1
	OnlineClient.report_sync_event("DESYNC tick=%d %s" % [tick, reason])
	if is_host():
		_send_state_repair(remote_id, reason)

func _send_state_repair(remote_id: String, reason: String) -> void:
	if not is_instance_valid(arena):
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_repair_sent_msec.get(remote_id, -STATE_REPAIR_COOLDOWN_MSEC)) < STATE_REPAIR_COOLDOWN_MSEC:
		return
	_last_repair_sent_msec[remote_id] = now
	OnlineClient.send_game_packet({
		"type": "state_repair",
		"match_id": _cloud_match_id,
		"target": remote_id,
		"reason": reason,
		"state": arena.snapshot()
	})
	OnlineClient.report_sync_event("REPAIR sent tick=%d -> %s" % [arena.frame, remote_id.left(6)])

func _apply_state_repair(state: Dictionary) -> void:
	if not is_instance_valid(arena) or not state.get("frame") is int:
		return
	arena.restore_snapshot(state)
	_rollback_inputs.clear()
	_rollback_used.clear()
	_rollback_states.clear()
	_rollback_hashes.clear()
	_pending_rollback_tick = -1
	_resimulating = false
	var repaired_state := arena.snapshot().duplicate(true)
	_rollback_states[arena.frame] = repaired_state
	if arena.frame > 0 and arena.frame % ROLLBACK_HASH_INTERVAL == 0:
		_rollback_hashes[arena.frame] = _rollback_state_hash(repaired_state)
	repair_count += 1
	OnlineClient.report_sync_event("REPAIR applied tick=%d" % arena.frame)

func _rollback_state_hash(state: Dictionary) -> int:
	var parts := PackedStringArray([str(state.get("frame", 0)), str(state.get("winner", 0))])
	for value: Variant in state.get("players", []):
		if value is Dictionary:
			var player: Dictionary = value
			var position: Vector2 = player.get("position", Vector2.ZERO)
			var velocity: Vector2 = player.get("velocity", Vector2.ZERO)
			parts.append("%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%s" % [
				int(player.get("id", 0)), roundi(position.x * 100.0), roundi(position.y * 100.0),
				roundi(velocity.x * 100.0), roundi(velocity.y * 100.0), int(player.get("stocks", 0)),
				roundi(float(player.get("percent", 0.0)) * 100.0), int(player.get("life", 0)),
				roundi(float(player.get("hitstun", 0.0)) * 1000.0), roundi(float(player.get("cooldown", 0.0)) * 1000.0),
				int(player.get("jumps", 0)), roundi(float(player.get("facing", 0.0))), str(player.get("kind", ""))])
	return hash("|".join(parts))

func _physics_process(_delta: float) -> void:
	if not cloud_room or phase != Phase.PLAYING or not is_instance_valid(arena):
		return
	_apply_pending_rollback()
	_advance_to_cloud_tick()

func _apply_pending_rollback() -> void:
	if _pending_rollback_tick < 0:
		return
	var target_tick := arena.frame
	var rollback_tick := maxi(_pending_rollback_tick, target_tick - ROLLBACK_MAX_TICKS)
	_pending_rollback_tick = -1
	if not _rollback_states.has(rollback_tick):
		return
	_resimulating = true
	rollback_count += 1
	arena.restore_snapshot(_rollback_states[rollback_tick])
	while arena.frame < target_tick and phase == Phase.PLAYING:
		arena.simulate_tick(FIXED_TICK_SECONDS)
	_resimulating = false

func _advance_to_cloud_tick() -> void:
	if _cloud_match_start_msec <= 0.0 or not OnlineClient.has_server_time_sync():
		return
	var elapsed_msec := maxf(0.0, OnlineClient.server_time_msec() - _cloud_match_start_msec)
	var expected_tick := int(floor(elapsed_msec / (FIXED_TICK_SECONDS * 1000.0)))
	var steps := clampi(expected_tick - arena.frame, 0, CLOCK_MAX_CATCHUP_TICKS)
	for _step: int in range(steps):
		if phase != Phase.PLAYING or arena.ended:
			break
		arena.simulate_tick(FIXED_TICK_SECONDS)
	OnlineClient.update_game_sync_stats(arena.frame, expected_tick, desync_count, repair_count)

func _broadcast_snapshot(state: Dictionary) -> void:
	if not is_offline() and multiplayer.get_peers().size() > 0:
		_world_state.rpc(state, room.generation)

@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _world_state(state: Dictionary, round_generation: int) -> void:
	if is_instance_valid(arena) and room.generation == round_generation:
		arena.apply_snapshot(state)

func _finished(_winner_id: int) -> void:
	phase = Phase.RESULT
	confirmed.clear()
	if not is_offline() and multiplayer.get_peers().size() > 0:
		_final_state.rpc(arena.snapshot(), room.generation)
	changed.emit()

@rpc("authority", "call_remote", "reliable")
func _final_state(state: Dictionary, round_generation: int) -> void:
	if is_instance_valid(arena) and room.generation == round_generation:
		arena.apply_snapshot(state)
		phase = Phase.RESULT
		confirmed.clear()
		changed.emit()

## Result of the current match, built from the replicated arena (null outside a match).
func match_result() -> MatchResult:
	if not is_instance_valid(arena):
		return null
	return MatchResult.from_arena(arena, room, room.generation)

## S4 Enter. Everyone still in the room must confirm before the shared return to the lobby.
func confirm_result() -> void:
	if phase != Phase.RESULT:
		return
	if cloud_room:
		var id := my_id()
		if not confirmed.get(id, false):
			confirmed[id] = true
			changed.emit()
			OnlineClient.send_game_packet({"type": "result_confirm", "match_id": _cloud_match_id})
			if is_host():
				_check_confirmations()
		return
	if is_offline():
		return_to_lobby()
	elif multiplayer.is_server():
		_record_confirm(1)
	elif not confirmed.get(my_id(), false):
		confirmed[my_id()] = true
		changed.emit()
		_request_confirm.rpc_id(1, room.generation)

@rpc("any_peer", "call_remote", "reliable")
func _request_confirm(round_generation: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if phase == Phase.RESULT and round_generation == room.generation and room.has_player(sender):
		_record_confirm(sender)

func _record_confirm(id: int) -> void:
	confirmed[id] = true
	_check_confirmations()

func _check_confirmations() -> void:
	if phase != Phase.RESULT:
		return
	for id in room.ids():
		if not confirmed.get(id, false):
			changed.emit()
			if not is_offline() and not cloud_room:
				_confirm_state.rpc(confirmed, room.generation)
			return
	return_to_lobby()

@rpc("authority", "call_remote", "reliable")
func _confirm_state(states: Dictionary, round_generation: int) -> void:
	if phase == Phase.RESULT and round_generation == room.generation:
		confirmed = states
		changed.emit()

## Host-only shared return to the same room's lobby with readiness cleared.
func return_to_lobby() -> void:
	if phase != Phase.RESULT or not is_host():
		return
	if cloud_room:
		OnlineClient.return_lobby()
		return
	for entry in room.players:
		entry.is_ready = false
	room.notice = ""
	if is_offline():
		_back_to_lobby(room.to_dict())
	else:
		_back_to_lobby.rpc(room.to_dict())

@rpc("authority", "call_local", "reliable")
func _back_to_lobby(data: Dictionary) -> void:
	var parsed := RoomState.from_dict(data, catalog)
	if parsed != null:
		parsed.address = room.address
		room = parsed
	if is_instance_valid(arena):
		arena.queue_free()
	arena = null
	match_setup = null
	phase = Phase.LOBBY
	confirmed.clear()
	input_masks.clear()
	input_times.clear()
	changed.emit()

func _peer_left(id: int) -> void:
	if not multiplayer.is_server() or not room.has_player(id):
		return
	var slot := room.remove_player(id)
	confirmed.erase(id)
	input_masks.erase(id)
	input_times.erase(id)
	_chat_times.erase(id)
	if phase == Phase.LOBBY:
		room.notice = UiStyle.LEFT % slot
		_publish_lobby()
	elif phase == Phase.RESULT:
		_roster_update.rpc(room.to_dict())
		_check_confirmations()
	elif is_instance_valid(arena):
		_roster_update.rpc(room.to_dict())
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
func _roster_update(data: Dictionary) -> void:
	var parsed := RoomState.from_dict(data, catalog)
	if parsed == null:
		return
	parsed.address = room.address
	parsed.phase = room.phase
	room = parsed
	changed.emit()
