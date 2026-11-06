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
## Training dummy: never receives input and is tagged 허수아비 instead of P<n>.
var is_dummy: bool = false
var character_id: StringName = &"test_fighter"
var junbae: JunbaeSettings = preload("res://resources/junbae_settings.tres")
var special_was_down: bool = false
var special_cooldown: float = 0.0
var digital_mode: bool = false
var digital_delay: float = 0.0
var digital_delay_count: int = 0
var digital_action: String = ""
var digital_action_left: float = 0.0
var digital_skill_airborne: bool = false
var projectile_kind: String = ""
var projectile_position: Vector2 = Vector2.ZERO
var projectile_velocity: Vector2 = Vector2.ZERO
var projectile_left: float = 0.0
var projectile_owner_id: int = 0
var mirror_position: Vector2 = Vector2.ZERO
var neutral_combo: int = 0
var neutral_combo_left: float = 0.0
var emote_text: String = ""
var emote_left: float = 0.0
var look_style: String = "standing"
var portrait_style: String = "profile"
var digital_portrait_position: Vector2 = Vector2.ZERO
var portrait_marker: Sprite2D
var character_sprite: Sprite2D
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
	character_sprite = Sprite2D.new()
	character_sprite.name = "CharacterArt"
	character_sprite.texture = _standing_texture(character_id)
	character_sprite.centered = false
	character_sprite.position = Vector2(-27.0, -96.0)
	if character_sprite.texture != null:
		character_sprite.scale = Vector2.ONE * (96.0 / maxf(1.0, character_sprite.texture.get_height()))
	character_sprite.visible = character_id == &"junbae"
	add_child(character_sprite)
	portrait_marker = Sprite2D.new()
	portrait_marker.name = "DigitalPortrait"
	portrait_marker.top_level = true
	portrait_marker.visible = false
	add_child(portrait_marker)
	_set_portrait("profile")

func _standing_texture(id: StringName) -> Texture2D:
	if id == &"junbae":
		return load("res://assets/characters/junbae.png") as Texture2D
	return null

func _profile_texture(style: String) -> Texture2D:
	var stem := "junbae_%s" % style if style != "profile" else "junbae_profile"
	for extension in ["png", "webp", "jpg"]:
		var path := "res://assets/characters/%s.%s" % [stem, extension]
		if ResourceLoader.exists(path):
			return load(path) as Texture2D
	return null

func _emote(value: String, seconds: float = 0.45) -> void:
	emote_text = value
	emote_left = seconds

func _set_portrait(style: String) -> void:
	portrait_style = style
	if not is_instance_valid(portrait_marker):
		return
	portrait_marker.texture = _profile_texture(style)
	if portrait_marker.texture != null:
		var dimension := maxf(float(portrait_marker.texture.get_width()), float(portrait_marker.texture.get_height()))
		portrait_marker.scale = Vector2.ONE * (40.0 / maxf(1.0, dimension))

func _set_character_look(style: String) -> void:
	if not is_instance_valid(character_sprite):
		return
	look_style = style
	if character_id != &"junbae":
		return
	var texture: Texture2D = _standing_texture(&"junbae") if style == "standing" else null
	if style != "standing":
		var stem := "junbae_%s" % style
		for extension in ["png", "webp", "jpg"]:
			var path := "res://assets/characters/%s.%s" % [stem, extension]
			if ResourceLoader.exists(path):
				texture = load(path) as Texture2D
				break
	if texture != null:
		character_sprite.texture = texture
		character_sprite.scale = Vector2.ONE * (96.0 / maxf(1.0, texture.get_height()))
	character_sprite.modulate = Color(0.55, 0.9, 1.0) if style == "digital" else Color.WHITE

