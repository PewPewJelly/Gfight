# SYS-01 게임하기 화면 개발 명세서

| 항목 | 값 |
|---|---|
| 문서 ID | SYS-01 |
| 화면 이름 | 게임하기 |
| 씬 / 스크립트 | `res://scenes/ui/start_game_screen.tscn` / `res://scripts/ui/start_game_screen.gd` |
| 클래스 | `class_name StartGameScreen extends Control` |
| 엔진 | Godot 4.7, GDScript |
| 기준 해상도 | 1280 × 720 (`project.godot`: `stretch/mode = canvas_items`, `aspect = expand`) |
| 입력 장치 | 마우스 전용. 키보드 단축키는 Enter(주소 확인), Esc(닫기/뒤로)만. 키보드·게임패드 포커스 이동은 만들지 않는다 |
| 문서 상태 | v0.4 (2026-10-27). 기획 답변 14건 반영, 아이콘을 SVG 파일로 전환. 결정 필요 사항 없음 |
| 참조 | `scripts/session.gd`, `scripts/ui_style.gd`, `scripts/main.gd`. 기존 `Design/match-flow-scene-ux.md` S1/S1-1은 이 문서로 대체된다(아래 0.2) |

### 이 문서 읽는 법 (시스템 명세서 공통 규칙)

- 섹션 1~2는 데이터, 섹션 3은 **UI 시각 표현만**, 섹션 4는 **로직만**, 섹션 5는 예외를 다룬다.
- `[제안]`이 붙은 수치는 초안에 없어서 명세서 작성자가 채우고 기획자가 승인한 값이다.
- `[결정 #n]`은 문서 맨 아래 `[결정 필요 사항]` n번에 걸려 있어, 확정 전까지 해당 부분만 구현을 보류한다.
- 문자열은 코드에 직접 쓰지 않고 `UiStyle` 상수로 둔다. 새 상수 이름은 이 문서에서 정한다.
- 네트워크·방 상태는 `Session`(autoload, `scripts/session.gd`)만 바꾼다. 화면은 `Session` 함수를 부르고 `Session.changed` 시그널에 반응만 한다.
- 화면 전환은 아래 0.3의 공통 구조를 따른다. 이후 SYS-02 이하 문서도 같은 구조를 쓴다.

---

## 0. 화면 개요

### 0.1 이 화면

- 진입: `<메인 화면>`(SYS-00, [게임하기][가이드북][설정])에서 [게임하기]를 누르면 들어온다. 대기방에서 나오거나 방이 닫혀도 이 화면으로 돌아온다.
- 구성: 좌상단 `[<] 게임하기` (뒤로가기 버튼, 그 오른쪽에 현재 위치 글자), 화면 좌측 '실전', 우측 '훈련장'.
- 실전에 마우스가 닿으면 아이콘 오른쪽에 [방 참여], [방 생성] 버튼이 나온다(위에서부터 이 순서).
- [방 생성] → `<대기방>`(온라인, 호스트). [방 참여] → '방 주소 입력' 플로팅 창 → 성공 시 `<대기방>`(온라인, 참가자).
- 훈련장 → 즉시 `<대기방>`(훈련, 혼자, 초대 불가). 대기방 설정과 경기 중 치트 모드는 별도 문서에서 다룬다.
- 뒤로가기 → `<메인 화면>`.

### 0.2 기존 문서와의 관계

| 기존 (`match-flow-scene-ux.md`, `main.gd`) | 새 구조 |
|---|---|
| S1 메인 메뉴: [게임 참여][게임 생성][게임 종료] | SYS-00 메인 화면: [게임하기][가이드북][설정] |
| (없음) | SYS-01 게임하기: 실전(방 참여/방 생성), 훈련장 |
| S1-1 게임 참여 팝업 "게임 참여 / 주소 / [참여]" | SYS-01 안의 플로팅 창 "방 주소 입력 / [확인]" |
| 대기실에서 나가면 S1 | 대기방에서 나가면 SYS-01 |
| `Session.local_game()` 같은 키보드 2인(테스트용) | 훈련장은 혼자 쓰는 새 모드 `Session.start_training()` (4.2) |

### 0.3 화면 전환 공통 구조 (전 문서 공통)

- 화면마다 `.tscn` 씬 1개 + 스크립트 1개. 에디터에서 노드를 배치하고, 스크립트는 `@onready var x: Type = %UniqueName`으로 노드를 잡는다(노드에 고유 이름 `%` 켜기).
- `main.tscn` 루트 `ScreenRouter`(Control)가 현재 화면 1개만 자식으로 두고 교체한다.
  - `func go_to(screen_id: StringName, data: RefCounted = null) -> void`: 이전 화면 `queue_free()`, 새 화면 `instantiate()` → `add_child()` → `enter(data)`.
  - 각 화면은 `signal exit_requested(result: RefCounted)`만 내보낸다. 다음 화면 결정은 라우터가 한다.
