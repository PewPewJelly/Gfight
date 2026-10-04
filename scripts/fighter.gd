class_name Fighter
extends CharacterBody2D

signal stock_lost(fighter: Fighter)
enum LifeState { ACTIVE, WAITING, ELIMINATED }

var rules: CombatRules
var player_id: int = 0
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
const HALF_SIZE := Vector2(18, 26)

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	var shape := RectangleShape2D.new()
	shape.size = HALF_SIZE * 2.0
	var collider := CollisionShape2D.new()
	collider.shape = shape
	add_child(collider)

func reset_round(at: Vector2) -> void:
	stocks = CombatRules.INITIAL_STOCKS
	percent = 0.0
	damage_received = 0.0
	invulnerability_left = 0.0
	respawn_left = 0.0
	life_state = LifeState.ACTIVE
	position = at
	_clear_actions()
	show()
	set_physics_process(true)

func _clear_actions() -> void:
	velocity = Vector2.ZERO
	hitstun_left = 0.0
	attack_cooldown = 0.0
	attack_requested = false
	jumps_left = 2
	jump_was_down = Input.is_physical_key_pressed(controls[2])
	attack_was_down = Input.is_physical_key_pressed(controls[3])

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
	invulnerability_left = CombatRules.RESPAWN_INVULNERABILITY
	show()
	return true

func _physics_process(delta: float) -> void:
	if life_state != LifeState.ACTIVE or not input_enabled:
		return
	invulnerability_left = maxf(0.0, invulnerability_left - delta)
	hitstun_left = maxf(0.0, hitstun_left - delta)
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	var jump_down := Input.is_physical_key_pressed(controls[2])
	var attack_down := Input.is_physical_key_pressed(controls[3])
	if is_on_floor():
		jumps_left = 2
	if hitstun_left <= 0.0:
		var axis := float(Input.is_physical_key_pressed(controls[1])) - float(Input.is_physical_key_pressed(controls[0]))
		velocity.x = move_toward(velocity.x, axis * 260.0, 1600.0 * delta)
		if axis != 0.0:
			facing = signf(axis)
		if jump_down and not jump_was_down and jumps_left > 0:
			velocity.y = -460.0
			jumps_left -= 1
		if attack_down and not attack_was_down and attack_cooldown <= 0.0:
			attack_requested = true
			attack_cooldown = 0.4
	jump_was_down = jump_down
	attack_was_down = attack_down
	velocity.y += 980.0 * delta
	move_and_slide()
	queue_redraw()

func _draw() -> void:
	var color := tint
	if invulnerability_left > 0.0:
		color.a = 0.45 + 0.35 * absf(sin(invulnerability_left * 12.0))
	draw_rect(Rect2(-HALF_SIZE, HALF_SIZE * 2.0), color)
	draw_line(Vector2(0, -10), Vector2(facing * 15, -10), Color.WHITE, 3.0)
	if attack_cooldown > 0.28:
		draw_arc(Vector2(facing * 25, 0), 45, -1.3 if facing > 0 else 1.8, 1.3 if facing > 0 else 4.4, 16, Color.WHITE, 3)