func reset_round(at: Vector2) -> void:
	last_input_mask = 0
	digital_mode = false
	digital_delay = 0.0
	digital_delay_count = 0
	digital_action = ""
	digital_action_left = 0.0
	digital_skill_airborne = false
	projectile_kind = ""
	projectile_left = 0.0
	neutral_combo = 0
	neutral_combo_left = 0.0
	special_cooldown = 0.0
	emote_text = ""
	emote_left = 0.0
	_set_portrait("profile")
	_set_character_look("standing")
	if is_instance_valid(portrait_marker):
		portrait_marker.hide()
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
	special_cooldown = 0.0
	attack_requested = false
	digital_mode = false
	digital_delay = 0.0
	digital_delay_count = 0
	digital_action = ""
	digital_action_left = 0.0
	digital_skill_airborne = false
	projectile_kind = ""
	projectile_left = 0.0
	emote_text = ""
	emote_left = 0.0
	_set_character_look("standing")
	_set_portrait("profile")
	if is_instance_valid(portrait_marker):
		portrait_marker.hide()
	_stop_drop()
	attack_visual = Rect2()
	jumps_left = 2
	jump_was_down = (last_input_mask & 4) != 0
	attack_was_down = (last_input_mask & 16) != 0
	down_was_down = (last_input_mask & 8) != 0
	special_was_down = (last_input_mask & 32) != 0

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
	if digital_mode:
		digital_mode = false
		digital_delay = 0.0
		digital_delay_count = 0
		digital_action = ""
		projectile_kind = ""
		_set_character_look("standing")
		_set_portrait("profile")
		if is_instance_valid(portrait_marker):
			portrait_marker.hide()
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

func simulate(delta: float, mask: int) -> void:
	last_input_mask = mask
	if life_state != LifeState.ACTIVE or not input_enabled:
		return
	invulnerability_left = maxf(0.0, invulnerability_left - delta)
	hitstun_left = maxf(0.0, hitstun_left - delta)
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	special_cooldown = maxf(0.0, special_cooldown - delta)
	neutral_combo_left = maxf(0.0, neutral_combo_left - delta)
	emote_left = maxf(0.0, emote_left - delta)
	if emote_left <= 0.0:
		emote_text = ""
	if drop_left > 0.0:
		drop_left -= delta
		if drop_left <= 0.0:
			_stop_drop()
	var jump_down := (mask & 4) != 0
	var attack_down := (mask & 16) != 0
	var down_down := (mask & 8) != 0
	var special_down := (mask & 32) != 0
	var on_ground := grounded()
	if on_ground:
		jumps_left = 2
	if character_id == &"junbae" and digital_action != "":
		digital_action_left = maxf(0.0, digital_action_left - delta)
		if digital_action_left <= 0.0:
			_complete_digital_action()
	if character_id == &"junbae" and digital_mode and (digital_action.is_empty() or digital_action == "enter" or digital_action.begins_with("wind_")):
		velocity = Vector2.ZERO
		var digital_axis := float((mask & 2) != 0) - float((mask & 1) != 0)
		if digital_axis != 0.0:
			facing = signf(digital_axis)
		if digital_mode and digital_action.is_empty() and special_down and not special_was_down and special_cooldown <= 0.0:
			_start_junbae_special(jump_down, down_down, digital_axis)
	elif hitstun_left <= 0.0:
		var axis := float((mask & 2) != 0) - float((mask & 1) != 0)
		velocity.x = move_toward(velocity.x, axis * movement.speed, movement.acceleration * delta)
		if axis != 0.0:
			facing = signf(axis)
		if jump_down and not jump_was_down and jumps_left > 0 and not (character_id == &"junbae" and special_down):
			velocity.y = -movement.jump_speed
			jumps_left -= 1
		if attack_down and special_down and not attack_was_down and not special_was_down and character_id == &"junbae":
			attack_kind = "finisher"
			_emote("대 준 배", 0.9)
			attack_requested = true
			attack_cooldown = junbae.finisher_cooldown
			attack_visual = attack_box()
		elif attack_down and not attack_was_down and attack_cooldown <= 0.0:
			if character_id == &"junbae":
				attack_kind = "up" if jump_down else ("ground_down" if down_down and on_ground else ("down" if down_down else "junbae_neutral"))
			else:
				attack_kind = "up" if jump_down else ("down" if down_down else "forward")
			if character_id == &"junbae" and attack_kind == "junbae_neutral":
				if neutral_combo_left <= 0.0:
					neutral_combo = 0
				attack_kind = "junbae_neutral_%d" % (neutral_combo + 1)
				neutral_combo = (neutral_combo + 1) % 2
				neutral_combo_left = 0.9
			attack_requested = true
			attack_cooldown = junbae.neutral_cooldown if character_id == &"junbae" and attack_kind.begins_with("junbae_neutral") else movement.attack_cooldown
			attack_visual = attack_box()
			if character_id == &"junbae":
				_emote("천재인가?" if attack_kind == "up" else ("이건 아니지" if attack_kind == "ground_down" else ("장발준배" if attack_kind == "down" else "와우!")), 0.36)
		if character_id == &"junbae" and special_down and not special_was_down and special_cooldown <= 0.0:
			if attack_down and not attack_was_down:
				special_cooldown = 1.4
			else:
				_start_junbae_special(jump_down, down_down, axis)
		# S+J selects a downward attack without also dropping through the platform.
		if down_down and not down_was_down and not attack_down and not special_down and on_ground:
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
	special_was_down = special_down
	if character_id == &"junbae" and digital_mode and (digital_action.is_empty() or digital_action == "enter" or digital_action.begins_with("wind_")):
		velocity = Vector2.ZERO
	else:
		velocity.y += movement.gravity * delta
	move_and_slide()
	_slide_off_heads()
	# Keep tiny platform/CPU floating-point differences from accumulating across rollback peers.
	position = Vector2(snappedf(position.x, 0.001), snappedf(position.y, 0.001))
	velocity = Vector2(snappedf(velocity.x, 0.001), snappedf(velocity.y, 0.001))
	queue_redraw()
	if is_instance_valid(portrait_marker) and digital_mode:
		portrait_marker.global_position = digital_portrait_position
	_tick_projectile(delta)

