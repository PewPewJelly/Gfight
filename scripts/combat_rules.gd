class_name CombatRules
extends Resource

## Prototype tuning only; values marked ?? in the handoff remain design decisions.
@export var ring_out_margin: float = 160.0
@export var respawn_delay: float = 2.0
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

func is_outside(point: Vector2, screen: Rect2) -> bool:
	var bounds := screen.grow(maxf(0.0, ring_out_margin))
	return point.x <= bounds.position.x or point.x >= bounds.end.x or point.y <= bounds.position.y or point.y >= bounds.end.y
