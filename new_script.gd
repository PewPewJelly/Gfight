class_name PlayerAttack
extends Node

## [확정 요구사항] 피격으로 인한 넉백 중인지 여부 (외부/임시 시스템에서 제공)
## 실제 넉백 시스템 도입 전 임시 조건으로 활용됩니다.
var is_in_knockback: bool = false

## [확정 요구사항] 각 캐릭터가 보유한 넉백 배율 (초기화 및 증가 규칙은 미정)
var knockback_multiplier: float = 1.0


func _unhandled_input(event: InputEvent) -> void:
	# [확정 요구사항] J 키 입력 시 공격 시도
	if event.is_action_pressed("attack"):
		try_attack()


## 공격 시작 시도
func try_attack() -> void:
	# [구현 처리 흐름 2] 임시 조건: 넉백 중이라면 공격 시작을 막음
	if is_in_knockback:
		return

	_execute_attack()


## 공격 실행 처리
func _execute_attack() -> void:
	# TODO: 미정 사항(방향 결정 규칙, 공격 종류 선택 방식) 확정 후 로직 구현 필요
	var attack_direction: Vector2 = _get_attack_direction()
	
	# TODO: 미정 사항(공격별 범위, 판정 방식, 유효 시간 등) 확정 후 판정 실행
	_check_hit_box(attack_direction)


## [미정 사항] 입력 방향 결정 로직
func _get_attack_direction() -> Vector2:
	# J와 W, A, D, S 조합 방식 및 '앞'의 의미(바라보는 방향 vs 좌우) 확정 필요
	return Vector2.ZERO


## [미정 사항] 공격 범위 및 명중 판정 처리
func _check_hit_box(_direction: Vector2) -> void:
	# TODO: 공격 판정 레이어/영역을 통해 상대 캐릭터(target) 감지 로직 구현
	var targets_hit: Array[PlayerAttack] = [] # 명중된 대상 목록 (임시 예시)

	for target in targets_hit:
		_on_hit_target(target)


## [구현 처리 흐름 4] 명중 시 상대방 처리
func _on_hit_target(target: PlayerAttack) -> void:
	if target != null:
		# [확정 요구사항] 공격자가 아닌 맞은 상대의 넉백 배율을 증가시킴
		target.apply_knockback_multiplier_increase()


## [확정 요구사항] 피격 시 넉백 배율 증가
func apply_knockback_multiplier_increase() -> void:
	# TODO: [미정 사항] 증가량, 누적 방식, 최대치, 초기화 조건 확정 후 수치 반영 필요
	pass