func _start_junbae_special(up: bool, down: bool, axis: float) -> void:
	if digital_mode:
		if down:
			digital_action = "wind_heal"
			digital_action_left = 0.24
			if is_instance_valid(portrait_marker):
				_set_portrait("ilay_profile")
			return
		digital_action = "wind_cipher" if up else ("wind_telema" if not is_zero_approx(axis) else "wind_coreline")
		digital_action_left = junbae.digital_skill_delay + junbae.digital_delay_growth * float(digital_delay_count)
		digital_delay_count += 1
		_emote("바람에 흩날리는 거짓말" if up else ("손님은 주인의 뜻대로" if not is_zero_approx(axis) else "단죄의 섬광"), 0.75)
		if digital_action == "wind_telema":
			digital_skill_airborne = not grounded()
		_set_portrait("cipher_profile" if up else ("telema_profile" if not is_zero_approx(axis) else "coreline_profile"))
		_set_character_look("cipher" if up else ("telema" if not is_zero_approx(axis) else "coreline"))
		return
	if up:
		_emote("어흐", 0.4)
		projectile_kind = "meme"
		projectile_owner_id = player_id
		projectile_position = position + Vector2(0, -40)
		projectile_velocity = Vector2(0, -junbae.meme_launch)
		projectile_left = 1.5
	elif down:
		_emote("대(물)검", 0.5)
		attack_kind = "sword"
		attack_requested = true
		attack_cooldown = junbae.sword_duration
		attack_visual = attack_box()
	else:
		if not is_zero_approx(axis):
			if projectile_kind == "altino":
				_emote("와아, 우레시이~", 0.55)
				attack_kind = "altino_blast"
				attack_requested = true
				attack_cooldown = 0.5
				attack_visual = attack_box()
				projectile_kind = ""
			else:
				_emote("알티노라이트 최고!", 0.55)
				projectile_kind = "altino"
				projectile_owner_id = player_id
				projectile_position = position + Vector2(facing * 36.0, -10.0)
				projectile_velocity = Vector2(facing * junbae.altino_speed, 0.0)
				projectile_left = 0.0
			special_cooldown = 0.4
			return
	special_cooldown = 0.5
	if not up and not down:
		digital_mode = true
		_emote("그거 나임", 0.65)
		digital_action = "enter"
		digital_action_left = junbae.digital_entry_delay
		velocity = Vector2.ZERO
		if is_instance_valid(portrait_marker):
			_set_portrait("profile")
			digital_portrait_position = position + Vector2(0, -92)
			portrait_marker.global_position = digital_portrait_position
			portrait_marker.show()