- 네트워크 사건(호스트 끊김 등)으로 인한 강제 이동도 라우터가 `Session.changed`를 보고 처리한다.
- 이유: 화면별로 파일이 나뉘어 한 화면을 고칠 때 다른 화면이 깨지지 않고, 명세서 1개 = 씬 1개로 코딩 AI에게 맡기기 쉽다. 기존 `main.gd`(모든 화면을 코드로 생성)는 화면별 명세서가 나오는 대로 옮긴다. 옮기는 동안 `tests/ui_flow_test.gd`도 함께 고쳐야 한다.

---

## 1. 화면 상태 (State Enum)

```gdscript
enum ScreenState {
    IDLE,            # 기본. 실전 하위 버튼 숨김
    REAL_EXPANDED,   # 실전 영역에 마우스가 있음. [방 참여][방 생성] 노출
    CREATING,        # [방 생성] 처리 중 (Session.host_game 호출 ~ 결과)
    JOIN_EDITING,    # 방 주소 입력 창 열림, 입력 대기
    JOIN_INVALID,    # 형식 오류 표시 중 (네트워크 요청 없음)
    JOIN_CONNECTING, # 접속 시도 중 (최대 Session.JOIN_TIMEOUT_MSEC = 8000ms)
    JOIN_FAILED,     # 네트워크 단계 실패 표시 중 (찾을 수 없음 / 가득 참 / 진행 중 / 버전 다름)
    LEAVING,         # 다른 화면으로 전환 중. 모든 입력 무시
}

enum JoinError { NONE, BAD_FORMAT, NOT_FOUND, ROOM_FULL, IN_PROGRESS, VERSION_MISMATCH }
```

### 1.1 상태 전이표

| 현재 | 트리거 | 다음 |
|---|---|---|
| IDLE | 실전 영역 `mouse_entered` 또는 RealButton 클릭 | REAL_EXPANDED |
| REAL_EXPANDED | 실전 영역 이탈 후 `HOVER_CLOSE_DELAY`(0.15초) 동안 재진입 없음 | IDLE |
| REAL_EXPANDED | [방 생성] `pressed` | CREATING |
| REAL_EXPANDED | [방 참여] `pressed` | JOIN_EDITING |
| CREATING | `Session.host_game()` == `OK` | LEAVING → `<대기방>` |
| CREATING | `Session.host_game()` != `OK` | IDLE (토스트 표시) |
| JOIN_EDITING / JOIN_INVALID / JOIN_FAILED | [확인] 또는 Enter, 형식 오류 | JOIN_INVALID |
| JOIN_EDITING / JOIN_INVALID / JOIN_FAILED | [확인] 또는 Enter, 형식 정상 | JOIN_CONNECTING |
| JOIN_INVALID / JOIN_FAILED | 입력 텍스트 변경 (`text_changed`) | JOIN_EDITING |
| JOIN_CONNECTING | `Session.phase == "lobby"` (호스트가 대기방 정보 전송) | LEAVING → `<대기방>` |
| JOIN_CONNECTING | `Session.join_error` 비어 있지 않음 | JOIN_FAILED |
| JOIN_* (CONNECTING 포함) | [취소] 또는 Esc | REAL_EXPANDED (`Session.cancel_join()`) |
| IDLE / REAL_EXPANDED | 훈련장 `pressed` | LEAVING → `<대기방>`(훈련) |
| IDLE / REAL_EXPANDED | 뒤로가기 `pressed` 또는 Esc | LEAVING → `<메인 화면>` |

---

## 2. 입출력 데이터 구조

### 2.1 진입 데이터 `StartGameEnterData` (RefCounted)

| 변수 | 타입 | 기본값 | 설명 |
|---|---|---|---|
| `notice` | `String` | `""` | 진입 직후 띄울 토스트. 예: 대기방에서 호스트가 방을 닫아 돌아온 경우 `UiStyle.ROOM_CLOSED`, 호스트와 끊긴 경우 `UiStyle.HOST_LOST` |

- `data == null`이면 모든 필드를 기본값으로 본다(`<메인 화면>`에서 들어올 때).
- 화면이 직접 읽는 전역 값: `Session.local_name: String`, `Session.phase: String`, `Session.join_error: String`, `Session.toast: String`, `Session.last_address: String`, `Session.room_address: String`.

### 2.2 이탈 데이터 `StartGameExitResult` (RefCounted)

