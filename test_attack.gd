extends SceneTree

func _init() -> void:
	print("--- 공격 구현 핸드오프 검증 시작 ---")
	var all_passed = true

	# 인스턴스 준비
	var attacker = PlayerAttack.new()
	var victim = PlayerAttack.new()

	# [검증 0] 시작 시 넉백 배율은 0% (0.0)이다.
	if attacker.knockback_multiplier == 0.0 and victim.knockback_multiplier == 0.0:
		print("[PASS] 0. 초기 넉백 배율 0%% 확인 (attacker: %s, victim: %s)" % [attacker.knockback_multiplier, victim.knockback_multiplier])
	else:
		print("[FAIL] 0. 초기 넉백 배율이 0%%가 아닙니다.")
		all_passed = false

	# [확인 기준 1] 공격 가능한 상태에서 J 입력이 공격 시작으로 연결된다.
	attacker.is_in_knockback = false
	var flag_started = [false]
	attacker.attack_started.connect(func(): flag_started[0] = true)
	
	# InputEvent 시뮬레이션
	var input_event = InputEventAction.new()
	input_event.action = "attack"
	input_event.pressed = true
	attacker._unhandled_input(input_event)

	if flag_started[0]:
		print("[PASS] 1. J 입력(attack action) 수신 시 공격 시작 성공")
	else:
		print("[FAIL] 1. J 입력 시 공격 시작 실패")
		all_passed = false

	# [확인 기준 2] 임시 넉백 중 조건이 참이면 J 입력으로 공격이 시작되지 않는다.
	attacker.is_in_knockback = true
	flag_started[0] = false
	var flag_blocked = [false]
	attacker.attack_blocked.connect(func(): flag_blocked[0] = true)

	attacker._unhandled_input(input_event)

	if not flag_started[0] and flag_blocked[0]:
		print("[PASS] 2. 넉백 중 J 입력 수신 시 공격 차단 확인")
	else:
		print("[FAIL] 2. 넉백 중 J 입력 시 공격이 시작되었습니다.")
		all_passed = false

	# [확인 기준 3] 공격이 상대에게 맞으면 공격자가 아닌 맞은 상대의 넉백 배율이 증가한다.
	attacker.is_in_knockback = false
	attacker.attack_multiplier_increase = 15.0 # 공격별 증가량 예시 수치 설정
	var attacker_initial_mult = attacker.knockback_multiplier
	var victim_initial_mult = victim.knockback_multiplier

	# 명중 시뮬레이션
	attacker._on_hit_target(victim)

	if victim.knockback_multiplier == victim_initial_mult + 15.0 and attacker.knockback_multiplier == attacker_initial_mult:
		print("[PASS] 3. 피격자의 넉백 배율만 증가 확인 (공격자: %s, 피격자: %s)" % [attacker.knockback_multiplier, victim.knockback_multiplier])
	else:
		print("[FAIL] 3. 피격자 배율 증가 또는 공격자 배율 불변 조건 불일치")
		all_passed = false

	# [확인 기준 4] 공격이 빗나가면 넉백 배율 증가 처리가 실행되지 않는다.
	var victim_before_miss = victim.knockback_multiplier
	var flag_miss = [false]
	attacker.hit_missed.connect(func(): flag_miss[0] = true)

	attacker._on_attack_missed()

	if victim.knockback_multiplier == victim_before_miss and flag_miss[0]:
		print("[PASS] 4. 공격 빗나감 시 넉백 배율 변동 없음 확인 (victim: %s)" % [victim.knockback_multiplier])
	else:
		print("[FAIL] 4. 공격 빗나감 처리 오류")
		all_passed = false

	# [추가 검증 5] 스톡 차감 시 넉백 배율 즉시 0% 초기화
	victim.reset_knockback_multiplier()
	if victim.knockback_multiplier == 0.0:
		print("[PASS] 5. 스톡 차감 시 넉백 배율 0%% 초기화 확인")

	else:
		print("[FAIL] 5. 배율 초기화 실패")
		all_passed = false

	attacker.free()
	victim.free()

	if all_passed:
		print("--- 모든 확인 기준 테스트 성공! ---")
		quit(0)
	else:
		print("--- 테스트 실패 항목 있음 ---")
		quit(1)
