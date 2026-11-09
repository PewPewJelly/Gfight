class_name BasicShot
extends ProjectileBehavior
## Straight line, falling arc, or slowing shot depending on its numbers. With speed 0 and a
## long lifetime it is a trap or a lingering zone; with a long hit area and a short lifetime, a beam.

const DISPLAY_NAME := "기본 (직선·포물선·감속·설치·빔)"
const LABELS := {
	"gravity": ["중력", "0이면 직선, 980이면 캐릭터처럼 떨어진다"],
	"deceleration": ["감속", "매초 줄어드는 속도"],
	"vanish_when_stopped": ["멈추면 사라짐", "끄면 수명이 끝날 때까지 그 자리에 남는다"],
}

## Downward pull in px/s². 0 flies straight; 980 falls like a fighter.
@export_range(0.0, 3000.0, 10.0, "or_greater", "suffix:px/s²") var gravity: float = 0.0
## Speed lost every second in px/s.
@export_range(0.0, 3000.0, 10.0, "or_greater", "suffix:px/s²") var deceleration: float = 0.0
## Disappears once deceleration has stopped it. Off leaves it hanging until its lifetime ends.
@export var vanish_when_stopped: bool = false

func step(shot: Projectile, _arena: FightArena, delta: float) -> void:
	if deceleration > 0.0:
		shot.velocity = shot.velocity.move_toward(Vector2.ZERO, deceleration * delta)
		if vanish_when_stopped and shot.velocity.is_zero_approx():
			shot.alive = false
	shot.velocity.y += gravity * delta
	shot.position += shot.velocity * delta
