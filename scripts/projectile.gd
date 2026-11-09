class_name Projectile
extends RefCounted
## One live projectile. Everything that changes during its life is here so FightArena can
## save and restore the list as plain values for rollback. Behaviors keep their own values
## in `vars` (plain values only: numbers, strings, Vector2, arrays, dictionaries).

var id: int = 0
var owner_id: int = 0
## Position in FightArena.projectile_types; snapshots cannot carry resources.
var type_index: int = 0
var data: ProjectileData
var position: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
var facing: float = 1.0
## Ticks since it appeared.
var age: int = 0
## Player slots already hit (bit per slot).
var hit_mask: int = 0
## Cleared to remove it at the end of the tick.
var alive: bool = true
var vars: Dictionary = {}

func box() -> Rect2:
	return Rect2(position - data.size / 2.0, data.size)

func snapshot() -> Dictionary:
	return {"id": id, "owner": owner_id, "type": type_index, "position": position,
		"velocity": velocity, "facing": facing, "age": age, "hits": hit_mask, "vars": vars.duplicate(true)}

## Rebuilds a projectile from snapshot(); null when the type is unknown (bad network data).
static func from_snapshot(state: Dictionary, types: Array[ProjectileData]) -> Projectile:
	var type: int = int(state.get("type", -1))
	if type < 0 or type >= types.size():
		push_warning("Snapshot has unknown projectile type %d" % type)
		return null
	var shot := Projectile.new()
	shot.id = int(state.get("id", 0))
	shot.owner_id = int(state.get("owner", 0))
	shot.type_index = type
	shot.data = types[type]
	shot.position = state.get("position", Vector2.ZERO)
	shot.velocity = state.get("velocity", Vector2.ZERO)
	shot.facing = float(state.get("facing", 1.0))
	shot.age = int(state.get("age", 0))
	shot.hit_mask = int(state.get("hits", 0))
	var saved_vars: Dictionary = state.get("vars", {})
	shot.vars = saved_vars.duplicate(true)
	return shot