| 변수 | 타입 | 설명 |
|---|---|---|
| `route` | `Route` (`enum Route { MAIN_MENU, LOBBY }`) | 다음 화면 |
| `room_mode` | `RoomMode` (`enum RoomMode { NONE, ONLINE, TRAINING }`) | `route == LOBBY`일 때 ONLINE/TRAINING, 그 외 NONE |
| `role` | `Role` (`enum Role { NONE, HOST, CLIENT }`) | 온라인 대기방이면 HOST/CLIENT, 훈련은 HOST, 그 외 NONE |
| `room_address` | `String` | 온라인 대기방일 때 `Session.room_address` (`"IP:포트"`). 그 외 `""` |

- 반환 방법: `exit_requested.emit(result)`. 실제 연결 객체는 반환하지 않는다. 연결은 `Session`이 쥔다.
- `Route`, `RoomMode`, `Role` enum은 다른 화면도 쓰므로 공용 스크립트 `res://scripts/ui/screen_types.gd`(`class_name ScreenTypes`)에 둔다.

### 2.3 주소 입력 창의 기본값

| 변수 | 타입 | 값 |
|---|---|---|
| `initial_address` | `String` | `Session.last_address`가 비어 있지 않으면 그 값(마지막으로 접속에 성공한 주소), 비어 있으면 `"%s:%d" % [Session.local_ipv4(), Session.DEFAULT_PORT]` (내 컴퓨터 주소, 예: `"192.168.0.5:27840"`) |

- `Session.local_ipv4()`는 기존 함수. 같은 네트워크 IPv4(192.168./10./172.)를 우선 반환하고, 없으면 `127.0.0.1`.

### 2.4 주소 검증 결과 (기존 `Session.parse_address(text: String) -> Dictionary` 재사용)

| 키 | 타입 | 설명 |
|---|---|---|
| `ok` | `bool` | 형식 정상 여부 |
| `host` | `String` | `ok == true`일 때 IP 또는 호스트 이름 |
| `port` | `int` | 생략 시 `Session.DEFAULT_PORT` (27840), 범위 1~65535 |

- 허용 형식: `IP`, `IP:포트`, `호스트이름`, `호스트이름:포트`. 앞뒤 공백 제거 후 판정.
- 빈 입력(공백만 포함)은 형식 오류(BAD_FORMAT)로 처리한다. 기존 `parse_address`는 빈 입력을 `127.0.0.1:27840`으로 통과시키므로, 이 화면이 `parse_address` 호출 전에 빈 입력을 먼저 걸러낸다(4.3).

---

## 3. UI (시각 표현 전용)

> 이 섹션은 노드 구성과 보이는 모습만 다룬다. 버튼을 눌렀을 때 무엇이 처리되는지는 섹션 4에만 있다.

### 3.1 UI 노드 트리 (ASCII)

`%` = 에디터에서 "고유 이름으로 접근" 켜기.

```
StartGameScreen (Control, Full Rect)                         start_game_screen.gd
├─ Background (ColorRect, Full Rect, color = UiStyle.BACKGROUND #101927, mouse_filter = IGNORE)
├─ TopBar (MarginContainer, Top Wide, margin 24px 전방향)
│  └─ TopBarRow (HBoxContainer, separation 12)
│     ├─ %BackButton (Button, 44×44, text "<")
│     └─ %LocationLabel (Label, text = UiStyle.PLAY_TITLE "게임하기", font 26, 세로 중앙)
├─ ModeRow (HBoxContainer, Center, separation 160)
│  ├─ %RealArea (Control, 560×360, mouse_filter = PASS)       ← 호버 판정 영역
│  │  ├─ %RealButton (Button, flat, 280×320, focus_mode = NONE)
│  │  │  └─ RealColumn (VBoxContainer, separation 8, alignment CENTER, mouse_filter = IGNORE)
│  │  │     ├─ %RealIcon (TextureRect, 240×240, mouse_filter = IGNORE, texture = res://assets/start_game/sword.svg)
│  │  │     └─ RealLabel (Label, text = UiStyle.MODE_REAL "실전", font 32, CENTER)
│  │  └─ %RealSubMenu (VBoxContainer, RealButton 오른쪽 16px, 세로 중앙, separation 12)
│  │     ├─ %JoinRoomButton (Button, 200×44, focus_mode = NONE, text = UiStyle.JOIN_ROOM "방 참여")
│  │     └─ %CreateRoomButton (Button, 200×44, focus_mode = NONE, text = UiStyle.CREATE_ROOM "방 생성")
│  └─ %TrainingButton (Button, flat, 280×320, focus_mode = NONE)
│     └─ TrainingColumn (VBoxContainer, separation 8, alignment CENTER, mouse_filter = IGNORE)
│        ├─ %TrainingIcon (TextureRect, 240×240, mouse_filter = IGNORE, texture = res://assets/start_game/target.svg)
│        └─ TrainingLabel (Label, text = UiStyle.MODE_TRAINING "훈련장", font 32, CENTER)
├─ %Toast (PanelContainer, Center Bottom, 하단에서 110px 위, 기본 숨김)
│  └─ %ToastLabel (Label, font 18)
├─ %JoinPopup (Control, Full Rect, mouse_filter = STOP, 기본 숨김)
│  ├─ Dimmer (ColorRect, Full Rect, color = UiStyle.DIMMER 검정 65%)
│  └─ JoinPanel (PanelContainer, Center, 최소 480×0, 모서리 14px)
│     └─ JoinColumn (VBoxContainer, separation 14)
│        ├─ JoinTitle (Label, text = UiStyle.JOIN_ADDRESS_TITLE "방 주소 입력", font 32)
│        ├─ %AddressField (LineEdit, 가로 확장, 높이 44, max_length 64,
│        │                  select_all_on_focus = true)
│        ├─ %JoinErrorLabel (Label, font 16, color UiStyle.ERROR #ff5a5a, 최소 높이 24, autowrap)
│        └─ JoinButtons (HBoxContainer, alignment END, separation 12)
│           ├─ %JoinCancelButton (Button, 110×44, text = UiStyle.CANCEL "취소")
│           └─ %JoinConfirmButton (Button, 110×44, text = UiStyle.CONFIRM "확인")
└─ %Fade (ColorRect, Full Rect, color = BACKGROUND, alpha 0, mouse_filter = IGNORE)
```

