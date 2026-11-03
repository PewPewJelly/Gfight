class_name Fighter
extends CharacterBody2D

signal stock_lost(fighter: Fighter)
enum LifeState { ACTIVE, WAITING, ELIMINATED }

## Input mask bits. Key arrays below use the same order, so key index i sets bit 1 << i.
const INPUT_LEFT := 1
const INPUT_RIGHT := 2
## Up only aims attacks and skills; it does not jump.
const INPUT_UP := 4
const INPUT_DOWN := 8
const INPUT_ATTACK := 16
const INPUT_SKILL := 32
const INPUT_JUMP := 64
const INPUT_ALL := 127
## Keys: left, right, up, down, attack, skill, jump. P2 is the local two-player test helper.
const P1_KEYS: Array[Key] = [KEY_A, KEY_D, KEY_W, KEY_S, KEY_J, KEY_K, KEY_SPACE]
const P2_KEYS: Array[Key] = [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_PERIOD, KEY_SLASH, KEY_COMMA]
const DEFAULT_MOVEMENT := preload("res://resources/movement_settings.tres")
const HALF_SIZE := Vector2(18, 26)

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
var controls: Array[Key] = P1_KEYS
var jump_was_down: bool = false
var attack_was_down: bool = false
var skill_was_down: bool = false
var attack_requested: bool = false
var input_enabled: bool = true
var self_tick: bool = true
## Selected character: movement, five basic attacks and skills (CharacterDef.Slot).
var character: CharacterDef = preload("res://resources/characters/test_fighter.tres")
var movement: MovementSettings = DEFAULT_MOVEMENT
var ground_checker: RayCast2D
var drop_left: float = 0.0
var drop_body: PhysicsBody2D
var down_was_down: bool = false
## Move started by the last press (basic attack or skill); FightArena reads it for hits.
var active_move: AttackData
var attack_slot: CharacterDef.Slot = CharacterDef.Slot.SIDE
var attack_is_skill: bool = false
## SkillData -> seconds until it can be used again (air slots may share a ground skill).
var skill_cooldowns: Dictionary = {}
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
## Training dummy: never receives input and is tagged 허수아비 instead of P<n>.
var is_dummy: bool = false

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

## Applies a catalog character (movement and moves). Call before the match starts.
func use_character(entry: CharacterDef) -> void:
	if entry == null:
		push_warning("P%d has no character; keeping %s" % [player_slot, character.id])
		return
	character = entry
	if entry.movement != null:
		movement = entry.movement
	else:
		movement = DEFAULT_MOVEMENT

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
	active_move = null
	skill_cooldowns.clear()
	_stop_drop()
	attack_visual = Rect2()
	jumps_left = 2
	jump_was_down = (last_input_mask & INPUT_JUMP) != 0
	attack_was_down = (last_input_mask & INPUT_ATTACK) != 0
	skill_was_down = (last_input_mask & INPUT_SKILL) != 0
	down_was_down = (last_input_mask & INPUT_DOWN) != 0

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
		simulate(delta, read_keyboard(controls))

## Reads one local player's keys (left, right, up, down, attack, skill, jump) into an input mask.
static func read_keyboard(keys: Array[Key]) -> int:
	var mask := 0
	for index in range(keys.size()):
		if Input.is_physical_key_pressed(keys[index]):
			mask |= 1 << index
	return mask & INPUT_ALL

## Move slot for an attack or skill press (GDD/characters/character-template.md §6):
## up > down > side; no direction is the same as up; only up and down split by ground/air.
## Slot names are input directions: an "up" move may hit anywhere its AttackData says.
static func move_slot(mask: int, airborne: bool) -> CharacterDef.Slot:
	var up := (mask & INPUT_UP) != 0
	var down := (mask & INPUT_DOWN) != 0
	var side := (mask & (INPUT_LEFT | INPUT_RIGHT)) != 0
	if down and not up:
		return CharacterDef.Slot.AIR_DOWN if airborne else CharacterDef.Slot.DOWN
	if side and not up:
		return CharacterDef.Slot.SIDE
	return CharacterDef.Slot.AIR_UP if airborne else CharacterDef.Slot.UP

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
	for skill: SkillData in skill_cooldowns.keys():
		skill_cooldowns[skill] = maxf(0.0, float(skill_cooldowns[skill]) - delta)
	if drop_left > 0.0:
		drop_left -= delta
		if drop_left <= 0.0:
			_stop_drop()
	var jump_down := (mask & INPUT_JUMP) != 0
	var attack_down := (mask & INPUT_ATTACK) != 0
	var skill_down := (mask & INPUT_SKILL) != 0
	var down_down := (mask & INPUT_DOWN) != 0
	var on_ground := grounded()
	if on_ground:
		jumps_left = 2
	if hitstun_left <= 0.0:
		var axis := float((mask & INPUT_RIGHT) != 0) - float((mask & INPUT_LEFT) != 0)
		velocity.x = move_toward(velocity.x, axis * movement.speed, movement.acceleration * delta)
		if axis != 0.0:
			facing = signf(axis)
		var jumped := false
		if jump_down and not jump_was_down and jumps_left > 0:
			velocity.y = -movement.jump_speed
			jumps_left -= 1
			jumped = true
		var attack_pressed := attack_down and not attack_was_down
		var skill_pressed := skill_down and not skill_was_down
		if (attack_pressed or skill_pressed) and attack_cooldown <= 0.0:
			# Jumping on the same frame makes it an air move.
			# A basic attack wins when both buttons are pressed on the same frame.
			_start_move(move_slot(mask, jumped or not on_ground), not attack_pressed)
		# S with an attack or skill picks a downward move without also dropping through.
		if down_down and not down_was_down and not attack_down and not skill_down and on_ground:
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
	skill_was_down = skill_down
	down_was_down = down_down
	velocity.y += movement.gravity * delta
	move_and_slide()
	_slide_off_heads()
	queue_redraw()

