class_name HitData
extends Resource
## What a hit does to its target. Shared by moves (AttackData) and projectiles (ProjectileData).
## Field meanings: GDD/characters/character-template.md §7.1.

@export var damage: float = 10.0
@export var percent_increase: float = 12.0
@export var base_launch_speed: float = 420.0
@export var hitstun_seconds: float = 0.35
@export var launch_direction: Vector2 = Vector2(1, -0.35)
