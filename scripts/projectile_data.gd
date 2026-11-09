class_name ProjectileData
extends HitData
## One projectile type: its numbers here, how it moves and reacts in `behavior`.
## launch_direction follows the way the projectile is traveling, not the shooter's facing.

## VANISH disappears on the first hit; PIERCE keeps going and hits each target once.
enum AfterHit { VANISH, PIERCE }

## Hit area in px, centered on the projectile.
@export var size: Vector2 = Vector2(24, 24)
## Launch speed in px/s.
@export var speed: float = 400.0
## Frames until it expires (60 per second). 0 keeps it until it leaves the blast zone.
@export var lifetime_frames: int = 90
## How many of this type one fighter can have out at once. 0 sets no limit of its own.
@export var max_active: int = 0
@export var after_hit: AfterHit = AfterHit.VANISH
## Touching a platform calls the behavior's on_platform (by default it disappears).
@export var hits_platforms: bool = false
## Movement and reactions. Empty flies straight at a constant speed.
@export var behavior: ProjectileBehavior

@export_group("Look")
## PNG drawn at the hit area. Empty draws a box in the owner's slot color.
@export var sprite: Texture2D
## Drawn height in px. 0 matches the hit area.
@export var sprite_height: float = 0.0
## Turns the PNG toward the direction of travel instead of only flipping left and right.
@export var rotates_with_travel: bool = false
