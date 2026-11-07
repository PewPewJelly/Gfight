# Gfight: AI용 Godot 작업 지침

> AI(코딩 에이전트)가 이 저장소에서 Godot 작업을 할 때 따르는 규칙이다. 사람이 AI에게 일을 맡길 때도 이 문서를 기준으로 삼는다.
> 대상 엔진: **Godot 4.7.x, GDScript** · 문서 버전: **v1 (2026-10-10)**

## 이 문서 사용법

**AI가 지킬 것**

- 작업을 시작하기 전에 이 문서를 읽는다. §0 프로젝트 고정값과 §1 최우선 규칙은 매번 확인한다.
- 사용자의 직접 지시가 이 문서와 충돌하면 사용자 지시를 따르고, 보고에 그 사실을 적는다.
- 이 문서에 없는 판단은 "기존 코드의 방식 → Godot 4.7 공식 문서 → 사용자에게 질문" 순서로 정한다.

**사람이 이 문서를 고치는 방법**

- 프로젝트 값(버전, 레이어, 포트, 폴더)이 바뀌면 **§0 표만** 고친다. 다른 절은 §0을 참조한다.
- 규칙을 추가할 때는 해당 절 끝에 한 줄로 넣고, 맨 아래 **변경 이력**에 날짜와 요약을 남긴다.
- 절 번호(§0~§16)는 바꾸지 않는다. 다른 문서와 대화에서 번호로 참조하기 때문이다. 새 절은 끝에 번호를 이어 붙인다.
- AI 도구가 이 문서를 자동으로 읽게 하려면 도구가 자동으로 읽는 파일에 한 줄을 넣는다.
  - Claude Code: 루트 `CLAUDE.md`에 `@AI_GODOT_GUIDE.md`
  - Codex 등: 루트 `AGENTS.md`에 "작업 전 `AI_GODOT_GUIDE.md`를 읽고 따른다."

---

## 0. 프로젝트 고정값

> `origin/main` 기준(2026-10-10)이다. 브랜치마다 다를 수 있으므로 작업 브랜치의 `project.godot`에서 다시 확인한다.

| 항목 | 값 | 비고 |
|---|---|---|
| 엔진 | Godot **4.7.x** 표준판 (팀 검증 버전 4.7.2) | 팀 전원이 같은 마이너 버전을 쓴다 |
| 언어 | GDScript, 정적 타입 | C#·GDExtension 도입은 사람이 결정한다 |
| 장르 | 2D 플랫폼 난투. 최대 4인, 3스톡, 넉백 배율 | 규칙은 `GDD/` |
| 렌더러 | Forward+ (Windows 드라이버 d3d12) | 변경 금지 |
| 2D 물리 | Godot 기본 2D 물리 | `3d/physics_engine="Jolt Physics"`는 3D 설정이라 2D와 무관하다 |
| 화면 | 1280×720, stretch `canvas_items` | |
| 메인 씬 | `res://main.tscn` | |
| 오토로드 | `Session` = `res://scripts/session.gd` (연결·로비·경기 단계) | 새 오토로드는 사람 승인 |
| 네트워크 | ENet, 호스트 권한형, 포트 27840 (테스트 27849), 최대 4명 | §8 |
| RPC 채널 | 0 기본(reliable 이벤트), 1 상태 스냅샷, 2 입력 | 채널 추가 시 이 표 갱신 |
| 2D 충돌 레이어 | 1 = 월드(땅·플랫폼), 2 = 플레이어 | 추가하면 이 표와 Project Settings > Layer Names > 2D Physics를 함께 갱신 |
| 조정값 위치 | `resources/*.tres` (`MovementSettings`, `CombatRules`, `AttackData`) | |
| 폴더 | 씬 `*.tscn`(루트), 스크립트 `scripts/`, 리소스 `resources/`, 테스트 `tests/` | 구조 변경은 사람 결정 |
| 기획 문서 | `GDD/*.md` 규칙, `Design/*.md` UI/UX, `GDD/implementation-status.md` 구현 현황·임시값 | |
| Godot 실행 파일 | Mac `/Applications/Godot.app/Contents/MacOS/Godot` · Windows: 각자 경로 | §12 명령의 `godot`를 이 경로로 바꾼다 |

---

## 1. 최우선 규칙

