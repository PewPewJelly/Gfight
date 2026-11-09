@tool
class_name ProjectileSpawn
extends Resource
## The trigger on a move: when the move reaches `frame`, launch `count` projectiles.

## Names shown by the character tools (TuningForm).
const LABELS := {
	"projectile": ["투사체", "발사할 투사체의 수치와 동작"],
	"frame": ["발사 프레임", "기술 시작부터 센 프레임. 기술 길이 안이어야 나간다"],
	"offset": ["발사 위치", "몸 중심에서 떨어진 거리. 오른쪽을 볼 때 기준"],
	"angle_degrees": ["발사 각도", "0은 정면, 음수는 위"],
	"count": ["개수", "한 번에 쏘는 개수"],
	"spread_degrees": ["부채꼴 각도", "여러 개를 쏠 때 펼쳐지는 전체 각도"],
}

@export var projectile: ProjectileData
## Frame counted from the start of the move (0 is the frame the move starts).
@export_range(0, 120, 1, "or_greater", "suffix:f") var frame: int = 0
## Launch point from the fighter's center while facing right (x flips with facing).
@export var offset: Vector2 = Vector2(36, 0)
## Launch angle while facing right: 0 is straight ahead, negative is upward.
@export_range(-180.0, 180.0, 1.0, "suffix:도") var angle_degrees: float = 0.0
@export_range(1, 12, 1, "or_greater", "suffix:개") var count: int = 1
## Total fan angle shared across `count` projectiles.
@export_range(0.0, 360.0, 1.0, "suffix:도") var spread_degrees: float = 0.0
