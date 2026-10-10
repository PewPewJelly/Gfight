class_name Fighter
extends CharacterBody2D

signal stock_lost(fighter: Fighter)
enum LifeState { ACTIVE, WAITING, ELIMINATED }

var rules: CombatRules
var player_id: int = 0
var player_slot: int = 1
var stocks: int = 3
var percent: float = 0.0
var damage_received: float = 0.0
var life_state: LifeState = LifeState.ACTIVE
var invulnerability_left: float = 0.0
var respawn_left: float = 0.0
var hitstun_left: float = 0.0
var attack_cooldown: float = 0.0
var jumps_left: int = 2
var facing: float = 1.0
var tint: Color = Color.CYAN
var controls: Array[Key] = [KEY_A, KEY_D, KEY_W, KEY_J]
var jump_was_down: bool = false
var attack_was_down: bool = false
var attack_requested: bool = false
var input_enabled: bool = true
var self_tick: bool = true
var movement: MovementSettings = preload("res://resources/movement_settings.tres")
var ground_checker: RayCast2D
var drop_left: float = 0.0
var drop_body: PhysicsBody2D
var down_was_down: bool = false
var attack_kind: String = "forward"
var attack_visual: Rect2
var last_input_mask: int = 0
## Match statistics (host-computed, replicated by snapshot).
var kills: int = 0
var dealt_percent: float = 0.0
var last_attacker_id: int = 0
## Arena frame of elimination; -1 while still in the match. Used for result ranks.
var eliminated_frame: int = -1
## Presentation only: own fighter shows the ▼나 marker, start countdown enlarges the tag.
var is_local: bool = false
var tag_emphasis: bool = false
var attacks: Dictionary = {
	"forward": preload("res://resources/basic_attack.tres"),
	"up": preload("res://resources/up_attack.tres"),
	"down": preload("res://resources/down_attack.tres")
}
const HALF_SIZE := Vector2(18, 26)

func _ready() -> void:
	collision_layer = 2
	collision_mask = 3
	var shape := RectangleShape2D.new()
	shape.size = HALF_SIZE * 2.0
	var collider := CollisionShape2D.new()
	collider.shape = shape
	add_child(collider)
	ground_checker = RayCast2D.new()
	ground_checker.name = "GroundChecker"
	ground_checker.target_position = Vector2(0, HALF_SIZE.y + 3.0)
	ground_checker.collision_mask = 1
	ground_checker.enabled = true
	add_child(ground_checker)

func reset_round(at: Vector2) -> void:
	last_input_mask = 0
	stocks = CombatRules.INITIAL_STOCKS
	percent = 0.0
	kills = 0
	dealt_percent = 0.0
	last_attacker_id = 0
	eliminated_frame = -1
	damage_received = 0.0
	invulnerability_left = 0.0
	respawn_left = 0.0
	life_state = LifeState.ACTIVE
	collision_layer = 2
	collision_mask = 3
	position = at
	_clear_actions()
	show()
	set_physics_process(true)

func _clear_actions() -> void:
	velocity = Vector2.ZERO
	hitstun_left = 0.0
	attack_cooldown = 0.0
	attack_requested = false
	_stop_drop()
	attack_visual = Rect2()
	jumps_left = 2
	jump_was_down = (last_input_mask & 4) != 0
	attack_was_down = (last_input_mask & 16) != 0
	down_was_down = (last_input_mask & 8) != 0

## All damage/impulse sources must enter here (or apply_external_impulse).
## Direction is an explicit attack vector, never inferred from victim facing.
func receive_hit(attack: AttackData, direction: Vector2) -> bool:
	if life_state != LifeState.ACTIVE or invulnerability_left > 0.0 or direction.is_zero_approx():
		return false
	damage_received += maxf(0.0, attack.damage)
	percent = rules.accumulated_percent(percent, attack.percent_increase)
	velocity = direction.normalized() * rules.launch_speed(attack.base_launch_speed, percent)
	hitstun_left = maxf(hitstun_left, attack.hitstun_seconds)
	attack_requested = false
	return true

func apply_external_impulse(impulse: Vector2) -> bool:
	if life_state != LifeState.ACTIVE or invulnerability_left > 0.0:
		return false
	velocity += impulse
	return true

func ring_out() -> bool:
	if life_state != LifeState.ACTIVE:
		return false
	stocks = maxi(0, stocks - 1)
	percent = 0.0
	damage_received = 0.0
	life_state = LifeState.WAITING if stocks > 0 else LifeState.ELIMINATED
	collision_layer = 0
	collision_mask = 0
	invulnerability_left = 0.0
	respawn_left = maxf(0.0, rules.respawn_delay)
	_clear_actions()
	hide()
	stock_lost.emit(self)
	return true

func respawn(at: Vector2) -> bool:
	if life_state != LifeState.WAITING or stocks <= 0:
		return false
	position = at
	_clear_actions()
	life_state = LifeState.ACTIVE
	collision_layer = 2
	collision_mask = 3
	invulnerability_left = CombatRules.RESPAWN_INVULNERABILITY
	show()
	return true

