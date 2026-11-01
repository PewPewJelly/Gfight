# 00 System Context (전역 규칙)

> 모든 화면 명세서(SYS-01 이후)와 코딩 AI 프롬프트 앞에 항상 붙이는 문서다. 짧게 유지한다.
> 세부 규칙의 원문은 저장소 루트 `AI_GODOT_GUIDE.md`이고, 두 문서가 다르면 그 파일을 따른다.
> v0.3 (2026-10-27). 결정 3건 반영 + 아이콘·그림을 SVG 파일로 전환. 결정 필요 사항 없음

## 0. 이 문서의 위치

| 문서 | 역할 |
|---|---|
| `00_System_Context.md` (이 문서) | 기술 스택, 코딩 규칙, 전역 데이터, 아키텍처. 모든 프롬프트에 포함 |
| `NN-<screen>-spec.md` | 화면 하나의 상태, 입출력, 노드 트리, 이벤트, 예외. 해당 화면 작업 때만 포함 |
| `GDD/*.md` | 게임 규칙(이동, 공격, 스톡 등). 규칙 작업 때만 포함 |
| `GDD/implementation-status.md` | 실제 구현 현황과 임시값. 코드와 문서가 다르면 여기를 먼저 본다 |

화면 명세서는 이 문서의 이름(타입, enum, 함수)을 그대로 쓰고, 새로 정의하지 않는다. 바꿔야 하면 이 문서를 먼저 고친다.

---

## 1. 기술 스택

| 항목 | 값 | 바꿀 수 있는 사람 |
|---|---|---|
| 엔진 | Godot 4.7.x (팀 검증 4.7.2) | 사람 |
| 언어 | GDScript, 정적 타입 필수. C#/GDExtension 사용 안 함 | 사람 |
| 렌더러 | Forward+ | 변경 금지 |
| 화면 | 1280 × 720, `stretch/mode = canvas_items`, `aspect = expand`, 시작 시 전체화면 (F11 / Alt+Enter 전환) | 사람 |
| 메인 씬 | `res://main.tscn` | 사람 |
| 오토로드 | `Session` = `res://scripts/session.gd` 하나만. 새 오토로드는 사람 승인 | 사람 |
| 네트워크 | ENet, 호스트 권한형, 최대 4인, 포트 27840 (테스트 27849), 접속 제한 8초 | 사람 |
| RPC 채널 | 0 = reliable 이벤트, 1 = 상태 스냅샷, 2 = 입력 | 사람 |
| 충돌 레이어 | 1 = 월드(땅·플랫폼), 2 = 플레이어 | 사람 |
| 조정값 | `resources/*.tres` (`MovementSettings`, `CombatRules`, `AttackData`) | 기획 |
| 폴더 | 기존 씬 `*.tscn` 루트(`main.tscn`, `arena.tscn`), 화면 씬 `scenes/ui/`, 화면 스크립트 `scripts/ui/`, 데이터 클래스 `scripts/data/`, 그 외 스크립트 `scripts/`, 리소스 `resources/`, 그림 파일 `assets/`(SVG, 하위 `icons/`·`start_game/`·`characters/`·`maps/`), 테스트 `tests/` | 사람 |
| UI 원칙 | 기본 도형과 글자만. 아이콘·캐릭터·맵 그림은 `assets/`의 SVG 파일을 `TextureRect` 또는 `draw_texture_rect()`로 표시한다. 단색 아이콘은 흰색으로 그려져 있으므로 색은 `self_modulate`(또는 draw 색 인자)로 입힌다. 상자·테두리·그림자·줄무늬 같은 UI 도형은 계속 `_draw()`/StyleBox로 그린다. 그림 목록과 출처는 `assets/README.md` | 기획 |
| 입력 장치 | 게임 조작은 키보드. 메뉴 화면은 마우스 전용(키보드·패드 포커스 이동 없음), 단축키는 Enter/Esc만 | 기획 |

---

## 2. 코딩 규칙

### 2.1 필수

