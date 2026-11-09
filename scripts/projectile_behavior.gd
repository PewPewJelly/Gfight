@tool
class_name ProjectileBehavior
extends Resource
## How one projectile type moves and reacts. Subclass it in scripts/projectiles/.
##
## One instance serves every projectile of its type, so a subclass may only declare @export
## tuning values. Anything that changes per projectile goes in the Projectile (position,
## velocity, age, vars), which FightArena saves for rollback. See Docs/gdd/characters/kit-rules.md.

## Called once when the projectile appears.
func on_spawn(_shot: Projectile, _arena: FightArena) -> void:
	pass

## Called every tick. The default flies straight at the current velocity.
func step(shot: Projectile, _arena: FightArena, delta: float) -> void:
	shot.position += shot.velocity * delta

## Called after the projectile hit a fighter, before it vanishes (if it does).
func on_hit(_shot: Projectile, _arena: FightArena, _target: Fighter) -> void:
	pass

## Called while ProjectileData.hits_platforms is on and it touches a platform.
func on_platform(shot: Projectile, _arena: FightArena, _surface: Rect2) -> void:
	shot.alive = false

## Called when lifetime_frames runs out, just before it disappears.
func on_expire(_shot: Projectile, _arena: FightArena) -> void:
	pass
