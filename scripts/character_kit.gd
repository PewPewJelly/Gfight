@tool
class_name CharacterKit
extends Resource
## Character-specific mechanics that data alone cannot express (transformations, combos, charge
## meters). Subclass it in scripts/characters/<id>_kit.gd and assign it on the CharacterDef.
##
## One instance serves every fighter using the character, so a subclass may only declare @export
## tuning values and the moves or projectiles it starts. Anything that changes during a match goes
## in fighter.kit_state (plain values only), which FightArena saves for rollback.
## See Docs/gdd/characters/kit-rules.md.

## Starting kit_state; applied again after every ring-out and respawn.
func initial_state() -> Dictionary:
	return {}

## Called every tick before input is read.
func tick(_fighter: Fighter, _delta: float) -> void:
	pass

## Called on an attack or skill press, before the normal move starts. Return true to take over
## the press; the normal move is then skipped. Fighter.move_slot(mask, airborne) reads the direction.
func handle_press(_fighter: Fighter, _mask: int, _attack_pressed: bool, _skill_pressed: bool, _airborne: bool) -> bool:
	return false

## Picks the move for a press, e.g. the next step of a combo. Return `move` to keep the normal one.
func choose_move(_fighter: Fighter, _slot: CharacterDef.Slot, _is_skill: bool, move: AttackData) -> AttackData:
	return move

## True holds the fighter in place with no gravity and hands input to handle_press only.
## Hitstun always overrides this so a frozen fighter can still be knocked away.
func body_frozen(_fighter: Fighter) -> bool:
	return false

## Called after this fighter landed a hit with a move or one of its projectiles.
func on_hit_dealt(_fighter: Fighter, _target: Fighter, _hit: HitData) -> void:
	pass

## Called after this fighter was hit.
func on_hit_taken(_fighter: Fighter, _hit: HitData) -> void:
	pass

## PNG to draw instead of the standing art and move poses. Null keeps those.
func sprite(_fighter: Fighter) -> Texture2D:
	return null

## Extra drawing on top of the fighter, using its draw_* functions. Must only read state.
func draw(_fighter: Fighter) -> void:
	pass
