class_name Fighter
extends CharacterBody2D

signal stock_lost(fighter: Fighter)
enum LifeState { ACTIVE, WAITING, ELIMINATED }
enum MovePhase { NONE, STARTUP, ACTIVE, RECOVERY }

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
## Default body. Characters set their own through half_size (CharacterDef.body_size).
const HALF_SIZE := Vector2(18, 26)
## Presentation only: how long a hit area stays drawn after it goes live.
const ATTACK_FLASH_SECONDS := 0.12
## Presentation only: slot-colored bar under PNG art so players stay distinct.
const FOOT_BAR_GAP := 3.0
const FOOT_BAR_HEIGHT := 4.0

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
## Filled at run time; a preload would be a load cycle because characters refer back to
## this script through their kits and projectile behaviors.
var character: CharacterDef
var movement: MovementSettings = DEFAULT_MOVEMENT
var half_size: Vector2 = HALF_SIZE
## Every move reachable from the character; snapshots refer to moves by index here.
var moves: Array[AttackData] = []
## Character-specific code (shared by everyone using it) and this fighter's state for it.
var kit: CharacterKit
var kit_state: Dictionary = {}
## Set by FightArena; null for a fighter outside an arena, which cannot launch projectiles.
var arena: FightArena
var body_shape: RectangleShape2D
var ground_checker: RayCast2D
var drop_left: float = 0.0
var drop_body: PhysicsBody2D
var down_was_down: bool = false
## Move started by the last press (basic attack or skill); FightArena reads it for hits.
var active_move: AttackData
var attack_slot: CharacterDef.Slot = CharacterDef.Slot.SIDE
var attack_is_skill: bool = false
var move_phase: MovePhase = MovePhase.NONE
## Frames since the running move started.
var move_frame: int = 0
## Player slots the running move has already hit (bit per slot).
var hit_mask: int = 0
## SkillData -> seconds until it can be used again (air slots may share a ground skill).
var skill_cooldowns: Dictionary = {}
var attack_visual: Rect2
var attack_flash_left: float = 0.0
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

func _init() -> void:
	use_character(load("res://resources/characters/test_fighter.tres"))

func _ready() -> void:
	collision_layer = 2
	collision_mask = 3
	body_shape = RectangleShape2D.new()
	var collider := CollisionShape2D.new()
	collider.shape = body_shape
	add_child(collider)
	ground_checker = RayCast2D.new()
	ground_checker.name = "GroundChecker"
	ground_checker.collision_mask = 1
	ground_checker.enabled = true
	add_child(ground_checker)
	_apply_body_size()

## Applies a catalog character (movement, moves, body and kit). Call before the match starts.
func use_character(entry: CharacterDef) -> void:
	if entry == null:
		push_warning("P%d has no character; keeping %s" % [player_slot, character.id])
		return
	character = entry
	if entry.movement != null:
		movement = entry.movement
	else:
		movement = DEFAULT_MOVEMENT
	moves.clear()
	for resource in entry.reachable_resources():
		if resource is AttackData:
			moves.append(resource)
	kit = entry.kit
	kit_state = kit.initial_state() if kit != null else {}
	half_size = entry.body_size / 2.0
	_apply_body_size()
	if arena != null:
		arena.index_projectile_types()

func _apply_body_size() -> void:
	if body_shape != null:
		body_shape.size = half_size * 2.0
	if ground_checker != null:
		ground_checker.target_position = Vector2(0, half_size.y + 3.0)

## Only fighters in play collide, so nobody leaves an invisible obstacle behind.
func update_collision() -> void:
	var in_play := life_state == LifeState.ACTIVE
	collision_layer = 2 if in_play else 0
	collision_mask = 3 if in_play else 0

## This fighter's bit in a hit mask.
func slot_bit() -> int:
	return 1 << player_slot

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
	update_collision()
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
	move_phase = MovePhase.NONE
	move_frame = 0
	hit_mask = 0
	skill_cooldowns.clear()
	_stop_drop()
	attack_visual = Rect2()
	attack_flash_left = 0.0
	kit_state = kit.initial_state() if kit != null else {}
	jumps_left = 2
	jump_was_down = (last_input_mask & INPUT_JUMP) != 0
	attack_was_down = (last_input_mask & INPUT_ATTACK) != 0
	skill_was_down = (last_input_mask & INPUT_SKILL) != 0
	down_was_down = (last_input_mask & INPUT_DOWN) != 0

## All damage/impulse sources must enter here (or apply_external_impulse).
## Direction is an explicit attack vector, never inferred from victim facing.
func receive_hit(attack: HitData, direction: Vector2) -> bool:
	if life_state != LifeState.ACTIVE or invulnerability_left > 0.0 or direction.is_zero_approx():
		return false
	damage_received += maxf(0.0, attack.damage)
	percent = rules.accumulated_percent(percent, attack.percent_increase)
	velocity = direction.normalized() * rules.launch_speed(attack.base_launch_speed, percent)
	hitstun_left = maxf(hitstun_left, attack.hitstun_seconds)
	attack_requested = false
	move_phase = MovePhase.NONE
	if kit != null:
		kit.on_hit_taken(self, attack)
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
	update_collision()
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
	update_collision()
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