func _physics_process(delta: float) -> void:
	if self_tick:
		simulate(delta, read_keyboard(controls, KEY_S if player_id != 2 else KEY_DOWN))

static func read_keyboard(keys: Array[Key], down_key: Key) -> int:
	var mask := 0
	for index in range(4):
		if Input.is_physical_key_pressed(keys[index]):
			mask |= [1, 2, 4, 16][index]
	if Input.is_physical_key_pressed(down_key):
		mask |= 8
	return mask

func grounded() -> bool:
	if ground_checker == null:
		return false
	ground_checker.force_raycast_update()
	return drop_left <= 0.0 and velocity.y >= 0.0 and ground_checker.is_colliding() and ground_checker.get_collision_normal().y < -0.7

func _stop_drop() -> void:
	if is_instance_valid(drop_body):
		remove_collision_exception_with(drop_body)
		if ground_checker != null:
			ground_checker.remove_exception(drop_body)
	drop_body = null
	drop_left = 0.0

func simulate(delta: float, mask: int) -> void:
	last_input_mask = mask
	if life_state != LifeState.ACTIVE or not input_enabled:
		return
	invulnerability_left = maxf(0.0, invulnerability_left - delta)
	hitstun_left = maxf(0.0, hitstun_left - delta)
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	if drop_left > 0.0:
		drop_left -= delta
		if drop_left <= 0.0:
			_stop_drop()
	var jump_down := (mask & 4) != 0
	var attack_down := (mask & 16) != 0
	var down_down := (mask & 8) != 0
	var on_ground := grounded()
	if on_ground:
		jumps_left = 2
	if hitstun_left <= 0.0:
		var axis := float((mask & 2) != 0) - float((mask & 1) != 0)
		velocity.x = move_toward(velocity.x, axis * movement.speed, movement.acceleration * delta)
		if axis != 0.0:
			facing = signf(axis)
		if jump_down and not jump_was_down and jumps_left > 0:
			velocity.y = -movement.jump_speed
			jumps_left -= 1
		if attack_down and not attack_was_down and attack_cooldown <= 0.0:
			attack_kind = "up" if jump_down else ("down" if down_down else "forward")
			attack_requested = true
			attack_cooldown = movement.attack_cooldown
			attack_visual = attack_box()
		# S+J selects a downward attack without also dropping through the platform.
		if down_down and not down_was_down and not attack_down and on_ground:
			var ground = ground_checker.get_collider()
			if ground is PhysicsBody2D and ground.get_meta("drop_through", false):
				drop_body = ground
				add_collision_exception_with(drop_body)
				ground_checker.add_exception(drop_body)
				drop_left = movement.drop_seconds
				position.y += 4.0
				velocity.y = 100.0
				jumps_left = mini(jumps_left, 1)
	jump_was_down = jump_down
	attack_was_down = attack_down
	down_was_down = down_down
	velocity.y += movement.gravity * delta
	move_and_slide()
	queue_redraw()

func attack_box() -> Rect2:
	var data: AttackData = attacks[attack_kind]
	if attack_kind == "up":
		return Rect2(Vector2(-data.width / 2.0, -HALF_SIZE.y - data.reach), Vector2(data.width, data.reach))
	if attack_kind == "down":
		return Rect2(Vector2(-data.width / 2.0, HALF_SIZE.y), Vector2(data.width, data.reach))
	return Rect2(Vector2(HALF_SIZE.x if facing > 0 else -HALF_SIZE.x - data.reach, -data.width / 2.0), Vector2(data.reach, data.width))

func attack_direction() -> Vector2:
	var data: AttackData = attacks[attack_kind]
	return Vector2(data.launch_direction.x * facing, data.launch_direction.y).normalized()

func _draw() -> void:
	var color := tint
	if invulnerability_left > 0.0:
		color.a = 0.45 + 0.35 * absf(sin(invulnerability_left * 12.0))
	draw_rect(Rect2(-HALF_SIZE, HALF_SIZE * 2.0), color)
	draw_line(Vector2(0, -10), Vector2(facing * 15, -10), Color.WHITE, 3.0)
	var tag_size := 28 if tag_emphasis else 16
	var tag_top := -HALF_SIZE.y - 8.0
	draw_string(ThemeDB.fallback_font, Vector2(-40, tag_top), "P%d" % player_slot, HORIZONTAL_ALIGNMENT_CENTER, 80, tag_size, tint if tag_emphasis else Color.WHITE)
	if is_local:
		draw_string(ThemeDB.fallback_font, Vector2(-40, tag_top - tag_size - 2.0), UiStyle.ME_MARK, HORIZONTAL_ALIGNMENT_CENTER, 80, 18, tint.lightened(0.3))
	if attack_cooldown > movement.attack_cooldown - 0.12:
		draw_rect(attack_visual, Color(1, 1, 1, 0.25))
		draw_rect(attack_visual, Color.WHITE, false, 2.0)