- 폭 검산(1280px 기준): RealArea 560 + 간격 160 + TrainingButton 280 = 1000px, 좌우 여백 각 140px. RealArea 안: RealButton 280 + 16 + RealSubMenu 200 = 496px.
- 하위 버튼이 RealArea 안에 있어서, 마우스가 아이콘에서 버튼으로 옮겨 가도 영역을 벗어나지 않는다.
- 새 `UiStyle` 상수: `PLAY_TITLE`, `MODE_REAL`, `MODE_TRAINING`, `JOIN_ROOM`, `CREATE_ROOM`, `JOIN_ADDRESS_TITLE`, `CONFIRM`. 재사용: `CANCEL`, `CONNECTING`, `CREATING`, 오류 문구 5종, `ROOM_CLOSED`, `HOST_LOST`.
- 폐기할 기존 상수: `JOIN`("게임 참여"), `CREATE`("게임 생성"), `JOIN_CONFIRM`("참여"), `ADDRESS`("주소"). 메인 화면의 `QUIT`는 SYS-00에서 정한다.

### 3.2 아이콘 그림 (SVG 파일)

두 아이콘은 `res://assets/start_game/sword.svg`, `target.svg`를 `TextureRect`로 표시한다(`stretch_mode = KEEP_ASPECT_CENTERED`). 파일은 240×240, 중심 (120, 120), 흰색으로 그려져 있다. 색은 `self_modulate`로 입힌다: 기본 `UiStyle.TEXT #e8eef7`, 실전 영역이 펼쳐진 동안 RealIcon만 `UiStyle.ACCENT #4f7cff`. 과녁 중심점의 빨강은 파일에 들어 있고 `self_modulate`와 곱해진다.

아래 표는 SVG에 그려진 모양이다. 그림을 고칠 때 기준으로 쓴다.

**`sword.svg` (검 2개 교차)**

| 부품 | 도형 | 수치 |
|---|---|---|
| 칼날 | 선 2개 | (40, 200) → (190, 50), (200, 200) → (50, 50). 두께 12px |
| 칼끝 | 삼각형 2개 | 각 칼날 끝에 길이 24px, 밑변 12px |
| 손잡이 막이 | 선 2개 | 칼날 아래 끝에서 30px 지점에 칼날과 수직, 길이 48px, 두께 10px |
| 손잡이 | 칼날 연장 | 막이 아래로 30px, 두께 14px |

**`target.svg` (과녁)**

| 부품 | 도형 | 수치 |
|---|---|---|
| 바깥 고리 | 원 테두리 | 반지름 108px, 두께 12px |
| 가운데 고리 | 원 테두리 | 반지름 72px, 두께 12px |
| 안쪽 고리 | 원 테두리 | 반지름 36px, 두께 12px |
| 중심점 | 채운 원 | 반지름 10px, 색 #ff5a5a (파일에 고정) |

### 3.3 상태별 표시 규칙

