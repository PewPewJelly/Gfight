class_name PlayerAttack
extends Node

## ==============================================================================
## 공격 구현 핸드오프 (PlayerAttack)
## 확정된 요구사항만 반영하며, 미정 사항에 대한 임의의 수치나 로직은 배제합니다.
## ==============================================================================

## [시그널] 상태 변화 및 이벤트 통지
signal attack_started()
signal attack_blocked()
signal hit_landed(target: PlayerAttack)
signal hit_missed()
signal knockback_multiplier_changed(new_value: float)

## [확정 요구사항 / 임시 조치] 피격으로 인한 넉백 중인지 여부 (외부/임시 시스템 제공)
## 실제 넉백 시스템 도입 전 공격 가능 여부를 가리는 임시 조건 플래그입니다.
## 실제 넉백 시스템 도입 시 해당 시스템의 상태·시작 및 종료 기준에 맞춰 조건을 변경합니다.
var is_in_knockback: bool = false

## [확정 요구사항] 각 플레이어가 보유한 넉백 배율
## 플레이어별로 개별 관리하며, 게임 시작 시 0% (0.0)입니다.
## 스톡이 1개 차감되면 즉시 0%로 초기화됩니다.
var knockback_multiplier: float = 0.0

## [미정 사항] 현재 공격의 넉백 배율 증가량 (기획 수치 미정: ??%)
## 공격 종류와 배율 증가량이 확정되면 각 공격 데이터에 맞게 설정됩니다.
var attack_multiplier_increase: float = 0.0


func _unhandled_input(event: InputEvent) -> void:
	# [확정 요구사항] J를 누르면 공격한다.
	if event.is_action_pressed("attack"):
		try_attack()


## [넉백 중 공격 제한의 임시 적용]
## 넉백 중 공격 불가는 임시 조치로, 공격 가능 여부를 가리는 조건만 먼저 마련합니다.
## 현재 메모만으로 넉백 상태를 판정하는 로직이나 지속시간을 새로 정의하지 않습니다.
func can_attack() -> bool:
	if is_in_knockback:
		return false
	return true


## [구현 처리 흐름 1~2] 공격 시작 시도
## 공격 가능한 상태에서 J 입력이 공격 시작으로 연결됩니다.
## 임시 넉백 중 조건이 참이면 공격이 시작되지 않습니다.
func try_attack() -> bool:
	if not can_attack():
		attack_blocked.emit()
		return false

	attack_started.emit()
	_execute_attack()
	return true


## [구현 처리 흐름 3] 공격 실행
func _execute_attack() -> void:
	# 공격의 방향과 범위에 맞게 명중 여부를 판정합니다.
	# 방향 결정 규칙, 공격별 범위와 판정 방식은 미정 사항이 결정되어야 구체화할 수 있습니다.
	var attack_direction: Vector2 = _get_attack_direction()
	_check_hit_box(attack_direction)


## [미정 사항] 방향 관련 입력 및 방향 결정
## 확정: 위쪽은 W, 앞쪽은 A·D, 아래쪽은 S와 연결된다.
## 미정: J와 W·A·D·S의 조합 방식, 방향 입력이 없거나 여러 방향을 동시에 누를 때의 우선순위,
##       '앞'의 의미(캐릭터가 바라보는 방향 vs 좌우 절대 방향).
## 미정 항목에는 임시 수치나 동작을 넣지 않습니다.
func _get_attack_direction() -> Vector2:
	# TODO: 방향 결정 규칙 확정 후 구현
	return Vector2.ZERO


## [미정 사항] 공격 범위 및 명중 판정
## 확정: 공격에 따라 범위가 다르다.
## 미정: 공격 종류 수, 각 공격의 판정 모양·크기·위치, 유효 시간, 다중 대상 명중 처리.
## 미정 항목에는 임시 수치나 동작을 넣지 않습니다.
func _check_hit_box(_direction: Vector2) -> void:
	# TODO: 공격 범위 판정 방식 확정 후 실제 감지 로직 구현
	var targets_hit: Array[PlayerAttack] = []

	if targets_hit.is_empty():
		_on_attack_missed()
	else:
		for target in targets_hit:
			_on_hit_target(target)


## [구현 처리 흐름 4] 명중 시 처리
func _on_hit_target(target: PlayerAttack) -> void:
	# [확정 요구사항] 공격이 상대에게 맞으면 공격자가 아닌 맞은 상대의 넉백 배율이 증가한다.
	if target != null and target != self:
		target.apply_knockback_multiplier_increase(attack_multiplier_increase)
		hit_landed.emit(target)


## 공격 빗나감 처리
func _on_attack_missed() -> void:
	# [확인 기준] 공격이 빗나가면 넉백 배율 증가 처리가 실행되지 않는다.
	hit_missed.emit()


## [확정 요구사항] 피격 시 넉백 배율 증가
## [미정 사항] 증가량, 누적 방식, 최대치, 초기화 조건 확정 후 수치 반영 필요.
## 외부(적중된 공격)로부터 전달받은 증가량만큼 배율을 증가시킵니다.
func apply_knockback_multiplier_increase(amount: float = 0.0) -> void:
	if amount > 0.0:
		knockback_multiplier += amount
		knockback_multiplier_changed.emit(knockback_multiplier)


## [확정 요구사항 / 장외 규칙 연동] 스톡 차감 시 넉백 배율 초기화
## 스톡이 1개 차감되면 해당 플레이어의 넉백 배율을 즉시 0%로 초기화합니다.
func reset_knockback_multiplier() -> void:
	knockback_multiplier = 0.0
	knockback_multiplier_changed.emit(knockback_multiplier)
