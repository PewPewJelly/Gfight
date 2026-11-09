@tool
class_name HitData
extends Resource
## What a hit does to its target. Shared by moves (AttackData) and projectiles (ProjectileData).
## Field meanings: GDD/characters/character-template.md §7.1.

## Names shown by the character tools (TuningForm).
const LABELS := {
	"damage": ["피해", "누적 피해 기록. 날아가는 거리에는 영향을 주지 않는다"],
	"percent_increase": ["배율 증가", "맞은 상대의 넉백 배율이 오르는 양"],
	"base_launch_speed": ["발사 속도", "배율 0%일 때 상대가 날아가는 속도"],
	"hitstun_seconds": ["피격 경직", "맞은 상대가 아무것도 못 하는 시간"],
	"launch_direction": ["발사 방향", "오른쪽을 볼 때 기준. 위로 띄우려면 y를 음수로"],
}

@export_range(0.0, 60.0, 0.5, "or_greater") var damage: float = 10.0
@export_range(0.0, 60.0, 0.5, "or_greater", "suffix:%") var percent_increase: float = 12.0
@export_range(0.0, 1200.0, 5.0, "or_greater", "suffix:px/s") var base_launch_speed: float = 420.0
@export_range(0.0, 2.0, 0.01, "or_greater", "suffix:초") var hitstun_seconds: float = 0.35
@export var launch_direction: Vector2 = Vector2(1, -0.35)