| 상태 | RealSubMenu | JoinPopup | 버튼 활성 | 기타 |
|---|---|---|---|---|
| IDLE | 숨김 (`visible = false`) | 숨김 | 전부 활성 | 아이콘 색 TEXT |
| REAL_EXPANDED | 표시 | 숨김 | 전부 활성 | RealIcon 색 ACCENT |
| CREATING | 표시 | 숨김 | 화면 내 모든 버튼 `disabled = true` | CreateRoomButton 텍스트 `UiStyle.CREATING` "방을 만드는 중…" |
| JOIN_EDITING | 숨김 | 표시 | 팝업 버튼 활성 | AddressField 글자색 `TEXT #e8eef7`, JoinErrorLabel `""` |
| JOIN_INVALID | 숨김 | 표시 | 팝업 버튼 활성 | AddressField 글자색 `ERROR #ff5a5a`, JoinErrorLabel = `UiStyle.BAD_ADDRESS` |
| JOIN_CONNECTING | 숨김 | 표시 | JoinConfirmButton `disabled`, JoinCancelButton 활성 | AddressField `editable = false`, Confirm 텍스트 `UiStyle.CONNECTING` "접속 중…", JoinErrorLabel `""` |
| JOIN_FAILED | 숨김 | 표시 | 팝업 버튼 활성 | AddressField 글자색 `ERROR #ff5a5a`, JoinErrorLabel = 오류별 문구 (5.2 표) |
| LEAVING | 유지 | 유지 | 전부 `disabled` | Fade alpha 1 → 0 |

### 3.4 연출 수치

| 항목 | 값 |
|---|---|
| 하위 버튼 등장 | `modulate.a` 0 → 1, 0.12초, `Tween.TRANS_LINEAR` |
| 하위 버튼 퇴장 | 영역 이탈 후 0.15초 대기, 이후 즉시 `visible = false` |
| 화면 전환 페이드 | 0.2초 |
| 토스트 표시 시간 | 3.0초 |
| 팝업 열기/닫기 | 애니메이션 없음, 즉시 표시/숨김 |
| 팝업 열림 직후 | AddressField에 포커스, 미리 채운 주소 전체가 선택(파란 반전)된 상태. 바로 타이핑하면 기존 값이 지워지고 새로 입력됨 |
| 주소 칸 클릭 | 포커스가 없던 상태에서 클릭하면 전체 선택(`select_all_on_focus`). 이미 포커스가 있으면 클릭 위치에 커서만 이동 |

---

## 4. 이벤트/시그널 흐름 (로직 전용)

> 이 섹션은 데이터와 상태 변경만 다룬다. 각 상태가 어떻게 보이는지는 섹션 3.3을 따른다. UI 갱신은 항상 `_apply_state(state)` 한 곳에서만 한다.

### 4.1 시그널 / 상수 / 변수

```gdscript
signal exit_requested(result: StartGameExitResult)
const HOVER_CLOSE_DELAY: float = 0.15
const TOAST_SECONDS: float = 3.0
var state: ScreenState = ScreenState.IDLE
var join_error: JoinError = JoinError.NONE
var _collapse_ticket: int = 0     # 호버 닫기 예약 취소용 세대 번호
```

### 4.2 `Session`에 추가할 함수 (훈련장용)

- `var training_mode: bool = false`
- `func start_training() -> void`
  - `leave()` 호출로 기존 연결 정리 (`OfflineMultiplayerPeer` 상태)
  - `training_mode = true`, `roster = {1: local_name}`, `ready_states.clear()`, `room_address = ""`, `phase = "lobby"`
  - `changed.emit()`
- `leave()`에 `training_mode = false` 추가.
- 훈련 대기방에서 시작 조건(`can_start()`는 현재 2명 이상 요구)과 치트 모드는 대기방·훈련장 문서에서 정한다. 이 화면은 `start_training()` 호출과 이동까지만 책임진다.

### 4.3 함수 시그니처와 흐름

**진입 / 공통**

- `func enter(data: StartGameEnterData) -> void`
  - `state = IDLE`, `join_error = NONE`, 팝업 숨김
  - `data != null and not data.notice.is_empty()` → `_show_toast(data.notice)`
  - `Session.changed.connect(_on_session_changed)` (중복 연결 검사)
- `func _set_state(next: ScreenState) -> void`
  - `state == LEAVING`이면 무시
  - `state = next` → `_apply_state(next)`
- `func _apply_state(s: ScreenState) -> void` — 섹션 3.3 표를 그대로 적용. 로직 없음.
- `func _exit_to(route: Route, room_mode: RoomMode = RoomMode.NONE, role: Role = Role.NONE) -> void`
  - `_set_state(LEAVING)`
  - `StartGameExitResult` 생성, `room_address = Session.room_address if room_mode == RoomMode.ONLINE else ""`
  - `exit_requested.emit(result)`

**뒤로가기**

- `func _on_back_pressed() -> void`
  - 조건: `state in [IDLE, REAL_EXPANDED]`. 그 외 무시
  - `_exit_to(Route.MAIN_MENU)`
- `func _unhandled_key_input(event: InputEvent) -> void`
  - 눌림(`pressed and not echo`) + Esc만 처리
  - 팝업 열림(`JOIN_*`) → `_on_join_cancel_pressed()`
  - `IDLE/REAL_EXPANDED` → `_on_back_pressed()`
  - 처리 후 `get_viewport().set_input_as_handled()`

**실전 호버**