1. **Godot 4.7 문법과 API만 쓴다.** Godot 3 문법(§4.4 표)을 쓰지 않는다. 확실하지 않은 API는 공식 문서에서 확인한 뒤 쓰고, 있을 것 같다고 추측한 메서드나 프로퍼티는 쓰지 않는다.
2. **기획을 임의로 확정하지 않는다.** GDD의 `??`, `[검토]`, `[미정]` 항목은 임시값으로만 구현한다. 임시값은 Resource에 두고 `GDD/implementation-status.md`에 "임시"로 기록한다.
3. **요청 범위만 바꾼다.** 관련 없는 리팩터링, 포맷 정리, 이름 변경, 파일 이동은 하지 않는다. 필요해 보이면 제안만 한다.
4. **수치를 코드에 박지 않는다.** 속도, 피해, 시간, 크기 같은 조정값은 `@export`나 `resources/*.tres`에 둔다.
5. **정적 타입을 쓴다.** 변수, 인자, 반환값에 모두 타입을 붙인다.
6. **게임 규칙은 호스트만 계산한다.** 클라이언트는 입력만 보내고, 호스트는 `any_peer` RPC로 받은 값을 모두 검증한다.
7. **`.godot/` 폴더는 읽지도, 고치지도, 커밋하지도 않는다.** 엔진이 다시 만드는 캐시다.
8. **파일을 옮기거나 이름을 바꿀 때는 `.uid` 파일과 모든 참조를 함께 처리한다.** 가능하면 사람에게 에디터에서 하도록 요청한다.
9. **바꾼 뒤에는 검증한다.** headless 테스트를 실행하고, 실행할 수 없으면 사람이 확인할 절차를 보고에 적는다.
10. **커밋, 푸시, 브랜치 조작은 사용자가 요청할 때만 한다.**

---

## 2. 작업 절차

### 2.1 시작 전

1. 요청에서 범위와 완료 기준을 확인한다. 불분명하면 짧게 질문한다.
2. 관련 문서를 읽는다: 해당 `GDD/*-handoff.md` → `GDD/implementation-status.md` → UI 작업이면 `Design/*.md`.
3. 관련 코드만 읽는다. 심볼, 시그널, 노드 이름은 `grep`으로 찾아 해당 파일만 연다.
4. `git status`와 현재 브랜치를 확인한다. 커밋되지 않은 사람의 변경을 덮어쓰지 않는다.
5. 변경이 크면(파일 3개 이상, 씬 구조 변경, RPC 프로토콜 변경) 계획을 먼저 짧게 제시하고 승인을 받는다.

### 2.2 구현 중

- 한 번에 기능 하나만 만든다. 단계마다 프로젝트가 실행 가능한 상태를 유지한다.
- 기존 코드의 구조와 이름 규칙을 따른다. 기존 코드가 이 문서와 다르면 새 코드에만 이 문서를 적용하고, 기존 코드 정리는 제안으로 남긴다.
- 테스트할 수 있는 규칙(스톡 차감, 배율 누적, 재스폰 무적 등)은 `tests/`에 검사를 추가한다.

### 2.3 끝난 뒤

1. §12 검증을 실행한다.
2. `GDD/implementation-status.md`를 갱신한다(구현 연결, 임시값, 확인 방법).
3. §15 형식으로 보고한다.

### 2.4 기획 문서 표기 해석

| 표기 | AI의 처리 |
|---|---|
| GDD "확정 규칙", `[확정]`, `[결정]` | 그대로 구현한다. 바꾸려면 사람의 승인이 필요하다 |
| `[제안]` | 기본값으로 구현해도 된다. 구현했으면 보고에 적는다 |
| `[미정]`, `[검토]`, `??` | 확정하지 않는다. 테스트용 임시값을 Resource에 두고 implementation-status.md "임시 구현 정책"에 기록한다 |

---

## 3. Godot 4 핵심 개념

### 3.1 구성 요소

| 개념 | 요점 | 이 프로젝트 |
|---|---|---|
| 노드 | 기능 단위. 부모-자식 트리를 이룬다 | `Fighter`(CharacterBody2D) |
| 씬 `.tscn` | 저장된 노드 트리. 인스턴스로 재사용한다(다른 엔진의 프리팹) | `main.tscn`, `arena.tscn` |
| 리소스 `.tres` | 데이터 객체. 같은 파일을 로드한 곳은 모두 **같은 객체를 공유**한다 | `AttackData`, `MovementSettings` |
| 시그널 | 이벤트 알림. **자식→부모는 시그널, 부모→자식은 메서드 호출** | `Fighter.stock_lost`, `Session.changed` |
| 오토로드 | 전역 싱글톤 노드. 씬이 바뀌어도 유지된다 | `Session` |
| 그룹 | 노드 태그. 여러 노드를 한 번에 찾을 때 쓴다 | |

### 3.2 생명주기와 처리 순서

- `_init()` → 트리 진입 시 `_enter_tree()` → 자식들의 `_ready()`가 먼저, 부모의 `_ready()`가 나중 → 매 프레임 `_process(delta)`, 고정 틱마다 `_physics_process(delta)` → 트리에서 빠질 때 `_exit_tree()`.
- `_ready()`는 노드당 한 번만 호출된다. 트리에서 뺐다가 다시 넣어도 다시 호출되지 않는다.
- `@onready` 변수는 `_ready()` 직전에 채워진다. `_init()`에서는 자식 노드에 접근할 수 없다.
- 이동, 충돌, 게임 규칙 타이머는 `_physics_process`(고정 틱, 기본 60Hz)에서, 연출과 UI는 `_process`에서 처리한다.
- `queue_free()`는 프레임 끝에 삭제한다. 삭제됐을 수 있는 노드는 `is_instance_valid()`로 확인한 뒤 쓴다.
- 씬 전환(`change_scene_to_file()`, `change_scene_to_packed()`)은 지연 처리된다. 같은 함수 안에서 새 씬에 접근하지 않는다.

