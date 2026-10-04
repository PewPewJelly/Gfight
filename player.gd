class_name SmashPlayer
extends CharacterBody2D

## 대난투 스타일 캐릭터 컨트롤러
## 확정된 규칙(A/D 이동, W 점프 2회, S 플랫폼 하강, J 4방향 공격, 넉백 배율, 장외 스톡 차감, 3초 무적) 반영

signal knockback_multiplier_changed(new_value: float)
signal stocks_changed(new_value: int)
signal attack_started(attack_name: String)
signal attack_blocked()
signal hit_landed(target: SmashPlayer, damage: float)
signal blast_out()

@export var player_id: int = 1
@export var is_dummy: bool = false # 연습용 더미 모드 (가만히 서서 맞아주기)

## -------------------------------------------------------------
## 기본 규칙 & 핸드오프 상태 변수
## -------------------------------------------------------------
var stocks: int = 3
var knockback_multiplier: float = 0.0 # 0%로 시작
var is_in_knockback: bool = false
var is_invincible: bool = false
var jump_count: int = 2
const MAX_JUMPS: int = 2

var facing_direction: float = 1.0 # 1.0: 오른쪽, -1.0: 왼쪽
var is_attacking: bool = false
var attack_cooldown: float = 0.0

## -------------------------------------------------------------
## 대난투 스타일 물리 수치
## -------------------------------------------------------------
const MOVE_SPEED: float = 340.0
const ACCELERATION: float = 2200.0
const FRICTION: float = 1800.0
const AIR_ACCEL: float = 1400.0
const AIR_FRICTION: float = 500.0
const GRAVITY: float = 1300.0
const MAX_FALL_SPEED: float = 850.0
const JUMP_VELOCITY: float = -520.0
const DOUBLE_JUMP_VELOCITY: float = -470.0

## 노드 참조
@onready var sprite: Sprite2D = $Sprite2D
@onready var ground_checker: RayCast2D = $GroundChecker
@onready var attack_area: Area2D = $AttackArea
@onready var attack_shape: CollisionShape2D = $AttackArea/CollisionShape2D
@onready var attack_visual: ColorRect = $AttackVisual
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	# 공격 판정 초기 비활성화
	if attack_area:
		attack_area.monitoring = false
	if attack_visual:
		attack_visual.visible = false

	# 플레이어별 색상 구분
	if sprite:
		if player_id == 1:
			sprite.modulate = Color(0.3, 0.7, 1.0) # 1P: 파란색
		else:
			sprite.modulate = Color(1.0, 0.4, 0.4) # 2P: 빨간색


func _physics_process(delta: float) -> void:
	# 1. 중력 적용
	if not is_on_floor():
		velocity.y = min(velocity.y + GRAVITY * delta, MAX_FALL_SPEED)

	# 2. 땅(플랫폼) 접촉 판정 -> 점프 기회 2회 충전
	if is_on_floor() or (ground_checker and ground_checker.is_colliding()):
		jump_count = MAX_JUMPS
		# 넉백 상태에서 바닥에 닿고 속도가 줄어들면 넉백 해제
		if is_in_knockback and velocity.length() < 300.0:
			_end_knockback()

	# 3. 넉백 감속 처리
	if is_in_knockback:
		var knockback_drag: float = 650.0 * delta
		velocity.x = move_toward(velocity.x, 0.0, knockback_drag)
		if velocity.length() < 80.0:
			_end_knockback()

	# 4. 공격 후딜레이 처리
	if attack_cooldown > 0.0:
		attack_cooldown -= delta
		if attack_cooldown <= 0.0:
			is_attacking = false

	# 5. 플레이어 입력 처리 (더미가 아니고, 넉백 중이 아닐 때만 허용)
	if not is_dummy and not is_in_knockback:
		_handle_player_input(delta)

	# 6. 실제 이동 반영
	move_and_slide()

	# 7. 장외(Blast Zone) 판정
	_check_blast_zone()