## Starts the character's basic attack or skill in this slot. A missing skill or one still
## cooling down does nothing; a missing basic attack is a data error.
func _start_move(slot: CharacterDef.Slot, is_skill: bool) -> void:
	var data: AttackData
	if is_skill:
		var skill := character.skill(slot)
		if skill == null or float(skill_cooldowns.get(skill, 0.0)) > 0.0:
			return
		skill_cooldowns[skill] = maxf(0.0, skill.cooldown)
		if not skill.self_velocity.is_zero_approx():
			velocity = Vector2(skill.self_velocity.x * facing, skill.self_velocity.y)
		data = skill
	else:
		data = character.attack(slot)
		if data == null:
			push_warning("%s has no %s attack" % [character.id, CharacterDef.Slot.keys()[slot]])
			return
	active_move = data
	attack_slot = slot
	attack_is_skill = is_skill
	attack_requested = true
	attack_cooldown = movement.attack_cooldown
	attack_visual = attack_box()

## Landing on another fighter never counts as standing: push sideways until clear.
func _slide_off_heads() -> void:
	for index in range(get_slide_collision_count()):
		var contact := get_slide_collision(index)
		var below := contact.get_collider() as Fighter
		if below == null or contact.get_normal().y > -0.5:
			continue
		var side := signf(position.x - below.position.x)
		if is_zero_approx(side):
			# Dead center: split by player id so host and replays agree.
			side = 1.0 if player_id > below.player_id else -1.0
		velocity.x = side * movement.stack_slide_speed
		return

## Hit area of the active move, relative to the fighter's position.
func attack_box() -> Rect2:
	if active_move == null:
		return Rect2()
	var data := active_move
	if data.anchor == AttackData.Anchor.ABOVE:
		return Rect2(Vector2(-data.width / 2.0, -HALF_SIZE.y - data.reach), Vector2(data.width, data.reach))
	if data.anchor == AttackData.Anchor.BELOW:
		return Rect2(Vector2(-data.width / 2.0, HALF_SIZE.y), Vector2(data.width, data.reach))
	return Rect2(Vector2(HALF_SIZE.x if facing > 0 else -HALF_SIZE.x - data.reach, -data.width / 2.0), Vector2(data.reach, data.width))

func attack_direction() -> Vector2:
	if active_move == null:
		return Vector2.ZERO
	return Vector2(active_move.launch_direction.x * facing, active_move.launch_direction.y).normalized()

func _draw() -> void:
	var color := tint
	if invulnerability_left > 0.0:
		color.a = 0.45 + 0.35 * absf(sin(invulnerability_left * 12.0))
	draw_rect(Rect2(-HALF_SIZE, HALF_SIZE * 2.0), color)
	draw_line(Vector2(0, -10), Vector2(facing * 15, -10), Color.WHITE, 3.0)
	var tag_size := 28 if tag_emphasis else 16
	var tag_top := -HALF_SIZE.y - 8.0
	var tag := UiStyle.DUMMY if is_dummy else "P%d" % player_slot
	draw_string(ThemeDB.fallback_font, Vector2(-60, tag_top), tag, HORIZONTAL_ALIGNMENT_CENTER, 120, tag_size, tint if tag_emphasis else Color.WHITE)
	if is_local:
		draw_string(ThemeDB.fallback_font, Vector2(-40, tag_top - tag_size - 2.0), UiStyle.ME_MARK, HORIZONTAL_ALIGNMENT_CENTER, 80, 18, tint.lightened(0.3))
	if attack_cooldown > movement.attack_cooldown - 0.12 and attack_visual.has_area():
		draw_rect(attack_visual, Color(1, 1, 1, 0.25))
		draw_rect(attack_visual, Color.WHITE, false, 2.0)