---

## 4. GDScript 규칙

### 4.1 이름

| 대상 | 규칙 | 예 |
|---|---|---|
| 파일·폴더 | snake_case, ASCII 영문 | `fighter.gd`, `attack_data.gd` |
| `class_name`, 노드 이름 | PascalCase | `Fighter`, `GroundChecker` |
| 함수·변수 | snake_case | `receive_hit()`, `jumps_left` |
| 상수·enum 값 | CONSTANT_CASE | `MAX_PLAYERS`, `LifeState.ACTIVE` |
| 시그널 | 과거형 snake_case | `stock_lost`, `match_started` |
| 비공개 멤버 | `_` 접두사 | `_clear_actions()` |
| 입력 액션 | `p<번호>_<동작>` | `p1_jump`, `p2_attack` |

- 다른 스크립트가 연결하는 시그널에는 `_`를 붙이지 않는다. 4.6부터 `_`로 시작하는 시그널은 자동 완성과 문서에서 숨겨진다.

### 4.2 스크립트 안 순서 (공식 스타일 가이드)

```
@tool, @icon
class_name
extends
## 문서 주석
signal
enum
const
static var
@export var
var
@onready var
_init, _enter_tree, _ready, _process, _physics_process, 그 밖의 내장 가상 함수
공개 메서드
비공개 메서드(_)
내부 클래스
```

### 4.3 작성 규칙

- **타입**: `var speed: float = 260.0`, `func receive_hit(attack: AttackData, direction: Vector2) -> bool:`. `:=`는 오른쪽만 보고 타입이 분명할 때만 쓴다.
- **컬렉션 타입**: `Array[Fighter]`, `Dictionary[int, String]` (타입 지정 Dictionary는 4.4+).
- **상태는 enum으로 표현한다**: `enum Phase { MENU, LOBBY, PLAYING, RESULT }`. 문자열 상태값은 오타를 잡지 못한다. 현재 `Session.phase`는 문자열이다. 바꾸려면 별도 작업으로 한다.
- **노드 참조**: `@onready var checker: RayCast2D = %GroundChecker`(씬 고유 이름) 또는 `@export var target: Node2D`. 깊은 `$A/B/C` 경로나 `get_node("../..")`는 노드 이름이 바뀌면 깨지므로 쓰지 않는다.
- **조정값 노출**: `@export_range(0.0, 2000.0, 10.0, "suffix:px/s") var speed: float = 260.0`. 묶을 때는 `@export_group("Jump")`를 쓴다.
- **시그널**: 연결은 `button.pressed.connect(_on_start_pressed)`, 발신은 `stock_lost.emit(self)`. 문자열 방식의 `connect("x", self, "y")`, `emit_signal("x")`는 쓰지 않는다.
- **await**: `await get_tree().create_timer(1.0).timeout`. await 뒤에는 노드가 삭제됐거나 라운드가 바뀌었을 수 있으므로 `is_inside_tree()`와 라운드 번호를 다시 확인한다. 재스폰, 무적, 경직 같은 **게임 규칙 타이머는 await 대신 `_physics_process`에서 줄어드는 float 변수로 관리한다**(현재 `respawn_left`, `invulnerability_left` 방식).
- **실수 비교**: `==` 대신 `is_equal_approx()`, `is_zero_approx()`.
- **오류 처리**: 예상 가능한 실패는 반환값(`Error`, `bool`)으로 알린다. 일어나면 안 되는 상황은 `assert()`(디버그 빌드 전용)나 `push_error()`로 남긴다.
- **주석**: `##` 문서 주석은 다른 스크립트가 호출하는 함수에 단다. 주석에는 "무엇"보다 "왜"를 쓴다.
- **함수 크기**: 함수 하나는 한 가지 일만 한다. 40~50줄을 넘으면 나눈다.
- **`class_name`**: 다른 곳에서 타입으로 쓰는 스크립트에만 붙인다. 같은 이름을 두 번 쓰지 않는다.

### 4.4 Godot 3 → 4 변환표 (AI가 자주 틀리는 것)

