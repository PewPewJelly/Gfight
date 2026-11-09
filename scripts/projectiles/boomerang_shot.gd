class_name BoomerangShot
extends ProjectileBehavior
## Flies out, then returns to its owner and disappears on arrival. It can hit each target
## once on the way out and once on the way back.

## Ticks before it turns around.
@export var outbound_frames: int = 24
## Disappears when this close to its owner, in px.
@export var catch_distance: float = 30.0

func step(shot: Projectile, arena: FightArena, delta: float) -> void:
	if shot.age == outbound_frames:
		shot.hit_mask = 0
	if shot.age >= outbound_frames:
		var thrower := arena.fighter_by_id(shot.owner_id)
		if thrower == null or thrower.life_state != Fighter.LifeState.ACTIVE:
			shot.alive = false
			return
		shot.velocity = shot.position.direction_to(thrower.position) * shot.data.speed
		if shot.position.distance_to(thrower.position) <= catch_distance:
			shot.alive = false
	shot.position += shot.velocity * delta
