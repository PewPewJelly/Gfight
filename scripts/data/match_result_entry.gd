class_name MatchResultEntry
extends RefCounted
## One participant's line in a MatchResult (Docs/00 §3.4).

var peer_id: int = 0
var slot: int = 1
var rank: int = 1
var kills: int = 0
var dealt_percent: float = 0.0
## Still in the room when the result is shown (the training dummy always counts).
var present: bool = true
var is_dummy: bool = false