| 쓰지 않는다 (3.x) | 쓴다 (4.x) |
|---|---|
| `export var x = 1` | `@export var x: int = 1` |
| `onready var n = $N` | `@onready var n: Node2D = $N` |
| `tool` | `@tool` |
| `yield(obj, "sig")` | `await obj.sig` |
| `connect("sig", self, "_f")` | `sig.connect(_f)` |
| `emit_signal("sig", a)` | `sig.emit(a)` |
| `var x setget set_x` | `var x: int: set = _set_x` |
| `KinematicBody2D`, `move_and_slide(vel, Vector2.UP)` | `CharacterBody2D`, `velocity = ...` 후 `move_and_slide()` |
| `Position2D` | `Marker2D` |
| `TileMap` | `TileMapLayer` (4.3+) |
| `scene.instance()` | `scene.instantiate()` |
| `update()` (다시 그리기) | `queue_redraw()` |
| `get_tree().change_scene(path)` | `get_tree().change_scene_to_file(path)` |
| `File`, `Directory` | `FileAccess`, `DirAccess` |
| `OS.get_ticks_msec()` | `Time.get_ticks_msec()` |
| `rand_range()`, `stepify()`, `deg2rad()` | `randf_range()`, `snapped()`, `deg_to_rad()` |
| `PoolStringArray` 등 | `PackedStringArray` 등 |
| `array.empty()` | `array.is_empty()` |
| `Engine.editor_hint` | `Engine.is_editor_hint()` |
| `NetworkedMultiplayerENet` | `ENetMultiplayerPeer` |
| `get_tree().network_peer` | `multiplayer.multiplayer_peer` |
| `remote`, `master`, `puppet`, `remotesync` | `@rpc("any_peer" 또는 "authority", "call_local" 또는 "call_remote", ...)` |
| `rpc("f", a)`, `rpc_id(id, "f", a)` | `f.rpc(a)`, `f.rpc_id(id, a)` |
| `rset()` | 없음. 값은 RPC로 보낸다 |
| `get_tree().get_rpc_sender_id()` | `multiplayer.get_remote_sender_id()` |
| `is_network_master()` | `is_multiplayer_authority()` |

### 4.5 4.4 이후 바뀐 점

- **`.uid` 파일 (4.4+)**: 스크립트와 셰이더마다 `파일명.gd.uid`가 생긴다. 원본과 함께 커밋하고 함께 옮긴다. 직접 만들거나 고치지 않는다.
- **타입 지정 Dictionary, `@export_tool_button` (4.4+)**
- **`@abstract` 클래스·메서드, 가변 인자 함수 (4.5+)**
- **노드 고유 ID (4.6+)**: `.tscn`의 노드 줄에 `unique_id=...`가 붙는다. 에디터가 관리하는 값이므로 지어내거나 고치지 않는다.
- **4.7 추가 기능**: `CollisionShape2D.one_way_collision_direction`(단방향 충돌 방향 지정), `Tween.tween_await()` 등.
- 최신 기능은 팀 전원이 §0의 버전을 쓸 때만 쓴다.

---

## 5. 씬·리소스·프로젝트 파일

### 5.1 원칙

- **구조는 씬에, 동작은 스크립트에 둔다.** 에디터에서 보고 고칠 수 있어야 하는 것(콜리전 모양, 레이캐스트, UI 배치, 색)은 `.tscn`에 둔다. `_ready()`에서 노드를 만들어 붙이는 방식은 런타임에 개수가 정해지는 것(참가 인원만큼의 Fighter 등)에만 쓴다.
  - 현재 `fighter.gd`는 CollisionShape2D와 GroundChecker를 코드로 만든다. 새로 만드는 노드는 씬에 두고, 기존 코드의 전환은 별도 작업으로 제안한다.
- 재사용 단위는 하위 씬으로 나눈다(예: `fighter.tscn`, `player_card.tscn`). 큰 씬 하나를 여러 사람이 동시에 고치면 병합 충돌이 난다.
- 스크립트가 의존하는 자식 노드는 `%고유이름`이나 `@export`로 드러낸다.

### 5.2 `.tscn`, `.tres`를 텍스트로 고칠 때

- 에디터 작업이 더 안전하다. AI가 텍스트로 고쳐도 되는 범위는 프로퍼티 값 변경, 단순한 노드 추가, 스크립트·리소스 연결까지다.
- 지킬 것:
  - `[ext_resource]`와 `[sub_resource]`의 `id`는 파일 안에서 고유해야 하고, `ExtResource("id")`, `SubResource("id")` 참조와 일치해야 한다.
  - `uid="uid://..."` 값과 `unique_id` 값을 지어내지 않는다. 모르면 `uid`는 빼고 `path`만 쓰고, 새 노드에는 `unique_id`를 생략한다. 에디터가 다음 저장 때 채운다.
  - 노드의 `parent`는 루트 기준 경로다(`"."`, `"Arena/Platforms"`).
  - 섹션 순서: 헤더 → `ext_resource` → `sub_resource` → `node` → `connection`.
- 텍스트로 고친 씬은 §12의 `--import`로 로드 오류를 확인하고, 사람에게 "에디터에서 한 번 열어 저장한 뒤 커밋"을 요청한다.
- 애니메이션 트랙, 타일맵 데이터, 테마처럼 복잡한 리소스는 텍스트로 크게 고치지 않는다. 에디터 작업 지시로 대신한다.

### 5.3 `project.godot`

- Project Settings 창으로 바꾸는 것이 원칙이다. AI가 직접 고칠 때는 해당 섹션의 기존 형식을 그대로 따르고, 바꾼 키를 보고한다.
- 입력 맵(`[input]`)은 직렬화 형식이 복잡하다. 새 액션은 사람에게 에디터에서 추가해 달라고 요청하거나, 기존 항목을 복제해 키 값만 바꾼다.
- 바꾸지 않는 것: `config/features`(엔진 버전), 렌더러와 드라이버, 물리 엔진.

### 5.4 파일과 경로