func _complete_digital_action() -> void:
	match digital_action:
		"enter":
			digital_action = ""
			_set_character_look("digital")
		"wind_telema":
			_set_character_look("telema")
			_set_portrait("telema_profile")
			digital_action = "telema"
			digital_action_left = junbae.digital_dash_duration
			velocity.x = facing * junbae.digital_side_dash
			attack_kind = "digital_side"
			attack_requested = true
		"wind_cipher":
			projectile_kind = "cipher_coin"
			projectile_owner_id = player_id
			projectile_position = position + Vector2(facing * 12.0, -36.0)
			projectile_velocity = Vector2(facing * 90.0, -110.0)
			projectile_left = junbae.digital_skill_delay
			_set_character_look("cipher")
			_set_portrait("cipher_profile")
			attack_kind = "digital_up"
			attack_requested = true
			velocity = Vector2(facing * 90.0, -junbae.digital_up_launch)
			_end_digital(false)
		"wind_coreline":
			_set_character_look("coreline")
			_set_portrait("coreline_profile")
			_start_mirror_shot()
			_end_digital(false)
		"wind_heal":
			_end_digital(true)
		"telema":
			digital_action = ""
			_end_digital(false)

func _end_digital(heal: bool) -> void:
	digital_mode = false
	digital_action = ""
	digital_action_left = 0.0
	digital_skill_airborne = false
	if heal:
		damage_received = maxf(0.0, damage_received - junbae.heal_percent)
		percent = maxf(0.0, percent - junbae.heal_percent)
	if is_instance_valid(portrait_marker):
		portrait_marker.hide()
	portrait_style = "profile"
	if heal:
		_emote("저런... 좆됐나봅니다", 0.65)
	_set_character_look("standing")

func _start_mirror_shot() -> void:
	projectile_kind = "mirror_first"
	projectile_owner_id = player_id
	projectile_position = position + Vector2(facing * 30.0, -12.0)
	projectile_velocity = Vector2(facing * junbae.mirror_speed * 0.8, 0.0)
	projectile_left = junbae.mirror_distance / maxf(1.0, junbae.mirror_speed * 0.8)
	mirror_position = position + Vector2(facing * junbae.mirror_distance, -12.0)

func _tick_projectile(delta: float) -> void:
	if projectile_kind.is_empty():
		return
	if projectile_kind == "altino":
		projectile_velocity.y += movement.gravity * delta
	else:
		projectile_left = maxf(0.0, projectile_left - delta)
	projectile_position += projectile_velocity * delta
	if projectile_kind == "meme":
		projectile_velocity.y = move_toward(projectile_velocity.y, 0.0, 210.0 * delta)
		if absf(projectile_velocity.y) < 1.0:
			projectile_kind = ""
	elif projectile_kind == "mirror_first" and projectile_left <= 0.0:
		projectile_position = mirror_position
		var target: Fighter = null
		if get_parent().has_method("nearest_fighter"):
			target = get_parent().call("nearest_fighter", mirror_position, projectile_owner_id) as Fighter
		if target != null:
			projectile_velocity = (target.position - mirror_position).normalized() * junbae.mirror_speed
			projectile_kind = "mirror_second"
			projectile_left = 1.2
		else:
			projectile_kind = ""
	elif projectile_kind == "altino" and (projectile_position.x < 0.0 or projectile_position.x > 1280.0 or projectile_position.y < 0.0 or projectile_position.y > 720.0):
		_emote("알티노라이트 최악!", 0.6)
		projectile_kind = ""
	elif projectile_kind == "mirror_second" and projectile_left <= 0.0:
		projectile_kind = ""
	elif projectile_kind == "cipher_coin" and projectile_left <= 0.0:
		projectile_kind = ""
	queue_redraw()

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