1. Godot 4.7 문법과 API만 쓴다. Godot 3 문법(`export var`, `yield`, `connect("s", self, "f")`, `instance()` 등) 금지. 모르는 API는 추측하지 않고 공식 문서로 확인한다.
2. 변수, 인자, 반환값에 모두 타입을 붙인다. `var x := 값`(추론)은 오른쪽 타입이 분명할 때만.
3. 상태는 `enum`으로 표현한다. 문자열 상태 금지(기존 `Session.phase` 문자열은 3.5 참고).
4. 속도, 시간, 크기, 피해 같은 수치를 코드에 직접 쓰지 않는다. 게임 규칙 값은 `.tres`, 화면 연출 값은 해당 스크립트의 `@export`/`const`.
5. 화면에 보이는 문구와 색은 `UiStyle`(`scripts/ui_style.gd`) 한 곳에만 둔다. `AI_GODOT_GUIDE.md`의 Theme 리소스 전환은 화면 이전이 모두 끝난 뒤 따로 검토한다.
6. 기획 문서의 `[미정]`, `[검토]`, `??`는 확정하지 않는다. 임시값으로 구현하고 `GDD/implementation-status.md`에 "임시"로 적는다. `[제안]`은 기본값으로 구현하고 보고에 적는다.
7. 요청 범위만 바꾼다. 관련 없는 이름 변경, 정리, 파일 이동은 제안만 한다.
8. `.godot/` 폴더, `.uid` 파일, `uid://`, `unique_id`는 만들거나 고치지 않는다.
9. 커밋·푸시·브랜치 조작은 사람이 요청할 때만. `main`에 직접 커밋하지 않는다.

### 2.2 이름

| 대상 | 규칙 | 예 |
|---|---|---|
| 파일, 폴더 | snake_case ASCII | `start_game_screen.gd` |
| `class_name`, enum 타입, 노드 이름 | PascalCase | `StartGameScreen`, `ScreenState`, `%BackButton` |
| 함수, 변수 | snake_case | `host_game()`, `room_address` |
| 비공개 함수·변수 | `_` 접두사 | `_apply_state()` |
| 상수, enum 값 | CONSTANT_CASE | `MAX_PLAYERS`, `JOIN_CONNECTING` |
| 시그널 | 과거형 snake_case. 다른 스크립트가 연결하면 `_` 없음 | `match_finished`, `exit_requested` |
| 시그널 처리 함수 | `_on_<노드>_<시그널>` | `_on_back_button_pressed` |
| 입력 액션 | `p<번호>_<동작>` | `p1_jump` |

`class_name`은 다른 스크립트가 타입으로 쓰는 것에만 붙인다.

### 2.3 스크립트 내부 순서

`class_name` → `extends` → 문서 주석(`##`) → `signal` → `enum` → `const` → `@export` → `var` → `@onready` → 내장 가상 함수(`_ready`, `_process` …) → 공개 함수 → 비공개 함수.

### 2.4 자주 쓰는 패턴

- 노드 참조: `@onready var back_button: Button = %BackButton`. 깊은 `$A/B/C` 경로 금지.
- 시그널: `sig.connect(f)`, `sig.emit(x)`. 중복 연결은 `is_connected(f)`로 막는다.
- 게임 규칙 타이머(재등장, 무적, 경직)는 `await` 대신 `_physics_process`에서 줄어드는 `float`. `await` 뒤에는 `is_inside_tree()`와 라운드 번호(`Session.generation`)를 다시 확인한다.
- 이동·충돌·규칙은 `_physics_process`, 연출·UI는 `_process`.
- 예상 가능한 실패는 `Error`/`bool` 반환값으로, 예상 밖 상황은 `push_error()`/`push_warning()`. 조용히 `return`하지 않는다.
- 실수 비교 `is_equal_approx()`, 삭제됐을 수 있는 노드 `is_instance_valid()`.

---

## 3. 전역 데이터 스키마

화면 사이, 그리고 네트워크로 주고받는 핵심 데이터다. 클래스는 `extends RefCounted`(저장하지 않는 값 묶음). **네트워크(RPC)로는 객체를 보내지 않고 `to_dict()`로 바꾼 `Dictionary`만 보낸다.** 받은 쪽은 `from_dict()`에서 키와 타입을 검사한다.