- 파일 이름은 ASCII snake_case로 짓는다. 한글, 공백, 대문자가 들어간 파일 이름은 Windows·Mac·내보낸 빌드 사이에서 문제를 만든다. 내보낸 빌드의 `res://` 경로는 대소문자를 구분하므로, 코드의 경로 문자열은 실제 파일 이름과 대소문자까지 일치시킨다.
- 이미지 등 에셋을 추가하면 `.import` 파일도 커밋한다. `.import` 내용은 손으로 고치지 않는다(설정은 에디터 Import 탭에서).
- 파일 이동과 이름 변경은 에디터 FileSystem 독에서 하면 참조가 자동으로 갱신된다. AI가 해야 한다면:
  1. `.uid` 파일을 함께 옮긴다.
  2. `grep -rn "옛경로" --include=*.gd --include=*.tscn --include=*.tres --include=project.godot .`로 참조를 모두 찾아 고친다.
  3. §12의 `--import`로 로드 오류가 없는지 확인한다.

---

## 6. 2D 물리와 충돌

- 플레이어는 `CharacterBody2D`에 `velocity`를 설정하고 `move_and_slide()`를 호출한다. `is_on_floor()`는 `move_and_slide()` 다음에 유효하다.
- 움직이는 모든 것은 `_physics_process(delta)`에서 처리하고, 속도와 가속에는 `delta`를 곱한다.
- 용도별 노드:

| 용도 | 노드 |
|---|---|
| 막히는 지형 | `StaticBody2D`. 아래에서 올라갈 수 있는 플랫폼은 `CollisionShape2D.one_way_collision` |
| 땅 감지 | `RayCast2D` 또는 `ShapeCast2D` (GroundChecker) |
| 공격 판정, 영역 감지 | `Area2D`, 또는 즉시 질의 `PhysicsDirectSpaceState2D.intersect_shape()` |

- **레이어와 마스크는 비트마스크다.** 레이어 n의 값은 `1 << (n - 1)`이다. 레이어 3은 값 3이 아니라 4다. 헷갈리지 않도록 `set_collision_layer_value(3, true)`나 이름 붙인 상수를 쓰고, 번호는 §0 표를 따른다.
- 물리 콜백(`body_entered` 등)이나 물리 처리 도중에 충돌 모양, `disabled`, `monitoring`을 바꾸거나 물리 노드를 추가·삭제할 때는 `set_deferred()`, `call_deferred()`를 쓴다. 그러지 않으면 "Can't change this state while flushing queries" 오류가 난다.
- 같은 프레임에 결과가 필요한 레이캐스트는 `force_raycast_update()`를 먼저 호출한다.
- 순간이동(재스폰)할 때는 `velocity`와 진행 중이던 상태(경직, 예약 공격, 통과 중 플랫폼)를 함께 초기화한다.
- 빠르게 날아가는 캐릭터가 얇은 벽을 뚫으면 충돌체를 두껍게 하거나 이동을 나눠 검사한다.

---

## 7. 입력

- 새 입력은 **Input Map 액션**으로 만든다. 키 코드(`KEY_A`)를 코드에 직접 쓰지 않는다.
  - 현재 `fighter.gd`와 `arena.gd`는 `KEY_*`와 `Input.is_physical_key_pressed()`를 직접 쓴다. 새 입력 코드는 액션을 쓰고, 기존 코드 전환은 별도 작업으로 제안한다.
- 액션 이름은 `p1_left`, `p1_right`, `p1_jump`, `p1_down`, `p1_attack`처럼 짓는다(로컬 2인은 `p2_*`). 메뉴 조작은 기본 `ui_*` 액션을 쓴다.
- 비교할 때는 StringName 리터럴을 쓴다: `Input.is_action_just_pressed(&"p1_jump")`.
- "누른 순간"(점프, 공격)과 "누르고 있음"(이동)을 구분한다. 네트워크에서는 호스트가 이전 입력 마스크와 비교해 "누른 순간"을 계산한다.
- 네트워크 입력 비트마스크의 비트 정의는 enum 한 곳에만 둔다.
- 이벤트형 입력은 `_unhandled_input()`에서 받는다. UI가 먼저 처리한 입력이 게임에 새지 않게 하기 위해서다.

---

## 8. 멀티플레이어 (ENet, 호스트 권한형)

### 8.1 구조

- 호스트(peer id `1`)만 이동, 충돌, 공격, 스톡, 타이머, 승패, 무작위 값(재스폰 위치)을 계산한다.
- 클라이언트는 자기 입력만 보내고, 받은 상태로 화면만 그린다.
- 연결 생성과 해제(`ENetMultiplayerPeer` 생성, `multiplayer.multiplayer_peer` 교체)는 `Session` 한 곳에서만 한다. 나중에 Steam 같은 다른 전송 계층으로 바꿀 때 이 부분만 교체하면 되도록 하기 위해서다.
- `MultiplayerSpawner`와 `MultiplayerSynchronizer`는 현재 쓰지 않는다. 도입은 구조 변경이므로 사람이 결정한다.

### 8.2 RPC 규칙

`@rpc(모드, 동기화, 전송 방식, 채널)` 기본 설정 (현재 코드와 같다)

