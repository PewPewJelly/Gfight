extends Control

@onready var p1_attack: PlayerAttack = $Player1/PlayerAttack
@onready var p2_attack: PlayerAttack = $Player2/PlayerAttack

@onready var p1_sprite: Sprite2D = $Player1/Sprite2D
@onready var p2_sprite: Sprite2D = $Player2/Sprite2D

@onready var label_p1_status: Label = $UI/Panel/VBox/LabelP1Status
@onready var label_p2_multiplier: Label = $UI/Panel/VBox/LabelP2Multiplier
@onready var label_log: Label = $UI/Panel/VBox/LabelLog

@onready var btn_attack: Button = $UI/Panel/VBox/HBoxButtons/BtnAttack
@onready var btn_knockback_toggle: Button = $UI/Panel/VBox/HBoxButtons/BtnKnockbackToggle
@onready var btn_reset: Button = $UI/Panel/VBox/HBoxButtons/BtnReset

func _ready() -> void:
	# 공격별 증가량 예시 수치 설정 (기획 미정 수치이므로 테스트용으로 15% 설정)
	p1_attack.attack_multiplier_increase = 15.0

	# 시그널 연결
	p1_attack.attack_started.connect(_on_p1_attack_started)
	p1_attack.attack_blocked.connect(_on_p1_attack_blocked)
	p1_attack.hit_landed.connect(_on_p1_hit_landed)
	p1_attack.hit_missed.connect(_on_p1_hit_missed)

	p2_attack.knockback_multiplier_changed.connect(_on_p2_multiplier_changed)

	# 버튼 연결
	btn_attack.pressed.connect(_on_btn_attack_pressed)
	btn_knockback_toggle.pressed.connect(_toggle_knockback)
	btn_reset.pressed.connect(_on_btn_reset_pressed)

	_update_ui()
	_log_message("테스트 환경 준비 완료. J 키를 누르면 공격합니다.")


func _input(event: InputEvent) -> void:
	# K 키: 넉백 상태 토글
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_K:
			_toggle_knockback()
		elif event.physical_keycode == KEY_R:
			_on_btn_reset_pressed()


func _on_btn_attack_pressed() -> void:
	p1_attack.try_attack()


func _toggle_knockback() -> void:
	p1_attack.is_in_knockback = not p1_attack.is_in_knockback
	_update_ui()
	if p1_attack.is_in_knockback:
		_log_message("[상태 변경] 플레이어 1이 넉백 상태가 되었습니다. (공격 불가)")
		p1_sprite.modulate = Color(1.0, 0.4, 0.4)
	else:
		_log_message("[상태 변경] 플레이어 1의 넉백 상태가 해제되었습니다. (공격 가능)")
		p1_sprite.modulate = Color.WHITE


func _on_btn_reset_pressed() -> void:
	p2_attack.reset_knockback_multiplier()
	_log_message("[스톡 차감 시뮬레이션] 플레이어 2의 넉백 배율이 0%로 초기화되었습니다.")


func _on_p1_attack_started() -> void:
	_log_message(">> J 입력 감지: 플레이어 1이 공격을 시작했습니다!")
	
	# 공격 연출 (앞으로 튀어나갔다 복귀)
	var tween = create_tween()
	var original_x = p1_sprite.position.x
	tween.tween_property(p1_sprite, "position:x", original_x + 40.0, 0.08)
	tween.tween_property(p1_sprite, "position:x", original_x, 0.12)
	
	# 명중 테스트를 위해 상대방에게 적중 호출
	# (공격 범위 판정 규칙이 미정이므로 테스트용으로 상대방에게 전달)
	p1_attack._on_hit_target(p2_attack)


func _on_p1_attack_blocked() -> void:
	_log_message("[공격 차단] 넉백 중이므로 공격이 나가지 않습니다!")
	
	# 차단 연출 (흔들림)
	var tween = create_tween()
	var original_x = p1_sprite.position.x
	tween.tween_property(p1_sprite, "position:x", original_x - 10.0, 0.05)
	tween.tween_property(p1_sprite, "position:x", original_x + 10.0, 0.05)
	tween.tween_property(p1_sprite, "position:x", original_x, 0.05)


func _on_p1_hit_landed(target: PlayerAttack) -> void:
	_log_message("-> 공격 적중! 맞은 상대방(플레이어 2)의 넉백 배율 증가!")
	
	# 피격 연출 (빨간 깜빡임)
	var tween = create_tween()
	p2_sprite.modulate = Color(1.5, 0.2, 0.2)
	tween.tween_property(p2_sprite, "modulate", Color.WHITE, 0.2)


func _on_p1_hit_missed() -> void:
	_log_message("-> 공격이 빗나갔습니다. (배율 변동 없음)")


func _on_p2_multiplier_changed(new_val: float) -> void:
	_update_ui()


func _update_ui() -> void:
	if p1_attack.is_in_knockback:
		label_p1_status.text = "플레이어 1: 넉백 중 (공격 불가) [K키로 해제]"
		label_p1_status.modulate = Color(1.0, 0.3, 0.3)
	else:
		label_p1_status.text = "플레이어 1: 정상 상태 (공격 가능) [K키로 넉백]"
		label_p1_status.modulate = Color(0.3, 1.0, 0.3)

	label_p2_multiplier.text = "플레이어 2 넉백 배율: %d%%" % int(p2_attack.knockback_multiplier)


func _log_message(msg: String) -> void:
	label_log.text = msg
