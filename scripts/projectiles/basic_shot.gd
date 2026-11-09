class_name BasicShot
extends ProjectileBehavior
## Straight line, falling arc, or slowing shot depending on its numbers. With speed 0 and a
## long lifetime it is a trap or a lingering zone; with a long hit area and a short lifetime, a beam.

## Downward pull in px/s². 0 flies straight; 980 falls like a fighter.
@export var gravity: float = 0.0
## Speed lost every second in px/s.
@export var deceleration: float = 0.0
## Disappears once deceleration has stopped it. Off leaves it hanging until its lifetime ends.
@export var vanish_when_stopped: bool = false

func step(shot: Projectile, _arena: FightArena, delta: float) -> void:
	if deceleration > 0.0:
		shot.velocity = shot.velocity.move_toward(Vector2.ZERO, deceleration * delta)
		if vanish_when_stopped and shot.velocity.is_zero_approx():
			shot.alive = false
	shot.velocity.y += gravity * delta
	shot.position += shot.velocity * delta