func restore_drop_state(seconds_left: float) -> void:
	_stop_drop()
	if seconds_left <= 0.0 or ground_checker == null:
		return
	ground_checker.force_raycast_update()
	var ground := ground_checker.get_collider()
	if ground is PhysicsBody2D and ground.get_meta("drop_through", false):
		drop_body = ground
		add_collision_exception_with(drop_body)
		ground_checker.add_exception(drop_body)
		drop_left = seconds_left

## Skill cooldowns keyed by each skill's index in `moves`; snapshots cannot carry resources.
func skill_cooldown_state() -> Dictionary:
	var state := {}
	for skill: SkillData in skill_cooldowns:
		state[moves.find(skill)] = float(skill_cooldowns[skill])
	return state

## Rebuilds the last move and skill cooldowns from snapshot values (see skill_cooldown_state).
func restore_move_state(slot: CharacterDef.Slot, is_skill: bool, move_index: int, cooldowns: Dictionary) -> void:
	attack_slot = slot
	attack_is_skill = is_skill
	active_move = _move_at(move_index)
	skill_cooldowns.clear()
	for index: int in cooldowns:
		var skill := _move_at(index) as SkillData
		if skill != null:
			skill_cooldowns[skill] = float(cooldowns[index])

## Null for an index outside `moves` (no move yet, or bad network data).
func _move_at(index: int) -> AttackData:
	return moves[index] if index >= 0 and index < moves.size() else null

func simulate(delta: float, mask: int) -> void:
	last_input_mask = mask
	if life_state != LifeState.ACTIVE or not input_enabled:
		return
	invulnerability_left = maxf(0.0, invulnerability_left - delta)
	hitstun_left = maxf(0.0, hitstun_left - delta)
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	attack_flash_left = maxf(0.0, attack_flash_left - delta)
	for skill: SkillData in skill_cooldowns.keys():
		skill_cooldowns[skill] = maxf(0.0, float(skill_cooldowns[skill]) - delta)
	if drop_left > 0.0:
		drop_left -= delta
		if drop_left <= 0.0:
			_stop_drop()
	_advance_move()
	var jump_down := (mask & INPUT_JUMP) != 0
	var attack_down := (mask & INPUT_ATTACK) != 0
	var skill_down := (mask & INPUT_SKILL) != 0
	var down_down := (mask & INPUT_DOWN) != 0
	var on_ground := grounded()
	if on_ground:
		jumps_left = 2
	if kit != null:
		kit.tick(self, delta)
	if hitstun_left <= 0.0:
		var frozen := _body_frozen()
		var locked := frozen or _move_locks_body()
		var axis := 0.0 if locked else float((mask & INPUT_RIGHT) != 0) - float((mask & INPUT_LEFT) != 0)
		velocity.x = move_toward(velocity.x, axis * movement.speed, movement.acceleration * delta)
		# A running move keeps the facing it started with so its hit area does not flip.
		if axis != 0.0 and move_phase == MovePhase.NONE:
			facing = signf(axis)
		var jumped := false
		if jump_down and not jump_was_down and jumps_left > 0 and not locked:
			velocity.y = -movement.jump_speed
			jumps_left -= 1
			jumped = true
		var attack_pressed := attack_down and not attack_was_down
		var skill_pressed := skill_down and not skill_was_down
		var airborne := jumped or not on_ground
		var taken_by_kit := (attack_pressed or skill_pressed) and kit != null and kit.handle_press(self, mask, attack_pressed, skill_pressed, airborne)
		if (attack_pressed or skill_pressed) and not taken_by_kit and not frozen and attack_cooldown <= 0.0 and move_phase == MovePhase.NONE:
			# Jumping on the same frame makes it an air move.
			# A basic attack wins when both buttons are pressed on the same frame.
			_start_move(move_slot(mask, airborne), not attack_pressed)
		# S with an attack or skill picks a downward move without also dropping through.
		if down_down and not down_was_down and not attack_down and not skill_down and on_ground and not locked:
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
	if _body_frozen():
		velocity = Vector2.ZERO
	else:
		velocity.y += movement.gravity * delta
	move_and_slide()
	_slide_off_heads()
	# Keep tiny platform/CPU floating-point differences from accumulating across rollback peers.
	position = Vector2(snappedf(position.x, 0.001), snappedf(position.y, 0.001))
	velocity = Vector2(snappedf(velocity.x, 0.001), snappedf(velocity.y, 0.001))
	queue_redraw()

## Starts the character's basic attack or skill in this slot. A missing skill or one still
## cooling down does nothing; a missing basic attack is a data error.
func _start_move(slot: CharacterDef.Slot, is_skill: bool) -> void:
	var data: AttackData = character.skill(slot) if is_skill else character.attack(slot)
	if kit != null:
		data = kit.choose_move(self, slot, is_skill, data)
	if data == null:
		if not is_skill:
			push_warning("%s has no %s attack" % [character.id, CharacterDef.Slot.keys()[slot]])
		return
	if data is SkillData and float(skill_cooldowns.get(data, 0.0)) > 0.0:
		return
	attack_slot = slot
	attack_is_skill = is_skill
	start_move(data)