- `func _on_real_area_mouse_entered() -> void`
  - `_collapse_ticket += 1` (대기 중인 닫기 예약 무효화)
  - `state == IDLE` → `_set_state(REAL_EXPANDED)`
- `func _on_real_area_mouse_exited() -> void`
  - 조건: `state == REAL_EXPANDED`
  - `_collapse_ticket += 1`, 현재 값 저장 → `await get_tree().create_timer(HOVER_CLOSE_DELAY).timeout` → `_try_collapse(saved_ticket)`
- `func _try_collapse(ticket: int) -> void`
  - `ticket != _collapse_ticket`이면 중단 (그 사이 재진입함)
  - `RealArea.get_global_rect().has_point(get_global_mouse_position())`이면 중단
  - `state == REAL_EXPANDED`일 때만 `_set_state(IDLE)`
- `func _on_real_button_pressed() -> void`
  - `state == IDLE` → `_set_state(REAL_EXPANDED)` (마우스 이동 이벤트를 못 받은 경우 대비)

**방 생성**

- `func _on_create_room_pressed() -> void`
  - 조건: `state == REAL_EXPANDED`. 그 외 무시(연타 차단)
  - `_set_state(CREATING)` → `await get_tree().process_frame` (버튼 문구가 한 프레임 그려지게)
  - `var err: Error = Session.host_game(Session.local_name)`
  - `err == OK` → `_exit_to(Route.LOBBY, RoomMode.ONLINE, Role.HOST)`
  - `err != OK` → `_show_toast(Session.toast)`(= `UiStyle.CREATE_FAILED`), `Session.toast = ""`, `_set_state(IDLE)`

**훈련장**

- `func _on_training_pressed() -> void`
  - 조건: `state in [IDLE, REAL_EXPANDED]`
  - `Session.start_training()`
  - `_exit_to(Route.LOBBY, RoomMode.TRAINING, Role.HOST)`

**방 참여 창**

- `func _on_join_room_pressed() -> void`
  - 조건: `state == REAL_EXPANDED`
  - `Session.join_error = ""`, `join_error = NONE`
  - `AddressField.text = _initial_address()`
  - `_set_state(JOIN_EDITING)` → `AddressField.grab_focus()` → `AddressField.select_all()`
- `func _initial_address() -> String`
  - `not Session.last_address.is_empty()` → `Session.last_address`
  - 그 외 → `"%s:%d" % [Session.local_ipv4(), Session.DEFAULT_PORT]`
- `func _on_address_text_changed(new_text: String) -> void`
  - `state in [JOIN_INVALID, JOIN_FAILED]` → `join_error = NONE`, `_set_state(JOIN_EDITING)`
- `func _on_join_confirm_pressed() -> void` / `func _on_address_submitted(text: String) -> void` (Enter)
  - 조건: `state in [JOIN_EDITING, JOIN_INVALID, JOIN_FAILED]`. `JOIN_CONNECTING`이면 무시
  - `AddressField.text.strip_edges().is_empty()` → `join_error = BAD_FORMAT`, `_set_state(JOIN_INVALID)`. 네트워크 요청 없음
  - `var parsed := Session.parse_address(AddressField.text)`
  - `not parsed.ok` → `join_error = BAD_FORMAT`, `_set_state(JOIN_INVALID)`. **네트워크 요청 없음**
  - `parsed.ok` → `_set_state(JOIN_CONNECTING)` → `Session.join_game(parsed.host, parsed.port, Session.local_name)`
  - `join_game` 반환값 != `OK` → `Session.changed`로 들어오는 `join_error`를 `_on_session_changed()`가 처리
- `func _on_join_cancel_pressed() -> void`
  - 조건: `state in [JOIN_EDITING, JOIN_INVALID, JOIN_CONNECTING, JOIN_FAILED]`
  - `Session.cancel_join()` (접속 중이면 연결 끊음, `join_error` 비움)
  - `_set_state(REAL_EXPANDED)` → 마우스가 RealArea 밖이면 `_on_real_area_mouse_exited()` 호출(0.15초 후 접힘)

**Session 반응**

- `func _on_session_changed() -> void`
  - `state == JOIN_CONNECTING and Session.phase == "lobby"` → 접속 성공. `_exit_to(Route.LOBBY, RoomMode.ONLINE, Role.CLIENT)`
    - 이때 `Session`이 성공 주소를 `last_address`로 저장한다(기존 `_remember_address`).
  - `state == JOIN_CONNECTING and not Session.join_error.is_empty()` → `join_error = _map_join_error(Session.join_error)`, `_set_state(JOIN_FAILED)`
  - `not Session.toast.is_empty()` → `_show_toast(Session.toast)`, `Session.toast = ""`
- `func _map_join_error(text: String) -> JoinError` — `UiStyle` 문구와 1:1 매핑(5.2 표). 매핑 실패 시 `NOT_FOUND`.