| 용도 | 설정 |
|---|---|
| 클라이언트 → 호스트 입력 | `@rpc("any_peer", "call_remote", "reliable", 2)` |
| 호스트 → 전원 상태 스냅샷(20Hz) | `@rpc("authority", "call_remote", "unreliable_ordered", 1)` |
| 호스트 → 전원 이벤트(시작, 결과, 로비 복귀) | `@rpc("authority", "call_local", "reliable")` |

- **`any_peer` RPC는 첫 줄에서 검증한다.** ① `multiplayer.is_server()` ② `multiplayer.get_remote_sender_id()`로 보낸 사람 확인 ③ 인자의 타입과 범위 ④ 현재 단계와 라운드 번호. 클라이언트가 보낸 플레이어 id, 좌표, 스톡 값은 믿지 않는다.
- RPC는 모든 피어에서 **같은 노드 경로의 같은 스크립트**에 있어야 한다. 노드 이름을 동적으로 정하면 피어끼리 같은 규칙으로 정한다(예: `"Fighter_%d" % peer_id`).
- `@rpc` 함수의 추가, 삭제, 설정 변경은 모든 피어 코드에 똑같이 들어가야 한다. 다른 빌드끼리는 접속하지 않는다고 가정한다.
- RPC 인자는 기본형, `Vector2`, `Array`, `Dictionary`, Packed 배열만 쓴다. 노드나 Object를 보내지 않고, `allow_object_decoding`을 켜지 않는다.
- 매 프레임 `reliable` 전송을 하지 않는다. 상태는 스냅샷 하나로 묶어 보낸다.
- 오래된 패킷을 무시하도록 라운드 번호(`generation`)와 프레임 번호를 함께 보낸다(현재 방식 유지).

### 8.3 연결 상태

- `peer_connected`, `peer_disconnected`, `connected_to_server`, `connection_failed`, `server_disconnected` 다섯 시그널을 모두 처리한다.
- 접속 시도에는 제한 시간(현재 8초)을 둔다.
- 호스트가 끊기면 메뉴로 돌아가 이유를 표시한다. 클라이언트가 끊기면 그 판에서 탈락 처리한다. 경기 중 새 접속은 거부한다(`Design/match-flow-scene-ux.md` 기준).

### 8.4 테스트

- 한 컴퓨터: 에디터 Debug > Customize Run Instances에서 인스턴스 2~4개를 띄우거나, §12의 headless 네트워크 테스트를 쓴다.
- 다른 컴퓨터 간 접속은 사람이 확인한다(방화벽에서 UDP 포트 허용, 같은 빌드 사용).

---

## 9. UI

- `Control` 노드와 컨테이너(`VBoxContainer`, `HBoxContainer`, `MarginContainer`, `GridContainer`)로 배치한다. 절대 좌표 배치는 해상도가 바뀌면 깨진다.
- 앵커 프리셋을 쓴다(전체 화면은 Full Rect).
- 색, 폰트, 크기는 `Theme` 리소스 하나에 모은다. Design 문서의 색(배경 `#101927`, 강조 `#4f7cff`, 오류 `#ff5a5a`)은 한 곳에만 정의한다.
- 화면 문구는 한 곳(상수 모음)에 모으고, Design 문서의 "문구 초안"과 같게 쓴다.
- UI는 게임 상태를 직접 바꾸지 않는다. 버튼은 `Session`이나 게임 로직의 함수를 부르고, UI는 시그널(`Session.changed` 등)을 받아 화면을 갱신한다.
- 네트워크 응답을 기다리는 동작에는 "진행 중" 상태(버튼 비활성과 안내 문구)를 둬서 같은 요청이 두 번 가지 않게 한다.
- 키보드·게임패드로 포커스를 옮길 수 있게 한다. 화면이 열리면 첫 버튼에 `grab_focus()`를 호출한다.
- 오버레이는 `mouse_filter = STOP`, 장식 요소는 `IGNORE`로 둬서 클릭이 뒤로 새지 않게 한다.

---

## 10. 효율성

### 10.1 실행 성능

- 먼저 측정한다(디버거의 Profiler, Monitors). 추측으로 최적화하지 않는다.
- `_process`와 `_physics_process` 안에서 피할 것:
  - `get_node()`, `find_child()`, `get_nodes_in_group()` 반복 호출 → `@onready`나 변수에 저장해 둔다
  - 매 프레임 노드나 Resource 생성
  - `load()` → `preload()`나 미리 로드한 값을 쓴다
  - 문자열 조합과 포맷팅
- 할 일이 없는 노드는 `set_process(false)`, `set_physics_process(false)`로 멈춘다.
- 매 프레임 상태를 확인하는 대신 시그널을 쓴다.
- 이 규모의 2D 게임에는 오브젝트 풀링이 대부분 필요 없다. 프로파일러에서 문제가 보일 때만 도입한다.
- 네트워크 스냅샷에는 화면에 필요한 값만 담는다.

### 10.2 AI 작업 효율

