class_name MovementSettings
extends Resource

## Editable prototype policy, not finalized GDD values.
@export var speed: float = 260.0
@export var acceleration: float = 1600.0
@export var jump_speed: float = 460.0
@export var gravity: float = 980.0
@export var drop_seconds: float = 0.35
@export var attack_cooldown: float = 0.4
## Sideways speed given to a fighter that lands on another fighter's head, so nobody
## can stand on top of a player (prototype value).
@export var stack_slide_speed: float = 300.0