func attack_data_for_kind(kind: String = "") -> AttackData:
	if kind.is_empty():
		kind = attack_kind
	if character_id != &"junbae":
		return attacks[kind] if attacks.has(kind) else attacks["forward"]
	var data := AttackData.new()
	match kind:
		"junbae_neutral_1", "junbae_neutral_2":
			data.damage = junbae.neutral_damage
			data.percent_increase = junbae.neutral_percent
			data.base_launch_speed = 300.0 if kind.ends_with("1") else 360.0
			data.hitstun_seconds = 0.24
			data.reach = junbae.neutral_reach
			data.width = junbae.neutral_width
			data.launch_direction = Vector2(1, -0.25)
		"up":
			data.damage = junbae.up_damage
			data.percent_increase = junbae.up_percent
			data.base_launch_speed = 330.0
			data.hitstun_seconds = 0.18
			data.reach = junbae.up_reach
			data.width = junbae.up_width
			data.launch_direction = Vector2(0, -1)
		"down":
			data.damage = junbae.down_damage
			data.percent_increase = junbae.down_percent
			data.base_launch_speed = 680.0
			data.hitstun_seconds = 0.48
			data.reach = junbae.down_reach
			data.width = junbae.down_width
			data.launch_direction = Vector2(0, 1)
		"ground_down":
			data.damage = junbae.down_damage
			data.percent_increase = junbae.down_percent
			data.base_launch_speed = 680.0
			data.hitstun_seconds = 0.48
			data.reach = junbae.down_reach
			data.width = junbae.ground_down_width
			data.launch_direction = Vector2(1, -0.12)
		"sword":
			data.damage = junbae.sword_damage
			data.percent_increase = junbae.sword_percent
			data.base_launch_speed = 460.0
			data.reach = junbae.sword_range
			data.width = junbae.sword_width
			data.launch_direction = Vector2(1, -0.15)
		"altino_blast":
			data.damage = junbae.altino_damage + 2.0
			data.percent_increase = junbae.altino_percent + 2.0
			data.base_launch_speed = 540.0
			data.reach = 108.0
			data.width = 132.0
			data.launch_direction = Vector2(1, -0.4)
		"meme":
			data.damage = junbae.meme_damage
			data.percent_increase = junbae.meme_percent
			data.base_launch_speed = 240.0
			data.reach = 38.0
			data.width = 44.0
			data.launch_direction = Vector2(0, -1)
		"digital_side":
			data.damage = junbae.digital_side_damage * (1.35 if digital_skill_airborne else 1.0)
			data.percent_increase = junbae.digital_side_percent * (1.35 if digital_skill_airborne else 1.0)
			data.base_launch_speed = 510.0
			data.reach = 120.0
			data.width = 92.0
			data.launch_direction = Vector2(1, -0.25)
		"digital_up":
			data.damage = junbae.digital_up_damage
			data.percent_increase = junbae.digital_up_percent
			data.base_launch_speed = junbae.digital_up_launch
			data.reach = 94.0
			data.width = 94.0
			data.launch_direction = Vector2(0, -1)
		"mirror_first":
			data.damage = 5.0
			data.percent_increase = 5.0
			data.base_launch_speed = 280.0
			data.reach = 30.0
			data.width = 30.0
			data.launch_direction = Vector2(1, -0.05)
		"mirror_second":
			data.damage = junbae.mirror_damage
			data.percent_increase = junbae.mirror_percent
			data.base_launch_speed = junbae.mirror_speed
			data.reach = 36.0
			data.width = 36.0
			data.launch_direction = Vector2(1, 0)
		"finisher":
			data.damage = junbae.finisher_damage
			data.percent_increase = junbae.finisher_percent
			data.base_launch_speed = junbae.finisher_launch
			data.hitstun_seconds = 0.55
			data.reach = junbae.finisher_reach
			data.width = junbae.finisher_width
			data.launch_direction = Vector2(1, -0.35)
		_:
			if kind == "cipher_coin":
				data.damage = 3.0
				data.percent_increase = 3.0
				data.base_launch_speed = 150.0
				data.reach = 22.0
				data.width = 22.0
				data.launch_direction = Vector2(1, -0.2)
				return data
			return attacks["forward"]
	return data

func attack_box() -> Rect2:
	var data: AttackData = attack_data_for_kind()
	if attack_kind == "up" or attack_kind == "digital_up":
		return Rect2(Vector2(-data.width / 2.0, -HALF_SIZE.y - data.reach), Vector2(data.width, data.reach))
	if attack_kind == "down":
		return Rect2(Vector2(-data.width / 2.0, HALF_SIZE.y), Vector2(data.width, data.reach))
	if attack_kind == "ground_down":
		return Rect2(Vector2(HALF_SIZE.x if facing > 0.0 else -HALF_SIZE.x - data.reach, 8.0), Vector2(data.reach, data.width))
	if attack_kind == "finisher":
		return Rect2(Vector2(-data.reach / 2.0, -HALF_SIZE.y - 12.0), Vector2(data.reach, data.width))
	if attack_kind == "altino_blast":
		return Rect2(projectile_position - position - Vector2(data.width / 2.0, data.width / 2.0), Vector2(data.width, data.width))
	return Rect2(Vector2(HALF_SIZE.x if facing > 0 else -HALF_SIZE.x - data.reach, -data.width / 2.0), Vector2(data.reach, data.width))