- 필요한 파일만 읽는다. `grep -rn "심볼" --include=*.gd --include=*.tscn .`으로 먼저 위치를 찾는다.
- `.godot/`, `*.import`, `*.uid`, 이미지·오디오 같은 바이너리는 읽지 않는다.
- 같은 값이나 로직을 여러 파일에 복사하지 않는다. 값은 Resource에, 공통 로직은 함수 하나에 둔다.
- 큰 기능은 "데이터(Resource) → 로직 → 테스트 → UI" 순서로 나눠 진행하고, 단계마다 검증한다.

---

## 11. 안정성

- **삭제된 노드**: 다른 노드 참조는 쓰기 전에 `is_instance_valid()`로 확인한다.
- **시그널 중복 연결**: `if not sig.is_connected(f): sig.connect(f)`. 한 번만 받을 때는 `CONNECT_ONE_SHOT`.
- **공유 Resource**: `preload()`한 `.tres`는 모든 사용처가 같은 객체를 쓴다. 런타임에 값을 바꾸면 다른 플레이어에게도 적용된다. `AttackData` 같은 조정값 리소스는 읽기 전용으로 쓰고, 개별 상태는 노드 변수에 둔다. 꼭 바꿔야 하면 `duplicate()`한 사본을 쓴다.
- **상태 전이는 전용 함수 하나에서**: 장외, 재스폰, 탈락처럼 여러 값을 함께 바꾸는 일은 전용 함수(현재 `ring_out()`, `respawn()`, `reset_round()`)에서만 하고, 중복 처리를 막는 가드를 둔다(이미 장외 상태면 무시).
- **외부 힘의 입구는 하나**: 피해와 넉백은 `receive_hit()`, `apply_external_impulse()`로만 받는다.
- **무작위 값**: `RandomNumberGenerator` 인스턴스를 호스트에서만 사용한다. 테스트에서는 seed를 고정한다.
- **실패를 숨기지 않는다**: 예상 밖 상황에서 조용히 `return`하지 말고 `push_warning()`이나 `push_error()`로 남긴다.
- **경고를 늘리지 않는다**: 새 GDScript 경고를 만들지 않는다. 권장 설정은 Project Settings > Debug > GDScript > `untyped_declaration` = Warn.
- **엔진 업그레이드는 사람이 한다**: 별도 브랜치와 별도 커밋으로 진행하고, 4.6 이후는 Project > Tools > Upgrade Project Files로 씬을 다시 저장한다.

---

## 12. 테스트와 검증

### 12.1 명령

```bash
# 0) 처음 클론했을 때, 또는 에셋·class_name·씬을 바꾼 뒤: 임포트와 클래스 캐시 생성, 로드 오류 확인
godot --headless --path . --import

# 1) 규칙·플레이 테스트
godot --headless --path . --script res://tests/combat_test.gd
godot --headless --path . --script res://tests/gameplay_test.gd

# 2) 네트워크 테스트 (터미널 두 개, 호스트를 먼저 실행)
godot --headless --path . --script res://tests/network_peer.gd -- host
godot --headless --path . --script res://tests/network_peer.gd -- client

# 스크립트 문법만 빠르게 확인
godot --headless --path . --check-only --script res://scripts/fighter.gd
```

- `godot`는 §0의 실행 파일 경로로 바꾼다. Windows에서는 `tests/run_checks.ps1 -GodotPath '<경로>'`로 전체를 실행할 수 있다.
- 출력에 `SCRIPT ERROR`, `ERROR`, `Parse Error`가 있으면 종료 코드가 0이어도 실패로 본다.

### 12.2 테스트 작성 규칙

- 형식: `extends SceneTree`, `_initialize()`에서 `call_deferred("run")`, 실패 수를 세서 마지막에 `quit(1 if failures > 0 else 0)` (현재 `tests/*.gd` 방식).
- GDD의 "확인 기준" 한 줄에 `check()` 하나를 대응시키고, 설명 문구로 어느 기준인지 알 수 있게 한다.
- 테스트용 값은 테스트 안에서 `AttackData.new()`처럼 새로 만든다. `resources/*.tres`를 테스트를 위해 고치지 않는다.
- 실제 물리 결과가 필요하면 물리 프레임을 돌린다(`await physics_frame`).

### 12.3 사람이 확인할 것 (AI는 보고에 체크리스트로 적는다)

- 에디터에서 바뀐 씬이 오류 없이 열리는가
- 실제 조작감(이동·점프·넉백 수치)
- UI 배치와 문구가 Design 문서와 맞는가
- 다른 컴퓨터 간 접속

---

## 13. Git과 협업

- 커밋하지 않는 것: `.godot/`, 내보내기 결과물(`*.exe`, `*.pck` 등), `export_credentials.cfg`, `.DS_Store`.
- 커밋하는 것: `.gd`, `.gd.uid`, `.tscn`, `.tres`, `.import`, 에셋 원본, `project.godot`, 문서.
- 커밋 하나에는 의도 하나만 담는다. 메시지 예: `공격: 아래 공격 히트박스 추가`, `재스폰: 장외 중복 차감 방지`.
- 같은 `.tscn`을 두 브랜치에서 동시에 고치지 않는다. 충돌이 나면 텍스트로 병합하기보다 한쪽을 기준으로 에디터에서 다시 작업하는 편이 안전하다.
- 새 브랜치 이름은 영문 소문자와 하이픈으로 짓는다(`feature/respawn-timer`, `fix/double-ring-out`).
- AI는 커밋, 푸시, 머지, 브랜치 삭제를 요청받았을 때만 한다. `git reset --hard`, `git push --force`는 하지 않는다.

