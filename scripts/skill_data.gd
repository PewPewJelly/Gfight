@tool
class_name SkillData
extends AttackData
## One skill (skill key): a hit like AttackData plus its own cooldown and an optional move
## of the user. A skill with no hit area (reach or width 0) only moves the user.

## Names shown by the character tools (TuningForm).
const SKILL_LABELS := {
	"@Skill": "스킬",
	"cooldown": ["재사용 대기", "이 스킬을 다시 쓸 수 있을 때까지의 시간"],
	"self_velocity": ["자기 이동", "사용 순간 내 속도. 바라보는 쪽 기준이고 위는 y 음수. 0이면 그대로"],
}

@export_group("Skill")
## Seconds before this skill can be used again.
@export_range(0.0, 20.0, 0.05, "or_greater", "suffix:초") var cooldown: float = 1.0
## Velocity given to the user when the skill starts, facing right (x flips when facing
## left, up is negative y). Zero keeps the current velocity.
@export var self_velocity: Vector2 = Vector2.ZERO