> 현재 코드(`session.gd`)는 같은 정보를 `roster: Dictionary`, `ready_states: Dictionary`, `phase: String` 등 흩어진 변수로 들고 있다. 아래는 목표 형태다. **화면을 새 구조로 옮기기 전에 별도 작업 1건("데이터 구조 정리")으로 한 번에 옮긴다.** 그 작업이 끝나기 전에는 각 표의 "현재 위치" 열을 읽는다. 클래스 파일은 `scripts/data/<snake_case>.gd`(예: `player_data.gd`, `room_state.gd`, `match_result.gd`).

### 3.1 공용 enum — `ScreenTypes` (`scripts/data/screen_types.gd`)

```gdscript
class_name ScreenTypes
extends RefCounted

enum ScreenId { MAIN_MENU, START_GAME, LOBBY, MATCH, RESULT, GUIDEBOOK, SETTINGS }
enum RoomMode { NONE, ONLINE, TRAINING }
enum Role { NONE, HOST, CLIENT }
```

| `ScreenId` | 명세서 | 비고 |
|---|---|---|
| MAIN_MENU | SYS-00 메인 화면 (미작성) | [게임하기][가이드북][설정] |
| START_GAME | SYS-01 게임하기 | 작성됨 |
| LOBBY | 대기방 (미작성) | 온라인/훈련 공용 |
| MATCH | 경기 + HUD (미작성) | 훈련 모드는 치트 기능 추가 |
| RESULT | 결과 (미작성) | |
| GUIDEBOOK, SETTINGS | 미작성 | |

### 3.2 `PlayerData` — 방 안의 플레이어 1명

| 필드 | 타입 | 범위 / 규칙 | 현재 위치 |
|---|---|---|---|
| `peer_id` | `int` | 호스트 1, 그 외 ENet이 준 id. 훈련 모드 1 | `Session.roster`의 키 |
| `slot` | `int` | 1~4. peer_id 오름차순 순서 | `Session.slot_of(id)` |
| `display_name` | `String` | 앞뒤 공백 제거, 줄바꿈 제거, 최대 20자, 빈 값이면 `"Player"` | `Session.roster[id]`, `Session.clean_name()` |
| `is_ready` | `bool` | 호스트는 항상 `true`로 본다(시작 버튼이 곧 준비) | `Session.ready_states[id]` |

- 슬롯 색은 저장하지 않고 `UiStyle.slot_color(slot)`로 구한다(빨강·파랑·초록·노랑).
- 이름 입력 화면은 아직 없다. 현재 모든 플레이어 이름은 `"Player"`.

### 3.3 `RoomState` — 지금 들어가 있는 방

| 필드 | 타입 | 범위 / 규칙 | 현재 위치 |
|---|---|---|---|
| `mode` | `ScreenTypes.RoomMode` | ONLINE / TRAINING | (없음. SYS-01에서 `Session.training_mode` 추가) |
| `phase` | `Session.Phase` | 3.5 참고 | `Session.phase: String` |
| `address` | `String` | 온라인 `"IP:포트"`, 훈련 `""` | `Session.room_address` |
| `players` | `Array[PlayerData]` | 1~4명, slot 순 | `Session.roster` + `ready_states` |
| `max_players` | `int` | 4 | `Session.MAX_PLAYERS` |
| `stocks` | `int` | 3 | `CombatRules.INITIAL_STOCKS` |
| `generation` | `int` | 경기를 시작할 때마다 1 증가. 오래된 RPC를 버리는 데 씀 | `Session.generation` |
| `notice` | `String` | 대기방 알림 한 줄("P2 님이 들어왔습니다.") | `Session.message` |

- 이 정보는 호스트만 바꾼다. 클라이언트는 호스트가 보낸 값으로 덮어쓰기만 한다.

### 3.4 `MatchResult` — 경기 1판의 결과

| 필드 | 타입 | 규칙 | 현재 위치 |
|---|---|---|---|
| `generation` | `int` | 이 결과가 속한 경기 번호 | `Session.generation` |
| `winner_id` | `int` | 우승자 peer_id, 무승부 0 | `FightArena.winner_id` |
| `entries` | `Array[MatchResultEntry]` | 참가자 전원, slot 순 | `FightArena.fighters` |

`MatchResultEntry`

