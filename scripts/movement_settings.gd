@tool
class_name MovementSettings
extends Resource

## Names shown by the character tools (TuningForm).
const LABELS := {
	"speed": ["이동 속도", "걷는 최고 속도"],
	"acceleration": ["가속·감속", "최고 속도까지 얼마나 빨리 붙는지"],
	"jump_speed": ["점프 속도", "높을수록 높이 뛴다"],
	"gravity": ["중력", "높을수록 빨리 떨어진다"],
	"drop_seconds": ["아래 통과 시간", "S로 플랫폼을 통과하는 시간"],
	"attack_cooldown": ["공격 재사용 대기", "기술 뒤 다음 기술까지의 기본 시간"],
	"stack_slide_speed": ["머리 위 밀어내기", "다른 플레이어 머리에 떨어졌을 때 옆으로 밀리는 속도"],
}

## Editable prototype policy, not finalized GDD values.
@export_range(0.0, 800.0, 5.0, "or_greater", "suffix:px/s") var speed: float = 260.0
@export_range(0.0, 6000.0, 50.0, "or_greater", "suffix:px/s²") var acceleration: float = 1600.0
@export_range(0.0, 1000.0, 5.0, "or_greater", "suffix:px/s") var jump_speed: float = 460.0
@export_range(0.0, 3000.0, 10.0, "or_greater", "suffix:px/s²") var gravity: float = 980.0
@export_range(0.05, 1.0, 0.01, "or_greater", "suffix:초") var drop_seconds: float = 0.35
@export_range(0.0, 2.0, 0.01, "or_greater", "suffix:초") var attack_cooldown: float = 0.4
## Sideways speed given to a fighter that lands on another fighter's head, so nobody
## can stand on top of a player (prototype value).
@export_range(0.0, 800.0, 5.0, "or_greater", "suffix:px/s") var stack_slide_speed: float = 300.0
