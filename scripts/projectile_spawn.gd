class_name ProjectileSpawn
extends Resource
## The trigger on a move: when the move reaches `frame`, launch `count` projectiles.

@export var projectile: ProjectileData
## Frame counted from the start of the move (0 is the frame the move starts).
@export var frame: int = 0
## Launch point from the fighter's center while facing right (x flips with facing).
@export var offset: Vector2 = Vector2(36, 0)
## Launch angle while facing right: 0 is straight ahead, negative is upward.
@export var angle_degrees: float = 0.0
@export var count: int = 1
## Total fan angle shared across `count` projectiles.
@export var spread_degrees: float = 0.0
