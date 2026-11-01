class_name RoomState
extends RefCounted
## The room this computer is in (Docs/00 §3.3). Only the host changes it; clients replace
## theirs with what the host sends (to_dict / from_dict).

const NAME_MAX_LENGTH: int = 12
const MIN_PLAYERS: int = 2
const MAX_PLAYERS: int = 4
var mode: ScreenTypes.RoomMode = ScreenTypes.RoomMode.NONE
## Session.Phase value. Session.phase reads and writes this field.
var phase: int = 0
## Online "IP:port", training "".
var address: String = ""
## Sorted by peer id; slot follows that order.
var players: Array[PlayerData] = []
var name: String = ""
var max_players: int = MAX_PLAYERS
var map: StringName = &""
var stocks: int = CombatRules.INITIAL_STOCKS
var generation: int = 0
## One-line lobby notice ("P2 님이 들어왔습니다.").
var notice: String = ""

static func clean_name(value: String) -> String:
	return value.replace("\n", " ").replace("\r", " ").strip_edges().left(NAME_MAX_LENGTH)

func player(peer_id: int) -> PlayerData:
	for entry in players:
		if entry.peer_id == peer_id:
			return entry
	return null

func has_player(peer_id: int) -> bool:
	return player(peer_id) != null

func ids() -> Array[int]:
	var result: Array[int] = []
	for entry in players:
		result.append(entry.peer_id)
	return result

func add_player(entry: PlayerData) -> void:
	players.append(entry)
	reassign_slots()

## Returns the slot the player had, or 0 when absent.
func remove_player(peer_id: int) -> int:
	var entry := player(peer_id)
	if entry == null:
		return 0
	players.erase(entry)
	reassign_slots()
	return entry.slot

## Slots are 1..4 in ascending peer id order (Docs/00 §3.2).
func reassign_slots() -> void:
	players.sort_custom(func(a: PlayerData, b: PlayerData) -> bool: return a.peer_id < b.peer_id)
	for index in range(players.size()):
		players[index].slot = index + 1

func slot_of(peer_id: int) -> int:
	var entry := player(peer_id)
	return entry.slot if entry != null else 0

## Ready participants, never counting the host.
func ready_count() -> int:
	var count := 0
	for entry in players:
		if entry.peer_id != 1 and entry.is_ready:
			count += 1
	return count

func to_dict() -> Dictionary:
	var player_dicts: Array = []
	for entry in players:
		player_dicts.append(entry.to_dict())
	return {"mode": int(mode), "players": player_dicts, "name": name, "max_players": max_players,
		"map": String(map), "stocks": stocks, "generation": generation, "notice": notice}

## Returns null when the structure is wrong. Address and phase stay local (not sent).
static func from_dict(data: Dictionary, catalog: ContentCatalog) -> RoomState:
	if not (data.get("mode") is int and data.get("players") is Array and data.get("name") is String
			and data.get("max_players") is int and (data.get("map") is String or data.get("map") is StringName)
			and data.get("stocks") is int and data.get("generation") is int and data.get("notice") is String):
		push_warning("Malformed room data")
		return null
	var room := RoomState.new()
	room.mode = clampi(data.mode, 0, ScreenTypes.RoomMode.size() - 1) as ScreenTypes.RoomMode
	room.name = clean_name(data.name)
	room.max_players = clampi(data.max_players, MIN_PLAYERS, MAX_PLAYERS)
	room.map = catalog.checked_map(StringName(data.map))
	room.stocks = maxi(1, data.stocks)
	room.generation = maxi(0, data.generation)
	room.notice = data.notice
	for entry in data.players:
		if not entry is Dictionary:
			push_warning("Malformed player entry")
			return null
		var parsed := PlayerData.from_dict(entry, catalog)
		if parsed == null or room.has_player(parsed.peer_id):
			return null
		room.players.append(parsed)
	room.reassign_slots()
	return room
