extends Node2D

const SmashPlayer = preload("res://player.gd")

@onready var p1: SmashPlayer = $Players/Player1
@onready var p2: SmashPlayer = $Players/Player2

@onready var p1_percent_label: Label = $UI/P1Card/PercentLabel
@onready var p2_percent_label: Label = $UI/P2Card/PercentLabel

@onready var p1_stocks_label: Label = $UI/P1Card/StocksLabel
@onready var p2_stocks_label: Label = $UI/P2Card/StocksLabel

@onready var mode_label: Label = $UI/ModeLabel
@onready var action_log_label: Label = $UI/ActionLogLabel


func _ready() -> void:
	p1.player_id = 1
	p2.player_id = 2
	p2.is_dummy = true # 기본값: 연습용 샌드백 모드

	p1.knockback_multiplier_changed.connect(func(v): _update_percent(1, v))
	p2.knockback_multiplier_changed.connect(func(v): _update_percent(2, v))

	p1.stocks_changed.connect(func(v): _update_stocks(1, v))
	p2.stocks_changed.connect(func(v): _update_stocks(2, v))

	p1.attack_started.connect(func(atk): _log_action("P1 공격: %s" % _get_attack_korean(atk)))
	p1.hit_landed.connect(func(target, dmg): _log_action("P1 타격 성공! (+%d%%)" % int(dmg)))
	p2.hit_landed.connect(func(target, dmg): _log_action("P2 타격 성공! (+%d%%)" % int(dmg)))

	p1.blast_out.connect(func(): _log_action(">> P1 장외! (스톡 차감 & 배율 리셋)"))
	p2.blast_out.connect(func(): _log_action(">> P2 장외! (스톡 차감 & 배율 리셋)"))

	_update_percent(1, 0.0)
	_update_percent(2, 0.0)
	_update_stocks(1, 3)
	_update_stocks(2, 3)
	_update_mode_label()


func _input(event: InputEvent) -> void:
	# F1: 2P 더미 모드 전환
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F1:
			p2.is_dummy = not p2.is_dummy
			_update_mode_label()
		elif event.physical_keycode == KEY_R:
			get_tree().reload_current_scene()


func _update_percent(pid: int, value: float) -> void:
	var label = p1_percent_label if pid == 1 else p2_percent_label
	label.text = "%d%%" % int(value)

	# 배율이 높을수록 붉은색으로 강조
	if value < 50.0:
		label.modulate = Color.WHITE
	elif value < 100.0:
		label.modulate = Color(1.0, 0.8, 0.2) # 노랑
	elif value < 150.0:
		label.modulate = Color(1.0, 0.4, 0.1) # 주황
	else:
		label.modulate = Color(1.0, 0.2, 0.2) # 빨강


func _update_stocks(pid: int, value: int) -> void:
	var label = p1_stocks_label if pid == 1 else p2_stocks_label
	var hearts = ""
	for i in range(value):
		hearts += "● "
	label.text = "스톡: %s" % hearts if value > 0 else "스톡 소진 (탈락)"


func _update_mode_label() -> void:
	if p2.is_dummy:
		mode_label.text = "[2P: 샌드백 모드] (F1 키로 2인 플레이 전환: 방향키 + L 키)"
	else:
		mode_label.text = "[2P: 수동 조작 모드] (방향키 이동/점프/하강 + L 키 공격) (F1 키로 샌드백 전환)"


func _log_action(text: String) -> void:
	action_log_label.text = text


func _get_attack_korean(atk: String) -> String:
	match atk:
		"neutral": return "제자리 잽 (J)"
		"forward_tilt": return "앞 틸트 (A/D + J)"
		"up_tilt": return "위 틸트 (W + J)"
		"down_tilt": return "아래 틸트 (S + J)"
	return atk
