class_name AttackData
extends Resource
## One basic attack. Field meanings: GDD/characters/character-template.md §7.1.

## Where the hit area sits: in front of the body, above the head, or below the feet.
enum Anchor { FRONT, ABOVE, BELOW }

@export var damage: float = 10.0
@export var percent_increase: float = 12.0
@export var base_launch_speed: float = 420.0
@export var hitstun_seconds: float = 0.35
@export var reach: float = 80.0
@export var width: float = 70.0
@export var launch_direction: Vector2 = Vector2(1, -0.35)
@export var anchor: Anchor = Anchor.FRONT