**토스트**

- `func _show_toast(text: String) -> void` — 텍스트 설정, `_toast_left = TOAST_SECONDS`. `_process(delta)`에서 감소, 0이면 숨김.

### 4.4 핵심 플로우 요약

```
[방 생성]  REAL_EXPANDED ─pressed→ CREATING ─host_game OK→ LEAVING → exit(LOBBY, ONLINE, HOST)
                                        └─host_game 실패→ IDLE + 토스트 "방을 생성할 수 없습니다."

[방 참여]  REAL_EXPANDED ─pressed→ JOIN_EDITING(마지막 주소 또는 내 주소, 전체 선택) ─확인/Enter→ parse_address
             parse 실패 → JOIN_INVALID (빨간 글씨 + "주소 형식이 올바르지 않습니다.")
             parse 성공 → JOIN_CONNECTING ─Session.phase=="lobby"→ LEAVING → exit(LOBBY, ONLINE, CLIENT)
                                         └─Session.join_error→ JOIN_FAILED (빨간 글씨 + 오류 문구)
             아무 단계에서나 [취소]/Esc → Session.cancel_join() → REAL_EXPANDED

[훈련장]   IDLE/REAL_EXPANDED ─pressed→ Session.start_training() → LEAVING → exit(LOBBY, TRAINING, HOST)

[뒤로가기] IDLE/REAL_EXPANDED ─pressed/Esc→ LEAVING → exit(MAIN_MENU)
```

---

## 5. 예외 처리 매트릭스

### 5.1 상황별

| 상황 | 조건 | UI 처리 | 로직 처리 |
|---|---|---|---|
| 주소 형식 오류 | `parse_address().ok == false` (포트가 숫자 아님, 포트 범위 밖, `:` 2개 이상, 허용 안 되는 문자) | 입력 글자색 `#ff5a5a`, 입력 칸 아래 "주소 형식이 올바르지 않습니다." 팝업·입력값 유지 | JOIN_INVALID. 네트워크 요청 없음 |
| 방을 찾을 수 없음 | 접속 시작 후 8000ms 무응답, 또는 `create_client` 실패 | 입력 글자색 `#ff5a5a`, "해당 주소의 게임을 찾을 수 없습니다." | `Session._connection_failed()` → JOIN_FAILED |
| 방이 가득 참 | 호스트 인원 4명 | 빨간 글씨 + "방이 가득 찼습니다." | `JoinRejection.FULL` → JOIN_FAILED |
| 경기 진행 중 | 호스트 `phase != "lobby"` | 빨간 글씨 + "이미 경기가 진행 중입니다." | `JoinRejection.IN_PROGRESS` → JOIN_FAILED |
| 버전 다름 | `game_version()` 불일치 | 빨간 글씨 + "게임 버전이 다릅니다." | `JoinRejection.VERSION` → JOIN_FAILED |
| 접속 중 호스트 끊김 | connecting 중 `server_disconnected` | 빨간 글씨 + "해당 주소의 게임을 찾을 수 없습니다." | `Session._server_left` → JOIN_FAILED |
| 오류 후 다시 입력 | JOIN_INVALID/FAILED에서 `text_changed` | 글자색 원래대로, 오류 문구 지움 | JOIN_EDITING, `join_error = NONE` |
| 빈칸으로 확인 | 미리 채운 주소를 지우고 빈칸(공백만 포함)으로 [확인] | 입력 칸 아래 빨간 글씨 "주소 형식이 올바르지 않습니다." | JOIN_INVALID. 네트워크 요청 없음 |
| 앞뒤 공백 | 예: `" 192.168.0.5 "` | 표시값 그대로 | `strip_edges()` 후 판정 |
| 입력 길이 초과 | 64자 초과 입력/붙여넣기 | 64자에서 입력 멈춤 | `LineEdit.max_length = 64` |
| 줄바꿈 포함 붙여넣기 | 클립보드에 `\n` | 한 줄로 표시 | LineEdit 단일행 동작, 이후 `strip_edges()` |
| 내 주소를 못 구함 | 저장된 주소 없음 + 네트워크 없음 등 `local_ipv4()`가 `127.0.0.1` 반환 | 기본값 `127.0.0.1:27840` 표시 | 정상 동작(같은 컴퓨터 접속용) |
| 방 생성 실패 | `create_server` != OK (포트 27840 사용 중 등) | 하단 토스트 "방을 생성할 수 없습니다." 3초 | IDLE 복귀, 화면 유지 |
| [방 생성] 연타 | CREATING 중 재클릭 | 버튼 `disabled` | `state != REAL_EXPANDED`면 무시 |
| [훈련장] 연타 | LEAVING 중 재클릭 | 버튼 `disabled` | `state == LEAVING`이면 무시 |
| [방 참여] 연타 | 팝업 열린 뒤 재클릭 | Dimmer가 버튼을 덮음 (`mouse_filter = STOP`) | `state != REAL_EXPANDED`면 무시 |
| [확인]/Enter 연타 | JOIN_CONNECTING 중 | 확인 버튼 `disabled`, 입력 칸 잠금 | `state == JOIN_CONNECTING`이면 무시 |
| 접속 중 취소 | JOIN_CONNECTING에서 [취소]/Esc | 팝업 닫힘 | `Session.cancel_join()` → 연결 끊고 `phase = "menu"` |
| 취소와 성공이 같은 프레임 | 취소 처리 전에 대기방 정보 도착 | 대기방으로 이동 | 먼저 처리된 쪽을 따름. LEAVING 이후 입력 무시 |
| 팝업 바깥 클릭 | Dimmer 클릭 | 변화 없음 | 입력 차단만. 닫기는 [취소]/Esc로만 |
| 팝업 열린 상태 뒤로가기 | BackButton 클릭 시도 | Dimmer가 막아 클릭 안 됨 | 해당 없음 |
| 호버 경계 깜빡임 | 마우스가 아이콘 ↔ 하위 버튼 사이 이동 | 하위 버튼 유지 | 하위 버튼이 RealArea 안 + 0.15초 지연 닫기 + 세대 번호 |
| 마우스 이벤트 누락 | 창 밖에서 들어와 `mouse_entered` 없이 클릭 | 클릭 즉시 펼침 | `_on_real_button_pressed()`가 REAL_EXPANDED로 전환 |
| 전환 중 입력 | LEAVING (페이드 0.2초) | 버튼 `disabled` | `_set_state` 무시, 모든 핸들러 조기 반환 |
| 대기방에서 돌아옴 | 방 닫힘 / 호스트 끊김 / [나가기] | 이 화면 + (해당 시) 토스트 3초 | 라우터가 `StartGameEnterData.notice` 전달 |
| 주소 저장 실패 | `ConfigFile.save` != OK | 표시 없음 | `push_warning`만, 접속은 정상 진행 |
| 창 크기 변경 | 전체화면 ↔ 창 (F11, Alt+Enter) | 앵커 기준 재배치 | `stretch/mode = canvas_items` |