| 필드 | 타입 | 규칙 | 현재 위치 |
|---|---|---|---|
| `peer_id` | `int` | | `Fighter.player_id` |
| `slot` | `int` | 1~4 | `Fighter.player_slot` |
| `rank` | `int` | 1부터. 늦게 탈락할수록 높은 순위, 같은 프레임 탈락은 공동 순위 | `FightArena.compute_ranks()` |
| `kills` | `int` | ≥ 0 | `Fighter.kills` |
| `dealt_percent` | `float` | 남에게 준 배율 합계, ≥ 0 | `Fighter.dealt_percent` |
| `present` | `bool` | 결과 화면 시점에 방에 남아 있는지 | `Session.roster.has(id)` |

- 결과 화면은 킬과 준 배율만 보여 준다(`Design/ui-ux-scenes-v2.pdf`).
- 훈련 모드 결과 처리는 훈련장 문서에서 정한다.

### 3.5 `Session.Phase` — 앱 전체의 네트워크 단계

```gdscript
enum Phase { MENU, CONNECTING, LOBBY, CLOSING, PLAYING, RESULT }
```

| enum | 현재 문자열 | 뜻 |
|---|---|---|
| MENU | `"menu"` | 방에 들어가 있지 않음 (메인, 게임하기, 가이드북, 설정 화면) |
| CONNECTING | `"connecting"` | 방 참여 접속 시도 중 (최대 8초) |
| LOBBY | `"lobby"` | 대기방 |
| CLOSING | `"closing"` | 호스트가 방을 닫는 중 (0.2초) |
| PLAYING | `"playing"` | 경기 중 |
| RESULT | `"result"` | 결과 화면 |

- 문자열 → enum 교체는 "데이터 구조 정리" 작업에 포함한다(`session.gd`, `main.gd`, 테스트 함께 변경). 그 작업 전까지는 문자열을 비교하되 위 표와 정확히 같아야 한다.

### 3.6 화면 진입·이탈 데이터 규칙

- 화면마다 `<Screen>EnterData`, `<Screen>ExitResult` 두 클래스(`extends RefCounted`)를 둔다. 필드는 각 화면 명세서 섹션 2에서 정한다.
- `EnterData`가 `null`이면 모든 필드를 기본값으로 본다.
- 화면끼리 주고받는 것은 이 두 객체뿐이다. 방·플레이어 정보는 `Session`에서 직접 읽는다(복사해 들고 다니지 않음).

---

## 4. 아키텍처

### 4.1 한 줄 요약

**UI는 입력을 받아 `Session` 함수를 부르거나 시그널을 내보내기만 한다. 방·연결·경기 상태는 `Session`이, 경기 규칙은 호스트의 `FightArena`가 바꾼다. 화면 전환은 `ScreenRouter`가 한다.**

### 4.2 구성 요소

```
main.tscn
└─ ScreenRouter (Control)               화면 1개만 자식으로 두고 교체
   └─ <현재 화면>.tscn                   예: StartGameScreen
        └ exit_requested(result) ──▶ ScreenRouter.go_to(...)

Session (autoload)                       연결, 방, 준비, 경기 시작·종료, 결과 확인
  └─ Arena (FightArena, 경기 중에만)      이동·충돌·공격·스톡·승패 (호스트만 계산)
```

| 구성 요소 | 하는 일 | 하지 않는 일 |
|---|---|---|
| 화면 씬 (`scenes/ui/*_screen.tscn` + `scripts/ui/*_screen.gd`) | 노드 배치, 입력 받기, 상태별 표시, `Session` 함수 호출, `exit_requested` 발신 | 네트워크 연결 생성, 게임 규칙 계산, 다른 화면 직접 열기 |
| `ScreenRouter` | `func go_to(screen_id: ScreenTypes.ScreenId, data: RefCounted = null) -> void`. 이전 화면 `queue_free()`, 새 화면 `instantiate()` → `add_child()` → `enter(data)`. `Session.changed`를 보고 강제 이동(호스트 끊김 → 게임하기 + 토스트) | 화면 안의 표시 결정 |
| `Session` (유일한 매니저 싱글톤) | ENet 연결 생성·해제, 방 상태 보유, RPC 송수신·검증, `changed` 시그널 | UI 노드 참조, 문구 결정(문구는 `UiStyle` 상수로만) |
| `FightArena`, `Fighter` | 경기 시뮬레이션. 호스트에서만 규칙 계산, 클라이언트는 스냅샷 적용 | 연결 관리 |
| `UiStyle` | 색, 문구, 슬롯 색 | 상태 보유 |
| `resources/*.tres` | 조정값 | 런타임 수정(공유 객체라 금지, 필요하면 `duplicate()`) |

