class_name ProjectileView
extends Node2D
## Draws the arena's projectiles above the fighters. Presentation only.

var arena: FightArena

func _draw() -> void:
	for shot in arena.projectiles:
		if shot.data.sprite == null:
			var owner_fighter := arena.fighter_by_id(shot.owner_id)
			draw_rect(shot.box(), owner_fighter.tint if owner_fighter != null else Color.WHITE)
		else:
			_draw_sprite(shot)

func _draw_sprite(shot: Projectile) -> void:
	var sprite := shot.data.sprite
	var height := shot.data.sprite_height if shot.data.sprite_height > 0.0 else shot.data.size.y
	var drawn := Vector2(height * sprite.get_width() / float(maxi(1, sprite.get_height())), height)
	var turn := shot.velocity.angle() if shot.data.rotates_with_travel else 0.0
	var side := 1.0 if shot.data.rotates_with_travel or shot.facing > 0.0 else -1.0
	draw_set_transform(shot.position, turn, Vector2(side, 1.0))
	draw_texture_rect(sprite, Rect2(-drawn / 2.0, drawn), false)
	draw_set_transform(Vector2.ZERO)
