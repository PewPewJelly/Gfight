class_name PlayerData
extends RefCounted
## One player in the room (Docs/00 §3.2). Sent over RPC only as to_dict().

const NAME_MAX_LENGTH: int = 10
const DEFAULT_NAME := "Player"
var peer_id: int = 0
var slot: int = 1
var display_name: String = DEFAULT_NAME
## The host is never ready: pressing start is its ready (Docs/02 decision 4).
var is_ready: bool = false
var character: StringName = &""

static func create(id: int, player_name: String, pick: StringName) -> PlayerData:
	var player := PlayerData.new()
	player.peer_id = id
	player.display_name = clean_name(player_name)
	player.character = pick
	return player

## Trims spaces, removes line breaks, caps at NAME_MAX_LENGTH; empty becomes "Player".
static func clean_name(value: String) -> String:
	var name_value := value.replace("\n", " ").replace("\r", " ").strip_edges().left(NAME_MAX_LENGTH).strip_edges()
	return name_value if not name_value.is_empty() else DEFAULT_NAME

func to_dict() -> Dictionary:
	return {"peer_id": peer_id, "slot": slot, "display_name": display_name, "is_ready": is_ready, "character": String(character)}

## Returns null when keys or types are wrong. Unknown characters fall back to the catalog's first.
static func from_dict(data: Dictionary, catalog: ContentCatalog) -> PlayerData:
	if not (data.get("peer_id") is int and data.get("slot") is int and data.get("display_name") is String
			and data.get("is_ready") is bool and (data.get("character") is String or data.get("character") is StringName)):
		push_warning("Malformed player data: %s" % data)
		return null
	var player := PlayerData.new()
	player.peer_id = data.peer_id
	player.slot = clampi(data.slot, 1, 4)
	player.display_name = clean_name(data.display_name)
	player.is_ready = data.is_ready
	player.character = catalog.checked_character(StringName(data.character))
	return player
