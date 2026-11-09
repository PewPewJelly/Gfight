@tool
class_name AttackData
extends HitData
## One basic attack. Field meanings: GDD/characters/character-template.md §7.1.

## Where the hit area sits: in front of the body, above the head, or below the feet.
enum Anchor { FRONT, ABOVE, BELOW }
## FREE keeps walking and jumping during the move; ROOTED blocks both until it ends.
enum MoveLock { FREE, ROOTED }

## Names shown by the character tools (TuningForm).
const ATTACK_LABELS := {
	"reach": ["범위 길이", "몸 가장자리에서 공격 방향으로 뻗는 길이. 0이면 판정 없음"],
	"width": ["범위 폭", "공격 방향과 수직인 두께"],
	"anchor": ["범위 위치", "판정이 놓이는 곳", ["몸 앞", "머리 위", "발밑"]],
	"@Timing": "타이밍",
	"startup_frames": ["선딜", "판정이 나오기 전 프레임 (1/60초)"],
	"active_frames": ["지속", "판정이 유지되는 프레임. 상대마다 한 번만 맞는다"],
	"recovery_frames": ["후딜", "판정이 끝난 뒤 다른 기술을 못 쓰는 프레임"],
	"cooldown_override": ["다음 기술까지", "음수면 이동값의 공격 재사용 대기를 쓴다"],
	"move_lock": ["사용 중 이동", "기술이 끝날 때까지 걷기·점프를 막을지", ["자유", "제자리 고정"]],
	"@Projectiles": "투사체",
	"spawns": ["발사", "이 기술이 쏘는 투사체"],
	"reflects_projectiles": ["투사체 반사", "판정에 닿은 적 투사체를 되돌려 내 것으로 만든다"],
	"@Look": "그림",
	"pose": ["사용 중 그림", "기술을 쓰는 동안 보여 줄 PNG"],
}

@export_range(0.0, 400.0, 1.0, "or_greater", "suffix:px") var reach: float = 80.0
@export_range(0.0, 400.0, 1.0, "or_greater", "suffix:px") var width: float = 70.0
@export var anchor: Anchor = Anchor.FRONT

@export_group("Timing")
## Frames before the hit area goes live (60 per second).
@export_range(0, 60, 1, "or_greater", "suffix:f") var startup_frames: int = 0
## Frames the hit area stays live. Each target is hit once per move.
@export_range(1, 60, 1, "or_greater", "suffix:f") var active_frames: int = 1
## Frames after the hit area ends before another move can start.
@export_range(0, 90, 1, "or_greater", "suffix:f") var recovery_frames: int = 0
## Seconds until the next move. Negative uses the character's MovementSettings.attack_cooldown.
@export_range(-1.0, 3.0, 0.01, "or_greater", "suffix:초") var cooldown_override: float = -1.0
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

## Hit area relative to the center of a body with this half size.
func hit_box(half_size: Vector2, facing: float) -> Rect2:
	if anchor == Anchor.ABOVE:
		return Rect2(Vector2(-width / 2.0, -half_size.y - reach), Vector2(width, reach))
	if anchor == Anchor.BELOW:
		return Rect2(Vector2(-width / 2.0, half_size.y), Vector2(width, reach))
	return Rect2(Vector2(half_size.x if facing > 0 else -half_size.x - reach, -width / 2.0), Vector2(reach, width))
