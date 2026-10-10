class_name CombatRules
extends Resource

## Prototype tuning only; values marked ?? in the handoff remain design decisions.
## Top blast line distance above the screen (knocked up fighters always fall back,
## so the top line is not based on recovery reach).
@export var ring_out_margin: float = 160.0
## Extra distance past the double-jump recovery reach for the side and bottom lines.
@export var blast_safety_margin: float = 40.0
@export var respawn_delay: float = 3.0
## [제안] Shared start signal; all input is ignored until it reaches zero.
@export var start_countdown: float = 3.0
@export var knockback_growth: float = 1.0
## Zero means uncapped.
@export var percent_cap: float = 0.0
const INITIAL_STOCKS: int = 3
const RESPAWN_INVULNERABILITY: float = 3.0

func launch_speed(base_speed: float, percent: float) -> float:
	return maxf(0.0, base_speed) * (1.0 + percent * maxf(0.0, knockback_growth) / 100.0)

func accumulated_percent(current: float, increase: float) -> float:
	var total := current + maxf(0.0, increase)
	return minf(total, percent_cap) if percent_cap > 0.0 else total

## Blast lines: side and bottom lines sit just past the farthest point from which a
## fighter could still reach the stage using both jumps, so crossing one means the
## fighter could not have recovered. stage spans all platforms; lowest_top is the
## top surface of the lowest platform.
func blast_zone(stage: Rect2, lowest_top: float, screen: Rect2, movement: MovementSettings) -> Rect2:
	var reach := recovery_reach(movement)
	var margin := maxf(0.0, blast_safety_margin)
	var left := stage.position.x - reach.x - margin
	var right := stage.end.x + reach.x + margin
	var top := screen.position.y - maxf(0.0, ring_out_margin)
	var bottom := lowest_top + reach.y + margin
	return Rect2(left, top, right - left, bottom - top)

## Farthest horizontal (x) and vertical rise (y) reachable with two jumps.
## Air time: jump, fall back to the start height, then jump again (2 × 2v/g);
## rise: each jump climbs v²/2g.
static func recovery_reach(movement: MovementSettings) -> Vector2:
	var gravity := maxf(1.0, movement.gravity)
	var air_time := 4.0 * movement.jump_speed / gravity
	return Vector2(movement.speed * air_time, movement.jump_speed * movement.jump_speed / gravity)

func is_outside(point: Vector2, zone: Rect2) -> bool:
	return point.x <= zone.position.x or point.x >= zone.end.x or point.y <= zone.position.y or point.y >= zone.end.y
