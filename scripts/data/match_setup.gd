class_name MatchSetup
extends RefCounted
## What the host fixed when the match started: random picks already resolved (Docs/02 §4.2).

var generation: int = 0
var room_mode: ScreenTypes.RoomMode = ScreenTypes.RoomMode.ONLINE
var map: StringName = &""
## Sorted peer ids taking part. Training adds Session.TRAINING_DUMMY_ID here.
var participants: Array[int] = []
## peer id -> character id (never random).
var characters: Dictionary = {}
## Participants without a player: the training dummy.
var dummy_ids: Array[int] = []

func to_dict() -> Dictionary:
	var picks := {}
	for id in characters:
		picks[id] = String(characters[id])
	return {"generation": generation, "room_mode": int(room_mode), "map": String(map),
		"participants": participants.duplicate(), "characters": picks, "dummy_ids": dummy_ids.duplicate()}

static func from_dict(data: Dictionary) -> MatchSetup:
	if not (data.get("generation") is int and data.get("room_mode") is int and data.get("map") is String
			and data.get("participants") is Array and data.get("characters") is Dictionary and data.get("dummy_ids") is Array):
		push_warning("Malformed match setup")
		return null
	var setup := MatchSetup.new()
	setup.generation = data.generation
	setup.room_mode = clampi(data.room_mode, 0, ScreenTypes.RoomMode.size() - 1) as ScreenTypes.RoomMode
	setup.map = StringName(data.map)
	for id in data.participants:
		if not id is int:
			return null
		setup.participants.append(id)
	for id in data.dummy_ids:
		if not id is int:
			return null
		setup.dummy_ids.append(id)
	for id in data.characters:
		if id is int and data.characters[id] is String:
			setup.characters[id] = StringName(data.characters[id])
	if setup.participants.size() < 2:
		push_warning("Match setup needs two participants")
		return null
	setup.participants.sort()
	return setup
