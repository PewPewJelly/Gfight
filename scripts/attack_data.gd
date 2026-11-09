class_name AttackData
extends HitData
## One basic attack. Field meanings: GDD/characters/character-template.md §7.1.

## Where the hit area sits: in front of the body, above the head, or below the feet.
enum Anchor { FRONT, ABOVE, BELOW }
## FREE keeps walking and jumping during the move; ROOTED blocks both until it ends.
enum MoveLock { FREE, ROOTED }

@export var reach: float = 80.0
@export var width: float = 70.0
@export var anchor: Anchor = Anchor.FRONT

@export_group("Timing")
## Frames before the hit area goes live (60 per second).
@export var startup_frames: int = 0
## Frames the hit area stays live. Each target is hit once per move.
@export var active_frames: int = 1
## Frames after the hit area ends before another move can start.
@export var recovery_frames: int = 0
## Seconds until the next move. Negative uses the character's MovementSettings.attack_cooldown.
@export var cooldown_override: float = -1.0
@export var move_lock: MoveLock = MoveLock.FREE

@export_group("Projectiles")
## Projectiles this move launches, each at its own frame.
@export var spawns: Array[ProjectileSpawn] = []
## While the hit area is live, enemy projectiles touching it turn back and become yours.
@export var reflects_projectiles: bool = false

@export_group("Look")
## PNG shown instead of the standing art while the move runs. Empty keeps the standing art.
@export var pose: Texture2D

## Length of the whole move in frames.
func total_frames() -> int:
	return maxi(0, startup_frames) + maxi(1, active_frames) + maxi(0, recovery_frames)