## -------------------------------------------------------------
## 이동, 점프, 플랫폼 하강 입력 처리
## -------------------------------------------------------------
func _handle_player_input(delta: float) -> void:
	var prefix = "p2_" if player_id == 2 else ""

	# [A/D] 좌우 이동
	var move_input: float = 0.0
	if player_id == 1:
		move_input = Input.get_axis("move_left", "move_right")
	else:
		if Input.is_action_pressed("p2_move_left"):
			move_input -= 1.0
		if Input.is_action_pressed("p2_move_right"):
			move_input += 1.0

	# 바라보는 방향 갱신
	if move_input != 0.0:
		facing_direction = sign(move_input)
		if sprite:
			sprite.scale.x = abs(sprite.scale.x) * facing_direction

	# 가감속 물리 계산 (지상 vs 공중)
	if move_input != 0.0:
		var accel = ACCELERATION if is_on_floor() else AIR_ACCEL
		velocity.x = move_toward(velocity.x, move_input * MOVE_SPEED, accel * delta)
	else:
		var friction = FRICTION if is_on_floor() else AIR_FRICTION
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)

	# [W] 점프 (점프 기회 소모)
	var jump_pressed: bool = false
	if player_id == 1:
		jump_pressed = Input.is_action_just_pressed("move_up")
	else:
		jump_pressed = Input.is_action_just_pressed("p2_move_up")

	if jump_pressed:
		try_jump()

	# [S] 플랫폼 아래로 이동 (드롭스루)
	var down_pressed: bool = false
	if player_id == 1:
		down_pressed = Input.is_action_just_pressed("move_down")
	else:
		down_pressed = Input.is_action_just_pressed("p2_move_down")

	if down_pressed and is_on_floor():
		_drop_through_platform()

	# [J] 공격
	var attack_pressed: bool = false
	if player_id == 1:
		attack_pressed = Input.is_action_just_pressed("attack")
	else:
		attack_pressed = Input.is_action_just_pressed("p2_attack")

	if attack_pressed:
		try_attack()


## 점프 시도
func try_jump() -> bool:
	# 넉백 중 점프 불가 (차단된 점프는 기회를 소모하지 않음)
	if is_in_knockback:
		return false

	if jump_count > 0:
		if is_on_floor():
			velocity.y = JUMP_VELOCITY
		else:
			velocity.y = DOUBLE_JUMP_VELOCITY
			_create_jump_puff_effect()
		jump_count -= 1
		return true

	return false


## 플랫폼 아래로 통과 (One-way platform drop-through)
func _drop_through_platform() -> void:
	# 1픽셀 아래로 내려서 원웨이 플랫폼 아래로 낙하
	position.y += 2.0


## -------------------------------------------------------------
## 대난투식 4방향 공격 시스템 (J 키)
## -------------------------------------------------------------
func can_attack() -> bool:
	if is_in_knockback or is_attacking:
		return false
	return true


func try_attack() -> bool:
	if not can_attack():
		attack_blocked.emit()
		return false

	_execute_attack()
	return true


func _execute_attack() -> void:
	is_attacking = true
	attack_cooldown = 0.28 # 쿨다운

	var is_up: bool = Input.is_action_pressed("move_up") if player_id == 1 else Input.is_action_pressed("p2_move_up")
	var is_down: bool = Input.is_action_pressed("move_down") if player_id == 1 else Input.is_action_pressed("p2_move_down")
	var is_horizontal: bool = false
	if player_id == 1:
		is_horizontal = Input.is_action_pressed("move_left") or Input.is_action_pressed("move_right")
	else:
		is_horizontal = Input.is_action_pressed("p2_move_left") or Input.is_action_pressed("p2_move_right")

	# 방향 결정 규칙:
	# 1. 위(W) 유지: 위 틸트 (Up Tilt)
	# 2. 아래(S) 유지: 아래 틸트 (Down Tilt)
	# 3. 앞(A/D) 유지: 앞 틸트 (Forward Tilt)
	# 4. 방향키 없음: 중립 잽 (Neutral Jab)
	var attack_name = "neutral"
	var damage_add: float = 3.0
	var knockback_power: float = 380.0
	var knockback_dir: Vector2 = Vector2(facing_direction, -0.4).normalized()
	var hitbox_offset: Vector2 = Vector2(40 * facing_direction, -10)
	var hitbox_size: Vector2 = Vector2(45, 35)

	if is_up:
		attack_name = "up_tilt"
		damage_add = 9.0
		knockback_power = 550.0
		knockback_dir = Vector2(facing_direction * 0.2, -1.0).normalized()
		hitbox_offset = Vector2(10 * facing_direction, -55)
		hitbox_size = Vector2(50, 60)
	elif is_down:
		attack_name = "down_tilt"
		damage_add = 8.0
		knockback_power = 480.0
		knockback_dir = Vector2(facing_direction * 0.8, -0.5).normalized()
		hitbox_offset = Vector2(35 * facing_direction, 20)
		hitbox_size = Vector2(55, 30)
	elif is_horizontal:
		attack_name = "forward_tilt"
		damage_add = 12.0
		knockback_power = 650.0
		knockback_dir = Vector2(facing_direction, -0.3).normalized()
		hitbox_offset = Vector2(50 * facing_direction, -5)
		hitbox_size = Vector2(65, 40)

	attack_started.emit(attack_name)
	_perform_hitbox(hitbox_offset, hitbox_size, damage_add, knockback_power, knockback_dir)


