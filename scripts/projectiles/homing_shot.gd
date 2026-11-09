class_name HomingShot
extends ProjectileBehavior
## Steers toward the nearest opponent at the type's launch speed.

## How hard it turns in px/s². Higher values turn more sharply.
@export var turn_rate: float = 1200.0

func step(shot: Projectile, arena: FightArena, delta: float) -> void:
	var target := arena.nearest_fighter(shot.position, shot.owner_id)
	if target != null:
		var wanted := shot.position.direction_to(target.position) * shot.data.speed
		shot.velocity = shot.velocity.move_toward(wanted, turn_rate * delta)
	shot.position += shot.velocity * delta
