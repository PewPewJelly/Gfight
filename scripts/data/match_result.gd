class_name MatchResult
extends RefCounted
## Result of one match (Docs/00 §3.4), built from the arena's replicated fighter state.

var generation: int = 0
## Winner peer id, 0 for a draw.
var winner_id: int = 0
## All participants in slot order.
var entries: Array[MatchResultEntry] = []

static func from_arena(arena: FightArena, room: RoomState, round_generation: int) -> MatchResult:
	var result := MatchResult.new()
	result.generation = round_generation
	result.winner_id = arena.winner_id
	var rank_input: Array[Dictionary] = []
	for fighter in arena.fighters:
		rank_input.append({"id": fighter.player_id, "out": fighter.eliminated_frame})
	var ranks := FightArena.compute_ranks(rank_input)
	for fighter in arena.fighters:
		var entry := MatchResultEntry.new()
		entry.peer_id = fighter.player_id
		entry.slot = fighter.player_slot
		entry.rank = int(ranks[fighter.player_id])
		entry.kills = fighter.kills
		entry.dealt_percent = fighter.dealt_percent
		entry.is_dummy = fighter.is_dummy
		entry.present = fighter.is_dummy or room.has_player(fighter.player_id)
		result.entries.append(entry)
	return result
