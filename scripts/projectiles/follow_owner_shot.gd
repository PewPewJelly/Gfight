class_name FollowOwnerShot
extends ProjectileBehavior
## A hit area glued to its owner that sweeps along an arc: swings and moving melee attacks.
## Set the sweep length with ProjectileData.lifetime_frames. Getting hit ends the swing.

## Distance from the owner's center in px.
@export var radius: float = 60.0
## Sweep start and end while facing right: 0 is straight ahead, negative is upward.
@export var start_degrees: float = -60.0
@export var end_degrees: float = 60.0

func step(shot: Projectile, arena: FightArena, _delta: float) -> void:
	var holder := arena.fighter_by_id(shot.owner_id)
	if holder == null or holder.life_state != Fighter.LifeState.ACTIVE or holder.hitstun_left > 0.0:
		shot.alive = false
		return
	var progress := clampf(float(shot.age) / float(maxi(1, shot.data.lifetime_frames)), 0.0, 1.0)
	var angle := deg_to_rad(lerpf(start_degrees, end_degrees, progress))
	shot.position = holder.position + Vector2(cos(angle) * shot.facing, sin(angle)) * radius