### 4.3 데이터가 흐르는 방향

```
[사용자 입력] → 화면.gd 핸들러 → Session.<함수>()  ─(RPC, 호스트 검증)→ 호스트 Session
                                                                      │
화면.gd._on_session_changed() ← Session.changed ← 상태 갱신 ←─(RPC)───┘
        └ _apply_state(state)  ← 표시 변경은 이 함수 한 곳에서만
```

- 화면 스크립트는 **로직 함수**(`_on_*`, 상태 전이)와 **표시 함수**(`_apply_state`)를 나눈다. 명세서 섹션 3(UI)과 4(로직)의 구분과 같다.
- 화면은 `Session` 변수를 읽기만 한다. 쓰는 것은 `Session`의 공개 함수로만. 예외: 표시한 토스트를 지우는 `Session.toast = ""` (기존 동작).

### 4.4 네트워크 규칙 (요약)

- 호스트(peer id 1)만 이동, 충돌, 공격, 스톡, 타이머, 승패, 무작위 값을 계산한다. 클라이언트는 입력만 보낸다.
- `any_peer` RPC는 첫 줄에서 ① `multiplayer.is_server()` ② `multiplayer.get_remote_sender_id()` ③ 인자 타입·범위 ④ 현재 phase·`generation`을 검사한다.
- RPC 기본값: 입력 `@rpc("any_peer", "call_remote", "reliable", 2)`, 스냅샷 `@rpc("authority", "call_remote", "unreliable_ordered", 1)`, 이벤트 `@rpc("authority", "call_local", "reliable")`.
- RPC 인자는 기본형, `Vector2`, `Array`, `Dictionary`, Packed 배열만. 객체 전송 금지.
- 연결 시그널 5개 모두 처리. 호스트가 끊기면 모든 클라이언트는 게임하기 화면 + 토스트 "호스트와의 연결이 끊어졌습니다."
- 훈련 모드는 네트워크 연결 없이(`OfflineMultiplayerPeer`) 같은 `Session` 흐름을 쓴다. 그래서 훈련 모드 코드도 "내가 호스트"인 경로로 동작해야 한다.

---

## 5. 검증과 보고

- 바꾼 뒤 headless 테스트를 돌린다(`tests/run_checks.ps1` 또는 `AI_GODOT_GUIDE.md` §검증 명령). 출력에 `SCRIPT ERROR`, `ERROR`, `Parse Error`가 있으면 종료 코드가 0이어도 실패.
- 못 돌리면 사람이 확인할 절차를 적는다. 사람이 확인할 것: 에디터에서 씬이 열리는지, 조작감, UI 배치·문구, 다른 컴퓨터 간 접속.
- 보고 형식: `## 요약` / `## 바꾼 파일` / `## 검증` / `## 임시값·가정` / `## 사람이 확인할 것` / `## 남은 문제·제안`.

---

## [결정 필요 사항]

없음. 결정 기록:

| # | 질문 | 결정 |
|---|---|---|
| 1 | 새 파일 폴더 | 화면 `scenes/ui/` + `scripts/ui/`, 데이터 클래스 `scripts/data/` |
| 2 | 색·글꼴 위치 | `UiStyle` 유지. Theme 전환은 화면 이전 후 별도 검토 |
| 3 | 데이터 구조 정리 시점 | 화면 이전 전에 한 번에 정리 (별도 작업 1건) |

## 작업 순서 (권장)

1. 데이터 구조 정리: 3장 클래스와 `Session.Phase` 도입, `session.gd`·`main.gd`·테스트 갱신. 화면 동작은 바뀌지 않아야 한다.
2. `ScreenRouter` 도입 + SYS-01 게임하기 화면 구현.
3. 이후 화면 명세서(메인, 대기방, 경기, 결과 …)가 나오는 대로 하나씩 이전.