## 히트박스 전개 및 피격자 검출
func _perform_hitbox(offset: Vector2, size: Vector2, damage: float, kb_power: float, kb_dir: Vector2) -> void:
	if not attack_area or not attack_shape:
		return

	# 히트박스 위치 및 크기 설정
	attack_area.position = offset
	var rect_shape = RectangleShape2D.new()
	rect_shape.size = size
	attack_shape.shape = rect_shape

	# 시각 효과 갱신
	if attack_visual:
		attack_visual.position = offset - size * 0.5
		attack_visual.size = size
		attack_visual.visible = true
		attack_visual.modulate = Color(1.0, 0.9, 0.2, 0.8) # 황금빛 슬래시
		var tween = create_tween()
		tween.tween_property(attack_visual, "modulate:a", 0.0, 0.15)
		tween.tween_callback(func(): attack_visual.visible = false)

	# 히트박스 활성화 (약 0.12초간 지속)
	attack_area.monitoring = true
	var timer = get_tree().create_timer(0.12)
	timer.timeout.connect(func():
		if is_instance_valid(attack_area):
			attack_area.monitoring = false
	)

	# 적중 대상 처리
	var bodies = attack_area.get_overlapping_bodies()
	for body in bodies:
		if body != self and body.has_method("take_hit"):
			body.take_hit(self, damage, kb_dir, kb_power)
			hit_landed.emit(body, damage)


func _on_attack_area_body_entered(body: Node2D) -> void:
	# 공격 활성화 중 진입한 적에게 명중
	if attack_area.monitoring and body != self and body.has_method("take_hit"):
		# 현재 공격 데이터로 타격 (단타 판정)
		pass


## -------------------------------------------------------------
## 피격 & 대난투 넉백 처리
## -------------------------------------------------------------
func take_hit(attacker, damage_add: float, kb_dir: Vector2, base_power: float) -> void:
	if is_invincible:
		return

	# [확정 규칙] 공격이 맞으면 맞은 상대의 배율만 증가
	knockback_multiplier += damage_add
	knockback_multiplier_changed.emit(knockback_multiplier)

	# [확정 규칙] 배율이 높을수록 동일 피격에서 더 멀리 날아감
	# 대난투식 넉백 계산식: base * (1 + 배율/100 * 1.2)
	var final_power: float = base_power * (1.0 + (knockback_multiplier / 100.0) * 1.2)
	velocity = kb_dir * final_power

	# 넉백 상태 돌입 (이동, 점프, 공격 조작 차단)
	is_in_knockback = true
	is_attacking = false

	# 피격 연출 (빨갛게 번쩍임 + 흔들림)
	if sprite:
		var orig_mod = sprite.modulate
		sprite.modulate = Color(2.5, 0.3, 0.3)
		var tween = create_tween()
		tween.tween_property(sprite, "modulate", orig_mod, 0.25)


func _end_knockback() -> void:
	is_in_knockback = false


## -------------------------------------------------------------
## 장외(Blast Zone) 판정 & 스톡 관리
## -------------------------------------------------------------
func _check_blast_zone() -> void:
	# 화면 밖 경계 판정
	var out_left = position.x < -150.0
	var out_right = position.x > 1430.0
	var out_top = position.y < -350.0
	var out_bottom = position.y > 850.0

	if out_left or out_right or out_top or out_bottom:
		_on_blast_zone_death()


func _on_blast_zone_death() -> void:
	blast_out.emit()

	# [확정 규칙] 장외 한 번에 스톡이 1개 차감
	stocks -= 1
	stocks_changed.emit(stocks)

	# [확정 규칙] 스톡 차감 즉시 넉백 배율 0%로 초기화
	knockback_multiplier = 0.0
	knockback_multiplier_changed.emit(knockback_multiplier)

	velocity = Vector2.ZERO
	is_in_knockback = false
	is_attacking = false

	if stocks > 0:
		# 재스폰: 플랫폼 위 중앙으로 이동 후 3초 무적
		respawn()
	else:
		# 스톡 0개: 탈락 처리
		visible = false
		position = Vector2(9999, 9999)


func respawn() -> void:
	position = Vector2(640, 250) # 플랫폼 위 공중에서 강하
	velocity = Vector2.ZERO
	is_invincible = true

	# 3초 무적 깜빡임 연출
	var tween = create_tween()
	for i in range(6):
		tween.tween_property(sprite, "modulate:a", 0.3, 0.25)
		tween.tween_property(sprite, "modulate:a", 1.0, 0.25)
	tween.tween_callback(func(): is_invincible = false)


func _create_jump_puff_effect() -> void:
	# 2단 점프 시 발밑 작은 점프 링 연출
	pass