func attack_direction() -> Vector2:
	var data: AttackData = attack_data_for_kind()
	if attack_kind == "mirror_first" or attack_kind == "mirror_second":
		return projectile_velocity.normalized()
	return Vector2(data.launch_direction.x * facing, data.launch_direction.y).normalized()

func _draw() -> void:
	var color := tint
	if invulnerability_left > 0.0:
		color.a = 0.45 + 0.35 * absf(sin(invulnerability_left * 12.0))
	if character_id != &"junbae":
		draw_rect(Rect2(-HALF_SIZE, HALF_SIZE * 2.0), color)
	else:
		if is_instance_valid(character_sprite):
			character_sprite.flip_h = facing < 0.0
			character_sprite.modulate.a = color.a
		if digital_mode:
			draw_rect(Rect2(-HALF_SIZE - Vector2(4, 4), HALF_SIZE * 2.0 + Vector2(8, 8)), Color(0.25, 0.95, 1.0, 0.22), false, 3.0)
	draw_line(Vector2(0, -10), Vector2(facing * 15, -10), Color.WHITE, 3.0)
	var tag_size := 28 if tag_emphasis else 16
	var tag_top := -HALF_SIZE.y - 8.0
	var tag := UiStyle.DUMMY if is_dummy else "P%d" % player_slot
	draw_string(ThemeDB.fallback_font, Vector2(-60, tag_top), tag, HORIZONTAL_ALIGNMENT_CENTER, 120, tag_size, tint if tag_emphasis else Color.WHITE)
	if is_local:
		draw_string(ThemeDB.fallback_font, Vector2(-40, tag_top - tag_size - 2.0), UiStyle.ME_MARK, HORIZONTAL_ALIGNMENT_CENTER, 80, 18, tint.lightened(0.3))
	if emote_left > 0.0 and not emote_text.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(-110, -124), emote_text, HORIZONTAL_ALIGNMENT_CENTER, 220, 18, Color("fff1a7"))
	if attack_cooldown > movement.attack_cooldown - 0.12:
		draw_rect(attack_visual, Color(1, 1, 1, 0.25))
		draw_rect(attack_visual, Color.WHITE, false, 2.0)
	if character_id == &"junbae" and not projectile_kind.is_empty():
		var local_projectile := projectile_position - position
		var projectile_color := Color("ffd447") if projectile_kind == "altino" else (Color("bce7ff") if projectile_kind == "meme" else Color("7bfff3"))
		draw_circle(local_projectile, 15.0, projectile_color)
		draw_circle(local_projectile, 15.0, Color.WHITE, false, 2.0)
		if projectile_kind == "altino":
			draw_string(ThemeDB.fallback_font, local_projectile + Vector2(-29, 5), "ALTINO", HORIZONTAL_ALIGNMENT_LEFT, 65, 11, Color.BLACK)
		elif projectile_kind == "meme":
			draw_string(ThemeDB.fallback_font, local_projectile + Vector2(-18, 5), "어흐", HORIZONTAL_ALIGNMENT_LEFT, 40, 12, Color.BLACK)
		elif projectile_kind == "mirror_first":
			draw_line(local_projectile + Vector2(0, -20), mirror_position - position, Color("ff8cda"), 2.0)
			draw_rect(Rect2(mirror_position - position - Vector2(9, 18), Vector2(18, 36)), Color("ff8cda"), false, 2.0)
	if character_id == &"junbae" and attack_kind == "finisher" and attack_cooldown > 1.0:
		draw_string(ThemeDB.fallback_font, Vector2(-80, -112), "대 준 배", HORIZONTAL_ALIGNMENT_CENTER, 160, 28, Color("ffe06c"))
		for object_index in range(5):
			var item_x := facing * float(34 + object_index * 24)
			var item_y := -58.0 - absf(2.0 - float(object_index)) * 12.0
			draw_rect(Rect2(Vector2(item_x, item_y), Vector2(14, 10)), Color("ffe06c"))
	if emote_text == "천재인가?":
		draw_circle(Vector2(0, -112), 10.0, Color("ffe76b"))
		draw_line(Vector2(-5, -112), Vector2(5, -112), Color.WHITE, 2.0)