---

## 14. 금지 사항 요약

- Godot 3 문법, 추측한 API
- GDD `[미정]`·`??` 항목을 확정값처럼 구현하기
- 요청 밖의 리팩터링, 이름 변경, 파일 이동
- 코드에 박은 조정값, 타입 없는 변수
- 클라이언트에서 게임 규칙 계산, 검증 없는 `any_peer` RPC, RPC로 Object 전송
- `.godot/` 수정·커밋, `.uid`·`uid://`·`unique_id` 값 지어내기
- 물리 콜백 안에서 충돌 상태를 즉시 변경하기(`set_deferred` 없이)
- `preload()`한 공유 Resource 값을 런타임에 바꾸기
- 엔진 버전, 렌더러, 물리 엔진 설정 변경
- 요청 없는 커밋, 푸시, 강제 푸시

---

## 15. 완료 체크리스트와 보고 형식

### 15.1 체크리스트

- [ ] Godot 4.7 문법만 썼고 새 경고가 없다
- [ ] 변수, 인자, 반환값에 타입이 있다
- [ ] 조정값은 Resource나 `@export`에 있다
- [ ] 미정 항목은 임시값으로 두고 implementation-status.md에 기록했다
- [ ] 네트워크 코드는 호스트 권한이고 `any_peer` RPC를 검증한다
- [ ] 파일을 옮겼다면 `.uid`와 참조를 함께 처리했다
- [ ] §12 테스트를 실행했다(또는 실행하지 못한 이유를 적었다)

### 15.2 보고 형식

```markdown
## 요약
(무엇을 바꿨는지 한두 문장)

## 바꾼 파일
- scripts/xxx.gd: ...

## 검증
- 실행한 명령과 결과 / 실행하지 못한 것과 이유

## 임시값·가정
- (GDD 미정 항목에 넣은 임시값, 기획 문서의 [제안]을 채택한 것)

## 사람이 확인할 것
- [ ] 에디터에서 ○○ 씬 열고 저장
- [ ] ...

## 남은 문제·제안
```

---

## 16. 사람용: AI에게 일을 맡기는 법

- **한 번에 기능 하나**를 맡긴다. 기능마다 새 대화를 시작하면 맥락이 섞이지 않는다.
- **근거 문서와 완료 기준**을 함께 준다. GDD의 "확인 기준"을 그대로 완료 기준으로 써도 된다.
- **오류는 텍스트로** 준다. Godot 출력 패널이나 디버거의 내용을 그대로 붙여넣는 것이 스크린샷보다 정확하다.
- AI가 텍스트로 만든 씬은 **에디터에서 한 번 열어 저장한 뒤** 커밋한다.

기능 구현 요청

```
AI_GODOT_GUIDE.md를 따라 작업해 줘.
작업: 재스폰 3초 대기 구현
근거: GDD/basicRule.md "재스폰", Design/match-flow-scene-ux.md S3
범위: scripts/arena.gd, resources/combat_rules.tres
완료 기준: 장외 후 3초 뒤 재스폰, combat_test 통과
미정 항목은 확정하지 말고 임시값으로 표시해 줘.
```

버그 수정 요청

```
AI_GODOT_GUIDE.md를 따라 버그를 고쳐 줘.
증상:
재현 방법:
기대 동작:
오류 메시지: (Godot 출력 그대로)
```

검토 요청

```
AI_GODOT_GUIDE.md §14, §15 기준으로 이 브랜치의 변경을 검토해 줘.
고치지 말고 문제만 파일·줄 단위로 알려 줘.
```

---

## 참고 문서

- [Godot 4.7 릴리스 노트](https://godotengine.org/releases/4.7/)
- [버전별 이전 가이드(4.x)](https://docs.godotengine.org/en/stable/tutorials/migrating/index.html)
- [Godot 3 → 4 이전 가이드](https://docs.godotengine.org/en/stable/tutorials/migrating/upgrading_to_godot_4.html)
- [GDScript 스타일 가이드](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html)
- [GDScript 정적 타입](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/static_typing.html)
- [고수준 멀티플레이](https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html)
- [커맨드 라인 사용법](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html)
- [프로젝트 구성](https://docs.godotengine.org/en/stable/tutorials/best_practices/project_organization.html)

> 문서 링크의 `stable`이 4.7이 아니면 페이지 왼쪽 아래에서 버전을 4.7로 바꿔 본다.

---

## 변경 이력

| 날짜 | 버전 | 내용 |
|---|---|---|
| 2026-10-10 | v1 | 최초 작성. Godot 4.7.2, `origin/main` 구조 기준 |