## Starts a move right away. Kits use this for moves outside the five slots; such a move must
## be an @export on the kit so every peer can look it up. Returns false if it cannot be found.
func start_move(data: AttackData) -> bool:
	if not moves.has(data):
		push_error("%s started a move it does not export" % character.id)
		return false
	var skill := data as SkillData
	if skill != null:
		skill_cooldowns[skill] = maxf(0.0, skill.cooldown)
		if not skill.self_velocity.is_zero_approx():
			velocity = Vector2(skill.self_velocity.x * facing, skill.self_velocity.y)
	active_move = data
	move_frame = 0
	hit_mask = 0
	attack_cooldown = data.cooldown_override if data.cooldown_override >= 0.0 else movement.attack_cooldown
	_update_move_phase()
	_launch_due_projectiles()
	return true

func _advance_move() -> void:
	if move_phase == MovePhase.NONE:
		return
	move_frame += 1
	_update_move_phase()
	if move_phase != MovePhase.NONE:
		_launch_due_projectiles()

func _update_move_phase() -> void:
	var active_start := maxi(0, active_move.startup_frames)
	var active_end := active_start + maxi(1, active_move.active_frames)
	if move_frame < active_start:
		move_phase = MovePhase.STARTUP
	elif move_frame < active_end:
		move_phase = MovePhase.ACTIVE
		attack_requested = true
		attack_visual = attack_box()
		attack_flash_left = ATTACK_FLASH_SECONDS
	elif move_frame < active_move.total_frames():
		move_phase = MovePhase.RECOVERY
	else:
		move_phase = MovePhase.NONE

func _launch_due_projectiles() -> void:
	if arena == null:
		return
	for spawn in active_move.spawns:
		if spawn.frame == move_frame and spawn.projectile != null:
			arena.launch(spawn, self)

func _move_locks_body() -> bool:
	return move_phase != MovePhase.NONE and active_move.move_lock == AttackData.MoveLock.ROOTED

func _body_frozen() -> bool:
	return hitstun_left <= 0.0 and kit != null and kit.body_frozen(self)

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
	return active_move.hit_box(half_size, facing)

func attack_direction() -> Vector2:
	if active_move == null:
		return Vector2.ZERO
	return Vector2(active_move.launch_direction.x * facing, active_move.launch_direction.y).normalized()

func _draw() -> void:
	var color := tint
	if invulnerability_left > 0.0:
		color.a = 0.45 + 0.35 * absf(sin(invulnerability_left * 12.0))
	var look := current_look()
	var art_top := -half_size.y
	if look != null:
		art_top = minf(art_top, _draw_look(look, color.a))
	else:
		draw_rect(Rect2(-half_size, half_size * 2.0), color)
		draw_line(Vector2(0, -10), Vector2(facing * 15, -10), Color.WHITE, 3.0)
	var tag_size := 28 if tag_emphasis else 16
	var tag_top := art_top - 8.0
	var tag := UiStyle.DUMMY if is_dummy else "P%d" % player_slot
	draw_string(ThemeDB.fallback_font, Vector2(-60, tag_top), tag, HORIZONTAL_ALIGNMENT_CENTER, 120, tag_size, tint if tag_emphasis or look != null else Color.WHITE)
	if is_local:
		draw_string(ThemeDB.fallback_font, Vector2(-40, tag_top - tag_size - 2.0), UiStyle.ME_MARK, HORIZONTAL_ALIGNMENT_CENTER, 80, 18, tint.lightened(0.3))
	if attack_flash_left > 0.0 and attack_visual.has_area():
		draw_rect(attack_visual, Color(1, 1, 1, 0.25))
		draw_rect(attack_visual, Color.WHITE, false, 2.0)
	if kit != null:
		kit.draw(self)

## PNG to draw now: the kit's choice, then the running move's pose, then the standing art.
func current_look() -> Texture2D:
	var look: Texture2D = kit.sprite(self) if kit != null else null
	if look == null and move_phase != MovePhase.NONE:
		look = active_move.pose
	return look if look != null else character.match_sprite

## Draws the PNG with its bottom edge at the feet and returns the y of its top edge.
func _draw_look(look: Texture2D, alpha: float) -> float:
	var height := character.sprite_height if character.sprite_height > 0.0 else half_size.y * 2.0
	var drawn := Vector2(height * look.get_width() / float(maxi(1, look.get_height())), height)
	var feet := Vector2(character.sprite_offset.x * facing, half_size.y + character.sprite_offset.y)
	var mirrored := (facing < 0.0) != character.sprite_faces_left
	draw_set_transform(feet, 0.0, Vector2(-1.0 if mirrored else 1.0, 1.0))
	draw_texture_rect(look, Rect2(Vector2(-drawn.x / 2.0, -drawn.y), drawn), false, Color(1, 1, 1, alpha))
	draw_set_transform(Vector2.ZERO)
	draw_rect(Rect2(-half_size.x, half_size.y + FOOT_BAR_GAP, half_size.x * 2.0, FOOT_BAR_HEIGHT), tint)
	return feet.y - drawn.y
