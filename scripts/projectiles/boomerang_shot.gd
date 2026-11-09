class_name BoomerangShot
extends ProjectileBehavior
## Flies out, then returns to its owner and disappears on arrival. It can hit each target
## once on the way out and once on the way back.

const DISPLAY_NAME := "부메랑"
const LABELS := {
	"outbound_frames": ["돌아오는 시점", "발사 후 방향을 바꿀 때까지의 프레임"],
	"catch_distance": ["회수 거리", "쏜 사람에게 이만큼 가까워지면 사라진다"],
}

## Ticks before it turns around.
@export_range(1, 120, 1, "or_greater", "suffix:f") var outbound_frames: int = 24
## Disappears when this close to its owner, in px.
@export_range(0.0, 200.0, 1.0, "or_greater", "suffix:px") var catch_distance: float = 30.0

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
