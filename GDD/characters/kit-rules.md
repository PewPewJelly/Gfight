# 캐릭터 고유 코드 작성 규칙

> 캐릭터 고유 스크립트(`CharacterKit`)와 투사체 동작 스크립트(`ProjectileBehavior`)를 쓸 때 지키는 규칙이다. AI에게 기믹 구현을 맡길 때 이 문서를 함께 준다.
> 규칙을 어기면 온라인 롤백에서 DESYNC가 난다. `tests/character_contract_test.gd`가 카탈로그의 모든 캐릭터를 검사한다.

## 1. 코드가 필요한지 먼저 본다

| 만들고 싶은 것 | 방법 |
|---|---|
| 피해, 범위, 선딜·지속·후딜, 재사용 대기, 사용 중 이동 제한, 포즈 PNG | 기술 데이터(`AttackData`, `SkillData`) |
| 몸 크기, 경기 PNG | 캐릭터 데이터(`CharacterDef`) |
| 직선, 포물선, 감속 투사체 | `BasicShot`의 수치 |
| 설치물, 지속 장판 | `BasicShot` + 속도 0 + 긴 수명 |
| 빔 | `BasicShot` + 긴 크기 + 짧은 수명 |
| 유도, 부메랑, 몸에 붙어 휘두르는 판정 | `HomingShot`, `BoomerangShot`, `FollowOwnerShot` |
| 새로운 움직임의 투사체, 분열, 착탄 폭발 | 새 동작 스크립트 `scripts/projectiles/<이름>_shot.gd` |
| 변신, 콤보, 게이지, 동시 입력, 투사체 재입력 폭발 | 고유 스크립트 `scripts/characters/<id>_kit.gd` |

## 2. 반드시 지킬 것

1. **스크립트에는 규칙과 `@export` 값만 둔다.** 스크립트 하나를 모든 파이터·투사체가 함께 쓰므로, `@export`가 아닌 멤버 변수를 만들면 안 된다.
2. **경기 중 바뀌는 값은 정해진 곳에만 둔다.** 고유 스크립트는 `fighter.kit_state`, 동작 스크립트는 `shot.vars`다. 넣을 수 있는 값은 숫자, 문자열, `bool`, `Vector2`, 배열, 딕셔너리뿐이고 객체는 안 된다.
3. **시작값은 `initial_state()`에서 돌려준다.** 장외와 재스폰 때 자동으로 다시 적용된다.
4. **시간은 틱으로 센다.** `await`, `Timer`, `Tween`, `create_timer`는 경기 규칙에 쓰지 않는다. `tick()`이나 `step()`에서 값을 줄인다.
5. **물리 노드와 새 노드를 만들지 않는다.** `Area2D`, `RigidBody2D`, `add_child`는 쓰지 않는다. 판정은 사각형 계산으로 하고 투사체는 `arena.spawn_projectile()`로 만든다.
6. **난수는 `arena.rng`만 쓴다.** `randf()`, `randi()`, 시계(`Time`)는 PC마다 값이 달라진다.
7. **쓰는 기술과 투사체는 `@export`로 선언한다.** 스냅샷은 리소스를 번호로 저장하는데, `@export`로 닿을 수 있어야 번호가 생긴다. `preload`나 `.new()`로 만든 기술은 시작되지 않는다.
8. **`draw()`와 `sprite()`는 읽기만 한다.** 연출은 상태에서 그린다. 롤백하면 상태가 되돌아가고 그림도 함께 맞춰진다.

## 3. 고유 스크립트 (`CharacterKit`)

| 함수 | 불리는 때 | 용도 |
|---|---|---|
| `initial_state()` | 경기 시작, 장외, 재스폰 | `kit_state` 시작값 |
| `tick(fighter, delta)` | 매 틱, 입력 처리 전 | 타이머, 게이지 |
| `handle_press(fighter, mask, attack_pressed, skill_pressed, airborne)` | 공격·스킬을 누른 틱 | `true`를 돌려주면 기본 기술 대신 처리한다 |
| `choose_move(fighter, slot, is_skill, move)` | 기본 기술이 정해진 뒤 | 콤보 단계처럼 다른 기술로 바꾼다 |
| `body_frozen(fighter)` | 매 틱 | `true`면 이동·중력이 멈추고 입력은 `handle_press`로만 간다. 피격 경직 중에는 무시된다 |
| `on_hit_dealt(fighter, target, hit)` | 내 기술·투사체가 맞았을 때 | 적중 시 효과 |
| `on_hit_taken(fighter, hit)` | 내가 맞았을 때 | 변신 해제 등 |
| `sprite(fighter)` | 그릴 때 | 표시할 PNG (없으면 `null`) |
| `draw(fighter)` | 그릴 때 | 말풍선 같은 추가 연출 |

슬롯 밖의 기술은 `@export`로 선언한 뒤 `fighter.start_move(기술)`로 시작한다.

## 4. 동작 스크립트 (`ProjectileBehavior`)

| 함수 | 불리는 때 | 기본 동작 |
|---|---|---|
| `on_spawn(shot, arena)` | 나타날 때 | 없음 |
| `step(shot, arena, delta)` | 매 틱 | 현재 속도로 직선 이동 |
| `on_hit(shot, arena, target)` | 파이터를 맞혔을 때 | 없음 (사라질지는 `after_hit` 값이 정한다) |
| `on_platform(shot, arena, surface)` | `hits_platforms`가 켜져 있고 플랫폼에 닿았을 때 | 사라짐 |
| `on_expire(shot, arena)` | 수명이 끝날 때 | 없음 |

`shot`에서 쓸 수 있는 값: `position`, `velocity`, `facing`, `age`(틱), `owner_id`, `data`, `hit_mask`, `alive`(`false`로 하면 사라짐), `vars`.
`arena`에서 쓸 수 있는 함수: `spawn_projectile()`, `projectiles_of()`, `fighter_by_id()`, `nearest_fighter()`, 값 `rng`, `platforms`.

## 5. 예시

```gdscript
class_name ChargeKit
extends CharacterKit
## 게이지를 모아 J+K로 강한 기술을 쓴다.

@export var full_seconds: float = 3.0
@export var charged_move: SkillData

func initial_state() -> Dictionary:
	return {"charge": 0.0}

func tick(fighter: Fighter, delta: float) -> void:
	fighter.kit_state.charge = minf(float(fighter.kit_state.charge) + delta, full_seconds)

func handle_press(fighter: Fighter, _mask: int, attack_pressed: bool, skill_pressed: bool, _airborne: bool) -> bool:
	if attack_pressed and skill_pressed and float(fighter.kit_state.charge) >= full_seconds:
		fighter.kit_state.charge = 0.0
		fighter.start_move(charged_move)
		return true
	return false
```

## 6. 확인

```powershell
godot --headless --path . --script res://tests/character_contract_test.gd
```

새 스크립트를 추가했다면 먼저 `godot --headless --path . --import`를 한 번 실행한다. 실패 메시지는 어긋난 값의 위치(예: `state.players[0].kit.charge`)를 알려 준다.
