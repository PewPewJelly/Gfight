class_name FollowOwnerShot
extends ProjectileBehavior
## A hit area glued to its owner that sweeps along an arc: swings and moving melee attacks.
## Set the sweep length with ProjectileData.lifetime_frames. Getting hit ends the swing.

const DISPLAY_NAME := "몸에 붙어 휘두르기"
const LABELS := {
	"radius": ["반지름", "몸 중심에서 판정까지의 거리"],
	"start_degrees": ["시작 각도", "오른쪽을 볼 때 기준. 0은 정면, 음수는 위"],
	"end_degrees": ["끝 각도", "오른쪽을 볼 때 기준. 0은 정면, 음수는 위"],
}

## Distance from the owner's center in px.
@export_range(0.0, 300.0, 1.0, "or_greater", "suffix:px") var radius: float = 60.0
## Sweep start and end while facing right: 0 is straight ahead, negative is upward.
@export_range(-180.0, 180.0, 1.0, "suffix:도") var start_degrees: float = -60.0
@export_range(-180.0, 180.0, 1.0, "suffix:도") var end_degrees: float = 60.0

func step(shot: Projectile, arena: FightArena, _delta: float) -> void:
	var holder := arena.fighter_by_id(shot.owner_id)
	if holder == null or holder.life_state != Fighter.LifeState.ACTIVE or holder.hitstun_left > 0.0:
		shot.alive = false
		return
	var progress := clampf(float(shot.age) / float(maxi(1, shot.data.lifetime_frames)), 0.0, 1.0)
	var angle := deg_to_rad(lerpf(start_degrees, end_degrees, progress))
	shot.position = holder.position + Vector2(cos(angle) * shot.facing, sin(angle)) * radius
