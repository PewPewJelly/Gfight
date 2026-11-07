class_name SkillData
extends AttackData
## One skill (skill key): a hit like AttackData plus its own cooldown and an optional move
## of the user. A skill with no hit area (reach or width 0) only moves the user.
## Startup/active/recovery times and projectiles are not implemented yet
## (GDD/characters/character-template.md §8.3).

## Seconds before this skill can be used again.
@export var cooldown: float = 1.0
## Velocity given to the user when the skill starts, facing right (x flips when facing
## left, up is negative y). Zero keeps the current velocity.
@export var self_velocity: Vector2 = Vector2.ZERO
