class_name HomingShot
extends ProjectileBehavior
## Steers toward the nearest opponent at the type's launch speed.

const DISPLAY_NAME := "유도"
const LABELS := {
	"turn_rate": ["회전력", "높을수록 급하게 꺾는다"],
}

## How hard it turns in px/s². Higher values turn more sharply.
@export_range(0.0, 5000.0, 10.0, "or_greater", "suffix:px/s²") var turn_rate: float = 1200.0

func step(shot: Projectile, arena: FightArena, delta: float) -> void:
	var target := arena.nearest_fighter(shot.position, shot.owner_id)
	if target != null:
		var wanted := shot.position.direction_to(target.position) * shot.data.speed
		shot.velocity = shot.velocity.move_toward(wanted, turn_rate * delta)
	shot.position += shot.velocity * delta