### 5.2 접속 오류 문구 매핑 (모두 빨간 글씨 + 입력 칸 아래 표시)

| `JoinError` | `Session.join_error` 값 (`UiStyle`) | 표시 문구 |
|---|---|---|
| BAD_FORMAT | `BAD_ADDRESS` | 주소 형식이 올바르지 않습니다. |
| NOT_FOUND | `NOT_FOUND` | 해당 주소의 게임을 찾을 수 없습니다. |
| ROOM_FULL | `ROOM_FULL` | 방이 가득 찼습니다. |
| IN_PROGRESS | `IN_PROGRESS` | 이미 경기가 진행 중입니다. |
| VERSION_MISMATCH | `VERSION_MISMATCH` | 게임 버전이 다릅니다. |

---

## [결정 필요 사항]

없음. 지금까지 결정된 사항은 아래 기록을 따른다.

| # | 질문 | 결정 |
|---|---|---|
| 1 | 메인 화면 구성 | [게임하기][가이드북][설정]. [게임하기] → 이 화면 |
| 2 | 뒤로가기와 '게임하기' 글자 위치 | `[<] 게임하기` (글자는 버튼 오른쪽) |
| 3 | 방 코드 vs IP 주소 | IP 주소 입력 유지, 제목 '방 주소 입력' |
| 4 | 훈련장 동작 | 즉시 혼자만 있는 대기방(초대 불가). 경기 중 치트 모드는 별도 문서 |
| 5 | 키보드·게임패드 조작 | 이번에는 만들지 않음(Esc/Enter 단축키만) |
| 6 | 주소 입력 칸 기본값 | 마지막 접속 주소, 없으면 내 컴퓨터 주소. 클릭 시 전체 선택 |
| 7 | 빨간 글씨 범위 | 형식 오류 + 네트워크 오류 4종 모두 |
| 8 | 아이콘 | `assets/start_game/`의 SVG 파일 (2026-10-27 변경. 처음 결정은 코드로 선·원을 그림) |
| 9 | 대기방에서 돌아오는 화면 | 게임하기 화면 |
| 10 | 화면 전환 구조 | 화면별 `.tscn` + `ScreenRouter` (0.3) |
| 11 | 버튼 문구 | 초안 문구로 통일 ([방 참여][방 생성][확인][취소]) |
| 12 | `[제안]` 수치 | 승인, 그대로 사용 |
| 13 | 마지막 접속 주소 vs 내 주소 우선순위 | 마지막 접속 주소 우선 |
| 14 | 빈칸으로 [확인] | 형식 오류(빨간 글씨) |
