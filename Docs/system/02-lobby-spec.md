# SYS-02 대기방 개발 명세서

| 항목 | 값 |
|---|---|
| 문서 ID | SYS-02 |
| 화면 이름 | 대기방 (온라인 / 훈련 공용) |
| 씬 / 스크립트 | `res://scenes/ui/lobby_screen.tscn` / `res://scripts/ui/lobby_screen.gd` |
| 클래스 | `class_name LobbyScreen extends Control` |
| 엔진 | Godot 4.7, GDScript |
| 좌표 기준 | 1920 × 1080 (00 §1). 모든 좌표는 `Stage`(테두리 5px 안쪽, 1910×1070)의 왼쪽 위 기준 |
| 입력 장치 | 키보드만으로 모든 조작이 가능해야 한다. 확인 J·Enter, 뒤로·닫기 Esc, 채팅 열기 T(보내기는 Enter). 마우스는 보조 (4.12, 2026-11-09 결정 3) |
| 원본 | 사용자 제공 "GFight 대기방(Lobby) UI — 구조 및 상태 로직 명세" (React 프로토타입, Make 버전 5)를 Godot 구조와 `00_System_Context.md` 규칙으로 다시 쓴 것 |
| 문서 상태 | v0.5 (2026-11-09). UI/UX 결정 1·2·3·4·5 반영(색·글꼴·기울기, 키보드 조작, 방 주소 공유 삭제, 닉네임 우선 표기. 근거 `Docs/design/ui-ux-direction.md`). v0.4 (2026-10-27): 결정 19건 반영, 아이콘·캐릭터·맵 그림을 SVG 파일로 전환 |
| 참조 | `00_System_Context.md` (항상 함께 읽음), `01-start-game-spec.md` (진입), `scripts/session.gd`, `scripts/ui_style.gd` |

### 이 문서 읽는 법

- 섹션 1~2는 데이터, 섹션 3은 **UI 시각 표현만**, 섹션 4는 **로직만**, 섹션 5는 예외를 다룬다.
- `[제안]` = 원본에 없어 작성자가 채운 값. `[결정 #n]` = 맨 아래 n번이 확정될 때까지 해당 부분만 구현 보류.
- 모든 방 상태는 **호스트가 결정하고 `Session` RPC로 전달**한다(00 §4.4). 원본의 봇 채팅, 디버그 바, 가짜 플레이어는 없다.
- **애니메이션 없음.** 이 화면의 모든 표시 변경은 즉시 반영한다. 유일한 예외: 버튼을 누르는 동안 내용이 아래로 3px 내려가는 효과. 화면 전환 페이드도 없다.

---

## 0. 화면 개요

### 0.1 이 화면

- 진입: SYS-01 게임하기의 [방 생성](온라인·호스트), [방 참여] 성공(온라인·참가자), [훈련장](훈련·혼자). 결과 화면에서 대기방으로 돌아올 때도 들어온다.
- 한 화면에서 참가자 확인, 캐릭터 선택, 방 설정(방장), 개인 설정, 준비/시작, 말풍선 채팅을 처리한다.
- 이탈: 경기 시작 → `<경기>`. 나가기, 강제 퇴장, 방 닫힘, 호스트 끊김 → SYS-01 게임하기(+토스트).
- 훈련 모드: 혼자 있는 방. 초대·채팅·참가자 관리 없음. 맵·캐릭터 등 일반 설정은 온라인과 같다. 시작 버튼은 항상 활성. 허수아비·목숨·텔레포트 같은 치트 기능은 `<경기>` 화면에서 조정한다(별도 문서).

### 0.2 화면 배치

```
┌──────────────────────────────────────────────────────────────────────────┐
│ (←) [방이름]                   ╱══════════ 선택창(Panel) ═════╱ [방]      │
│ [맵 ○○] [준비 n/m]             ╱                              ╱  [캐릭터] │
│                               ╱  탭에 따라 하나만 표시:         ╱    [설정]  │
│        (말풍선)               ╱   방     → PlayerList          ╱  ▒ 오른쪽  │
│      ┌─────────┐             ╱   캐릭터 → CharacterGrid       ╱  ◀ 띠      │
│      │ 내 캐릭터 │            ╱   설정   → SettingsPanel       ╱   준비     │
│      │ 440×440 │            ╱   (맵 선택) → MapGrid           ╱   화살표   │
│      └─────────┘           ╱                                ╱              │
│ [T 채팅]                  ╱                                ╱               │
│ ┌──────────────────╲     ╱                                ╱                │
│ │캐릭터명            ╲   ╱                                ╱                 │
│ │닉네임 ★    (버튼)  │ ╱                                ╱                  │
└──────────────────────────────────────────────────────────────────────────┘
```

### 0.3 원본에서 바뀐 것

| 원본 (React) | 이 문서 (Godot) |
|---|---|
| 모든 상태를 `Lobby.tsx`가 로컬로 보유 | 방·플레이어 상태는 `Session`(호스트 결정). 화면은 표시·입력만 |
| 방 코드 `7KQ2X` | 없음. 방 코드·방 주소를 보여 주거나 복사하지 않는다. 다른 사람은 공개 방 목록에서 들어온다 (2026-11-09 결정 4) |
| 봇 채팅 응답 | 실제 플레이어 채팅을 RPC로 전달 |
| 호스트도 준비, 전원 준비 시 시작 + [준비 해제] | 호스트는 준비하지 않음. 시작 버튼이 곧 준비(현재 게임 규칙) |
| 캐릭터 8종, 맵 2종 + 랜덤 | 카탈로그 방식(00 §3.8). 현재 캐릭터 1종, 맵 1종(TestMap). 추가하면 선택칸에 자동 표시 |
| 방장 권한 양도 | 없음 (방을 만든 컴퓨터가 서버라 실제 양도 불가) |
| 시작 카운트다운 3→2→1→GO, `started` 카드 | 없음. 바로 `<경기>`로 이동, 경기장의 기존 3초 카운트다운 사용 |
| 공개/비공개 칩·설정 | 없음. 모든 방은 공개 방이고 비공개·친구 전용 옵션은 만들지 않는다 (2026-11-09 결정 4) |
| 프로필의 레벨·승리 | 없음. 캐릭터·준비 상태만 |
| `left` 화면 + [다시 입장하기] | 나가면 SYS-01 게임하기 |
| 디버그 바 | 없음 |
| `TabRail` 컨테이너 `border-[10px]` (화면 위 20px 띠) | 없음. 그 자리는 스테이지 배경과 줄무늬로 채움 |
| SVG 일러스트, CSS skew | 아이콘·캐릭터·맵 그림은 `assets/`의 SVG 파일. 기울어진 상자·테두리는 `_draw()`로 그리고 기울기는 다각형 좌표로 계산 |

---

## 1. 화면 상태 (State Enum)

서로 독립인 4개 축으로 나눈다.

```gdscript
## 화면 흐름 (오버레이·전환). 한 번에 하나.
enum FlowState {
	BROWSING,     # 기본. 탭 조작 가능
	CHAT_INPUT,   # 내 말풍선 입력 중 (온라인만)
	MENU_OPEN,    # 다른 플레이어 카드의 ⋯ 메뉴 열림 (호스트만)
	MODAL_OPEN,   # 모달 열림 (종류는 modal_kind)
	STARTING,     # 시작 요청을 보내고 경기 시작을 기다림
	CLOSING,      # 호스트가 방을 닫는 중 (Session.phase == "closing", 0.2초)
	LEAVING,      # 다른 화면으로 전환 중. 모든 입력 무시
}

enum Tab { ROOM, CHARACTER, SETTINGS }
enum SettingsView { ROOM, PERSONAL, MAP }
enum ReadyButtonState { IDLE, READY, START, START_DISABLED }
enum ModalKind { NONE, EXIT, KICK, PROFILE }
enum PlayerAction { PROFILE, MUTE, KICK }
```

### 1.1 `ReadyButtonState` 결정 규칙

| 조건 | 상태 |
|---|---|
| 훈련 모드 | START (항상) |
| 온라인 + 내가 호스트 + `Session.can_start()` | START |
| 온라인 + 내가 호스트 + 시작 불가 | START_DISABLED |
| 온라인 + 참가자 + 준비 완료 | READY |
| 온라인 + 참가자 + 준비 안 함 | IDLE |

- `can_start()` (온라인): 인원 2명 이상 + 호스트 제외 전원 준비 완료(기존 규칙).
- 준비 수 표시(`준비 n/m`, 화살표 색): `n = Session.ready_count()`(호스트 제외 준비 완료 수), `m = 인원 - 1`. 다른 참가자가 0명이면 `0/0`, 화살표 비율 0.

### 1.2 `FlowState` 전이표

| 현재 | 트리거 | 다음 |
|---|---|---|
| BROWSING | T(조건 4.7) 또는 [T 채팅] 클릭 | CHAT_INPUT |
| CHAT_INPUT | Enter(보내기 후 닫기), Esc, 입력칸 포커스 잃음 | BROWSING |
| BROWSING | ⋯ 클릭 (호스트) | MENU_OPEN |
| MENU_OPEN | [음소거] / 메뉴 밖 클릭 / Esc | BROWSING |
| MENU_OPEN | [프로필 보기], [강제 퇴장] | MODAL_OPEN |
| BROWSING | 뒤로가기 클릭, 또는 닫을 것이 없을 때 Esc (4.9) | MODAL_OPEN (EXIT) |
| MODAL_OPEN | [취소], 배경 클릭, Esc | BROWSING |
| MODAL_OPEN (EXIT) | [나가기] | CLOSING(호스트 + 다른 참가자 있음) 또는 LEAVING |
| BROWSING | 시작 버튼(START) | STARTING |
| STARTING | `Session.start_game()` 실패 | BROWSING |
| 모든 상태 | `Session.phase == "playing"` | LEAVING → `<경기>` |
| 모든 상태 | `Session.phase == "menu"` | LEAVING → 게임하기 |

---

## 2. 입출력 데이터 구조

### 2.1 진입 데이터 `LobbyEnterData` (RefCounted)

| 변수 | 타입 | 기본값 | 설명 |
|---|---|---|---|
| `room_mode` | `ScreenTypes.RoomMode` | `ONLINE` | ONLINE / TRAINING |
| `role` | `ScreenTypes.Role` | `HOST` | HOST / CLIENT. 훈련은 항상 HOST |
| `initial_tab` | `Tab` | `ROOM` | 처음 열 탭 |

### 2.2 이탈 데이터 `LobbyExitResult` (RefCounted)

| 변수 | 타입 | 설명 |
|---|---|---|
| `route` | `enum Route { START_GAME, MATCH }` | 다음 화면 |
| `notice` | `String` | `START_GAME`일 때 게임하기 화면 토스트. 직접 나가면 `""` |
| `match_setup` | `MatchSetup` (00 §3.6) | `MATCH`일 때만. 그 외 `null` |

### 2.3 사용하는 전역 데이터 (00 §3)

- `PlayerData`: `peer_id`, `slot`, `display_name`, `is_ready`, `character`
- `RoomState`: `mode`, `phase`, `address`, `players`, `name`, `max_players`, `map`, `stocks`, `generation`
- `MatchSetup`, `ContentCatalog`, `CharacterDef`, `MapDef`
- 닉네임 최대 10자 (00 §3.2)

### 2.4 이 화면 전용 (로컬, 네트워크로 보내지 않음)

| 변수 | 타입 | 설명 |
|---|---|---|
| `muted_ids` | `Dictionary` (int → bool) | 내가 음소거한 플레이어. 그 사람 말풍선을 표시하지 않음. 방을 나가면 초기화 |
| `prefs` | `Dictionary` `{ "bgm": int, "sfx": int }` | 0~100, 기본 70 / 80. `settings.cfg [audio]`. 메인 [설정]과 같은 값을 공유 |

### 2.5 선택칸 구성 규칙 (카탈로그에서 자동 생성)

- 캐릭터 선택칸 = `ContentCatalog.characters` 순서대로 + (2종 이상이면) 마지막에 `random`.
- 맵 선택칸 = `ContentCatalog.maps` 순서대로 + (2종 이상이면) 마지막에 `random`.
- 열 수: 캐릭터 `columns = clampi(항목 수, 1, 3)`, 맵 1열 [제안]. 항목을 열에 왼쪽부터 차례로 나눠 담는다(항목 i → 열 `i % columns`).
- 현재 카탈로그(00 §3.8): 캐릭터 `test_fighter` 1개 → 1열 1항목, `random` 없음. 맵 `test_map` 1개 → 1열 1항목, `random` 없음.
- 기본 선택: 캐릭터는 카탈로그 첫 캐릭터, 맵도 첫 맵.

---

## 3. UI (시각 표현 전용)

> 노드 구성과 보이는 모습만 다룬다. 눌렀을 때의 처리는 섹션 4에만 있다.

### 3.1 기하 상수와 기울기 표현

`scripts/ui/lobby/lobby_geometry.gd` (`class_name LobbyGeometry`, 상수와 정적 함수만):

```gdscript
const SKEW_DEG: float = 9.0               # 메인 메뉴와 같은 9° (2026-11-09 결정 1. 옛 값 12°)
const TAN: float = 0.15838                # tan(9°)
const STAGE_SIZE := Vector2(1910, 1070)   # 루트 테두리(5px) 안쪽
const PANEL_BLEED: float = 16.0
const PANEL_LEFT: float = 840.0           # y = PANEL_TOP 지점의 왼쪽 x
const PANEL_TOP: float = -16.0
const PANEL_WIDTH: float = 840.0
const PANEL_HEIGHT: float = 1102.0        # STAGE.y + 2 * BLEED
const PANEL_PAD: float = 14.0
const PANEL_PAD_Y: float = 26.0           # BLEED - 4(테두리) + PAD
const PANEL_INNER_H: float = 1042.0       # STAGE.y - 2 * PAD
static func panel_right_at(y: float) -> float   # PANEL_LEFT + PANEL_WIDTH + TAN * (y - PANEL_TOP)
static func slant_x(x: float, y: float, origin_y: float) -> float   # x + TAN * (y - origin_y)
```

- **기울기**: 메인 메뉴와 같은 9°(원본 CSS는 `skewX(12°)`, 원점 왼쪽 위). 원본과 같은 방식으로 기울어진 도형의 점 (x, y)를 `x + TAN * (y - 도형 top)`으로 옮겨 그린다. Godot `Control`에는 skew 속성이 없으므로 `SlantBox`(3.3)가 `_draw()`로 다각형을 그리고, 그 안의 글자·그림은 기울이지 않는다.
- **화면 배치**: `LobbyStage`는 1920×1080 크기로 화면 가운데(`PRESET_CENTER`)에 둔다. 창 비율이 16:9가 아니라서 남는 영역은 `Backdrop`(MAIN_INK)이 채운다.
- **잘림**: `Stage`는 `clip_contents = true`. 선택창은 위아래로 16px 넘쳐서 위아래 테두리와 모서리가 보이지 않는다.

### 3.2 UI 노드 트리 (ASCII)

`%` = 고유 이름. `z` = `z_index`.

```
LobbyScreen (Control, Full Rect)                                   lobby_screen.gd
├─ Backdrop (ColorRect, Full Rect, MAIN_INK)
└─ %LobbyStage (Control, 1920×1080, 화면 가운데)
   ├─ StageFrame (Panel, 1920×1080, 테두리 5px MAIN_INK, 모서리 36px, 배경 = 3.4의 배경 그라데이션)
   └─ %Stage (Control, 위치 (5,5), 1910×1070, clip_contents = true)
	  ├─ Stripes (Control, Full Rect, _draw: 78° 줄무늬, 흰색 4.5%, 두께 2px, 간격 28px)
	  │
	  ├─ %Portrait (Control, (230,300), 440×440)
	  │  ├─ PortraitShadow (Control, 300×36 타원, 검정 15%, top 462, 가로 중앙)
	  │  ├─ %PortraitArt (CharacterArt, 440×440)
	  │  └─ %MyBubbleAnchor (Control, 아트의 x 40%, y −4% 지점)
	  │     ├─ %MyBubble (BubbleView)
	  │     └─ %ChatInput (BubbleInput, 420×66)
	  ├─ %ChatHintButton (Button, (40,812), 알약, 검정 25%, UiStyle.CHAT_HINT "T 채팅", z 10)
	  ├─ %MyCard (Control, (0, 874), 600×196, z 10)
	  │  ├─ MyCardShape (Control, _draw 3.5)
	  │  ├─ %MyCharacterName (Label, (40,28), 26px bold MAIN_BROWN)
	  │  ├─ %MyNickname (Label, (36,66), 88px black, 최대 너비 360, 말줄임. 뒤에 " · P{slot}" 40px [제안] — 결정 5)
	  │  ├─ %MyHostStar (Control, 56×56 별, 닉네임 오른쪽 8px)
	  │  └─ %ReadyButton (RoundButton, (474,70), 100×100)
	  │
	  ├─ %ContentHost (Control, Full Rect, z 10)        ← 아래 4개 중 하나만 자식으로 둠
	  │  ├─ PlayerList        (scenes/ui/lobby/player_list.tscn)
	  │  ├─ CharacterGrid     (scenes/ui/lobby/slant_grid.tscn)
	  │  ├─ MapGrid           (scenes/ui/lobby/slant_grid.tscn)
	  │  └─ SettingsPanel     (scenes/ui/lobby/settings_panel.tscn)
	  │
	  ├─ %RightBand (SlantBox, (1680, −16), 400×1102, MAIN_BROWN, 테두리 없음, z 5)
	  ├─ %TabRail (Control, z 20)
	  │  ├─ %TabRoom (SlantTab, top 30, 128×56, "방")
	  │  ├─ %TabCharacter (SlantTab, top 98, 128×56, "캐릭터")
	  │  └─ %TabSettings (SlantTab, top 166, 128×56, "설정")
	  ├─ %ReadyArrow (Control, Full Rect, mouse_filter IGNORE, z 20, _draw 3.11)
	  │
	  ├─ %Header (HBoxContainer, (36,28), separation 16, z 30)
	  │  ├─ %BackButton (RoundButton, 80×80)
	  │  └─ %RoomNameBox (PanelContainer, 높이 80, 모서리 22, 테두리 4 MAIN_INK, 배경 MAIN_PAPER, 왼쪽 여백 28, 오른쪽 28)
	  │     └─ %RoomNameLabel (Label, 38px bold, 최대 너비 320, 말줄임)
	  ├─ %RoomChips (HBoxContainer, (36,132), separation 10, z 20)
	  │  ├─ %MapChip (Chip, "맵 {이름}")
	  │  └─ %ReadyChip (Chip, "준비 {n}/{m}")
	  │
	  ├─ %ModalLayer (Control, Full Rect, z 50, 기본 숨김)
	  │  ├─ Dimmer (ColorRect, Full Rect, MAIN_INK 50%, mouse_filter STOP)
	  │  └─ %ModalBox (SlantBox, 너비 780 (프로필 820), 화면 가운데)
	  │     └─ VBoxContainer: %ModalTitle (Label, 40px bold) + %ModalBody (Control) + %ModalButtons (HBoxContainer, 오른쪽 정렬, separation 16)
	  └─ %Toast (PanelContainer, 가운데 아래, 하단에서 165px 위, 글자 27px, z 50, 기본 숨김)
```

### 3.3 하위 씬 (재사용 단위, `scenes/ui/lobby/` + `scripts/ui/lobby/`)

| 클래스 | 기반 | 역할 |
|---|---|---|
| `SlantBox` | Control | 기울어진 사각형. `@export fill: Color`, `border_color: Color`, `border_width: float`, `corner_radius: float`(모서리당 6분할 근사), `shadow_offset: float`, `skew_deg: float = 9`. 자식은 똑바로 그림 |
| `SlantTab` | BaseButton | 탭. 내부에 `SlantBox` + `Label`. `@export active: bool` |
| `RoundButton` | BaseButton | 원형 버튼. `@export fill, border_color, shadow_color: Color`, `icon: LobbyIcons.Kind` |
| `Chip` | PanelContainer | 룸 태그. 높이 44, 둥근 알약, MAIN_INK, 20px bold 흰 글자, 앞 라벨 부분 흰색 55% |
| `CharacterArt` | TextureRect | `@export pick: StringName`. `res://assets/characters/{pick}.svg`를 표시(`KEEP_ASPECT_CENTERED`). 파일 이름 = 캐릭터 id. `random`이면 `random.svg`(`?`). 파일이 없으면 `push_warning` + `random.svg` |
| `MapArt` | TextureRect | `@export pick: StringName`. `res://assets/maps/{pick}.svg`를 표시(640×360 비율, `KEEP_ASPECT_COVERED`). 파일 이름 = 맵 id. TestMap은 `test_map.svg`(바닥 1개 + 발판 2개). `random`이면 `random.svg`(큰 `?`). 파일이 없으면 `push_warning` + `random.svg` |
| `SelectTile` | BaseButton | 캐릭터·맵 공용 타일 (3.8) |
| `BubbleView` / `BubbleInput` | Control | 말풍선 (3.6) |
| `SlantGrid` | Control | 무한 반복 기울어진 그리드 (3.8) |
| `PlayerList`, `SettingsPanel` | Control | 3.7, 3.9 |
| `LobbyIcons` | RefCounted (정적) | `enum Kind { X, O, V, STAR, BACK, INFO, DOTS, MUTE, PLAY, LOCK }`(COPY는 방 주소 복사가 없어져 뺌). 각 Kind = `res://assets/icons/{소문자 이름}.svg`(64×64, 흰색). `static func texture(kind: Kind) -> Texture2D`(처음 한 번 `load` 후 캐시), `static func draw(canvas: CanvasItem, kind: Kind, rect: Rect2, color: Color) -> void`(= `canvas.draw_texture_rect(texture(kind), rect, false, color)`) |

### 3.4 색과 글꼴 (메인 메뉴 스타일 그대로)

2026-11-09 결정 1·2: 대기방도 메인 메뉴의 색·글꼴·기울기를 그대로 쓴다. 옛 회색 체계(`LOBBY_*` 색 상수)는 없앤다. 애니메이션 없음(맨 위 규칙)은 그대로다.

| 상수 (기존 `UiStyle`) | 값 | 쓰임 |
|---|---|---|
| `MAIN_INK` | #141416 | 테두리, 딱딱한 그림자, 선택창·칩·배너 바탕, 스테이지 바깥, 어두운 글자 |
| `MAIN_YELLOW` | #eba823 | 활성 탭, 선택 칩, 선택 타일 점선, 시작 버튼, 준비 완료 표시 |
| `MAIN_BROWN` | #3a2a08 | 밝은 바탕 위 보조 글자, 오른쪽 띠, 선택창 테두리, 노란 버튼 그림자 |
| `MAIN_PAPER` | #fff4d6 | 밝은 상자(방 이름 상자, 타일, 비활성 탭) |
| `MAIN_SELECTED_TEXT` | #ffffff | 어두운 바탕 위 글자, 카드 바탕 |
| 배경 그라데이션 | #E39A16 → #F2BC45 → #FCE6AE | 스테이지 배경 (메인 메뉴와 같은 그라데이션) |

- 글꼴: 영어·숫자 Barlow Condensed, 한글 Noto Sans KR (`resources/fonts/files/`). 본문의 bold·black은 이 글꼴의 굵기다.
- 딱딱한 그림자: 같은 모양을 `MAIN_INK`로 아래 5px(탭 4px) 옮겨 먼저 그린다. 흐림 없음.
- 옛 색 → 새 색 대응 [제안] (결정 1을 지키려고 작성자가 정한 대응이며, 본문 수치는 이 표대로 고쳐 두었다):

| 옛 상수 (값) | 새 색 |
|---|---|
| `LOBBY_BG` (#A9A9A9) | 배경 그라데이션 |
| `LOBBY_OUTSIDE` (#262626), `LOBBY_LINE` (#555555), `LOBBY_LINE_DARK` (#2E2E2E), `LOBBY_CHIP` (#4E4E4E) | `MAIN_INK` |
| `LOBBY_PANEL` / `LOBBY_PANEL_LINE` (#4A4A4A / #3A3A3A) | `MAIN_INK` / `MAIN_BROWN` |
| `LOBBY_BAND` (#7A7A7A) | `MAIN_BROWN` |
| `LOBBY_CARD` (#F4F4F4) | `MAIN_PAPER` |
| `LOBBY_GOLD_BG` / `LOBBY_GOLD` / `LOBBY_GOLD_SHADOW` | `MAIN_YELLOW` / `MAIN_INK` / `MAIN_BROWN` |
| `LOBBY_ORANGE` (#F5A040) | `MAIN_YELLOW` |
| `LOBBY_RED` 계열 (준비 안 함, 강제 퇴장) | `MAIN_INK` 테두리 + `MAIN_PAPER` 바탕(준비 안 함), `MAIN_INK` 바탕 + 흰 글자(강제 퇴장) |
| `LOBBY_GREEN` 계열 (전원 준비) | `MAIN_YELLOW` |
| `LOBBY_START` 계열 (시작 버튼) | `MAIN_INK` / `MAIN_YELLOW` / `MAIN_BROWN` |

### 3.5 왼쪽 영역

- **MyCardShape**: 다각형 `(−20,0) → (572,48) → 2차 곡선(제어점 (592,50)) → (592,70) → (592,226) → (−20,226)`. 흰 채움, 테두리 5px `MAIN_INK`. 같은 모양을 (+10, −10) 옮겨 검정 14%로 먼저 그린다.
- **ReadyButton** (100×100 원, 테두리 5px, 그림자 아래 5px, 버튼 위 글자 없음, `tooltip_text`만):

| 상태 | 테두리 / 배경 / 그림자 [제안] | 아이콘 | tooltip |
|---|---|---|---|
| IDLE | MAIN_INK / MAIN_PAPER / MAIN_INK | X 56px, MAIN_INK | 준비하기 |
| READY | MAIN_INK / MAIN_INK / MAIN_BROWN | V 56px, MAIN_YELLOW | 준비 해제 |
| START | MAIN_INK / MAIN_YELLOW / MAIN_BROWN | ▶ 46px, MAIN_INK | 게임 시작 |
| START_DISABLED | START 색, `modulate.a = 0.4`, `disabled = true` [제안] | ▶ 46px | 시작 조건 문구 (4.5) |

- **MyHostStar**: 내가 호스트일 때만(온라인). 훈련 모드는 숨김 [제안].
- **내 슬롯 색 띠** (결정 5): MyNickname 바로 아래, 닉네임 너비 × 높이 8px [제안], `UiStyle.slot_color(slot)`. 훈련 모드도 표시.
- **ChatHintButton**: 온라인 + `flow == BROWSING`일 때만 표시.

### 3.6 말풍선 (온라인만)

| 항목 | 값 |
|---|---|
| BubbleView | 최대 너비 460, 글자 24px [제안], 한 줄, 넘치면 말줄임, 흰 배경, 테두리 4px MAIN_INK, 아래쪽 꼬리 삼각형(밑변 24, 높이 16) [제안] |
| BubbleInput | 420×66, `LineEdit`(`max_length = 40`), 오른쪽에 `n/40` (20px, MAIN_BROWN) |
| 다른 플레이어 버블 | PlayerList 카드 안, 아트 기준 (x 74%, y −26%) |
| 표시 시간 | 3.0초 |

### 3.7 PlayerList ([방] 탭)

- 선택창 외형: `SlantBox` (840, −16), 840×1102, 모서리 22, 테두리 4 MAIN_BROWN, 배경 MAIN_INK, 그림자 없음. 위아래 안쪽 여백 26, 좌우 14.
- **나를 뺀** 플레이어를 slot 순으로 위에서 아래로 쌓는다. 카드 사이 14px.
- 카드 높이 `card_h = (1042 − 14 × (n − 1)) / n` (n = 다른 플레이어 수, 최소 1). 예: n=3 → 337.3px.
- 카드(`SlantBox`): 모서리 16, 테두리 4 MAIN_INK, 흰 배경.
  - 왼쪽 변 안쪽: 슬롯 색 띠, 폭 8px [제안], `UiStyle.slot_color(slot)` (결정 5)
  - 가운데: `CharacterArt`, 크기 `min(card_h × 0.7, 400)`
  - 왼쪽 아래 (36, 아래 20): 닉네임 `clamp(card_h × 0.15, 44, 80)`px와 그 뒤 " · P{slot}"(닉네임 크기의 50% [제안]) (결정 5: 닉네임 우선), 호스트면 ★(닉네임 × 0.72), 아래에 캐릭터 이름 22px MAIN_BROWN, 음소거면 음소거 아이콘
  - 오른쪽 아래 (오른쪽 40, 아래 16): 준비면 O, 아니면 X, 크기 `max(56, 닉네임 × 1.1)`. 호스트 카드는 O/X 대신 "방장" 글자(MAIN_BROWN, 같은 크기의 60%) [제안]
  - 오른쪽 위 (오른쪽 28, 위 16): ⋯ 버튼 80×42. 내가 호스트가 아니면 `disabled`, `modulate.a = 0.35`, tooltip "방장만 사용할 수 있어요"
  - ⋯ 메뉴: 너비 280, 항목 `프로필 보기` / `음소거`|`음소거 해제` / 구분선 / `강제 퇴장`(MAIN_INK 바탕, 흰 글자). 열린 카드는 `z_index + 10`
- 다른 플레이어 0명:
  - 온라인: 점선 상자에 "초대 대기 중…". 방 주소 공유 안내("ⓘ 버튼으로 방 주소를 공유해 보세요")는 없앤다 (2026-11-09 결정 4)
  - 훈련: "훈련 모드 · 혼자 연습합니다" [제안]

### 3.8 SlantGrid + SelectTile

- 선택창 외형 3.7과 같음 + `clip_contents`. 열과 스크롤 방향이 선택창 기울기를 따른다.
- 열 너비 `col_w = (832 − 28 − 14 × (n − 1)) / n`. 1열 804px, 2열 395px, 3열 ≈258.7px.
- 무한 반복: `pitch = tile_h + 14`, `cycle = 열 항목 수 × pitch`, `m = fposmod(offset + col_shift[c] × pitch, cycle)`. k번째 타일 top = `26 + k × pitch − m − pitch`, 내용은 `col[k % col.size()]`. 타일 x = 열 x + `TAN × (top − PANEL_TOP)`.
- 열당 타일 노드 수 = `ceili((1042 + cycle + 2 × pitch) / pitch) + 1`. 처음에 만들고 재사용한다(스크롤 중 생성·삭제 금지).
- 항목 1개짜리 열도 같은 규칙으로 같은 타일이 반복된다(원본과 동일).
- 잠금: 그리드 `modulate.a = 0.5`, 타일 `mouse_filter = IGNORE`. 위쪽 배너(좌우 44 안쪽, top 36, 높이 84, MAIN_INK, 흰 24px 글자).

| 사용처 | 열 | tile_h | col_shift | 잠금 / 배너 |
|---|---|---|---|---|
| 캐릭터 | 2.5 규칙 | 300 | 3열이면 `[0, −0.38, 0.1]`, 그 외 0 | 온라인 참가자가 준비 완료 / "준비 완료 상태에서는 캐릭터를 바꿀 수 없어요" + [준비 해제] |
| 맵 | 1열 | 316 | 0 | 없음 |

**SelectTile**

- 모서리 16, 배경 MAIN_PAPER, 기본 테두리 4px MAIN_INK. 선택 시 5px 점선 MAIN_YELLOW(점 12, 간격 8 [제안]). 선택 표시는 테두리뿐.
- 선택 안 한 타일도 원래 색 그대로. 마우스 올림 효과 없음.
- 캐릭터 타일: 아트 210px(아래 여백 48), 이름 32px MAIN_INK(선택 시 MAIN_BROWN), 왼쪽 아래 (32, 아래 16). 그라데이션 없음.
- 맵 타일: 아래 46% 높이 검정 80%→40%→0% 그라데이션, 이름 40px 흰색(선택 시 MAIN_YELLOW), 영문명 흰색 70%.
- 오른쪽 위 (오른쪽 24, 위 16): (i) 40px 원, tooltip = 이름.

### 3.9 SettingsPanel ([설정] 탭)

- 선택창 외형 3.7과 같음. 위쪽 바(높이 84): 서브 탭 칩 [방] [개인] (높이 68, 최소 너비 118, 선택 시 MAIN_YELLOW 바탕 + MAIN_INK 테두리).
- [방] 탭에서 온라인 참가자면 바 오른쪽에 "🔒 읽기 전용 · 방장만 수정할 수 있어요" 배지, 모든 행 배경 MAIN_PAPER에 불투명도 60%, 입력 비활성.
- 행 공통: 모서리 16, 테두리 4 MAIN_INK, 수정 가능하면 흰 배경. 제목 34px, 설명 20px.
- **[방] 탭**

| 행 | 온라인 높이 | 훈련 높이 | 내용 |
|---|---|---|---|
| 방 이름 | 160 | (숨김) | 기울어진 입력칸 380×68, `max_length = 12`, `n/12` |
| 맵 설정 | 596 | 944 | 현재 맵 그림 버튼 400×262 (그라데이션 + 이름/영문명). 맵이 1종이어도 버튼은 활성(맵 선택 화면에 1개 표시) |
| 최대 인원 | 160 | (숨김) | 칩 [2명] [3명] [4명]. 현재 인원 미만 `disabled` |

  - 온라인 맵 행 = 1042 − 84 − 14 × 3 − 160 × 2 = 596. 훈련 = 1042 − 84 − 14 = 944.

- **[개인] 탭** (행 높이 (1042 − 84 − 14 × 3) / 3 = 305.3)
  1. 배경음: 슬라이더 0~100 (너비 360, 색 MAIN_YELLOW) + 숫자
  2. 효과음: 같음
  3. 닉네임: 기울어진 입력칸 380×68, `max_length = 10`, `n/10`

### 3.10 탭과 오른쪽 띠

- 탭 x = `panel_right_at(top) + 16` → 1703 / 1714 / 1725 (9° 기준). 128×56, 모서리 12, 테두리 4, 24px bold.
- 활성: 테두리 MAIN_INK, 배경 MAIN_YELLOW, 그림자 4px MAIN_BROWN. 비활성: 테두리 MAIN_INK, 배경 MAIN_PAPER.
- RightBand의 왼쪽 변은 선택창 오른쪽 변과 같은 선이다.
- `TabRail`은 크기·테두리가 없는 컨테이너다. 화면 위쪽에 띠가 생기지 않는다.

### 3.11 준비 화살표 (ReadyArrow)

- 꼭짓점 `(1910, 105.4)`, `(1838, 560)`, `(1910, 1014.6)` (`w = 72`, `half = 72 / TAN = 454.6`, 9° 기준).
- 두 빗변 기울기 |dx/dy| = TAN. 아래 빗변은 선택창 오른쪽 변과 평행, 둘 사이 가로 간격 약 66.8px.
- 테두리 6px, 세 변 모두, 이음점은 반지름 3 원으로 둥글게. 오른쪽 변은 화면 끝에서 절반이 잘린다.
- 색: `t = n / m` (m = 0이면 0, 1.1 정의). 채움 `MAIN_PAPER.lerp(MAIN_YELLOW, t)`, 테두리 `MAIN_INK`(고정) [제안].
- 훈련 모드: 숨김 [제안].

### 3.12 모달 문구

| kind | 제목 / 본문 | 버튼 |
|---|---|---|
| EXIT (참가자, 혼자인 호스트, 훈련) | 방에서 나가시겠습니까? | [취소] [나가기] |
| EXIT (다른 참가자가 있는 호스트) | 방에서 나가시겠습니까? / "방을 닫으면 모두 나가게 됩니다." | [취소] [나가기] |
| KICK | {닉네임}님을 강제 퇴장할까요? | [취소] [강제 퇴장](MAIN_INK 바탕, 흰 글자) |
| PROFILE | {닉네임} / 캐릭터 그림 240px, 캐릭터 이름, 준비 상태 | [닫기] |

### 3.13 훈련 모드에서 숨기는 것

채팅 힌트·말풍선, ⋯ 메뉴, 준비 칩, 준비 화살표, 방장 별, 방 이름 행, 최대 인원 행. 방 이름 상자에는 `UiStyle.TRAINING_ROOM` "훈련장" 고정 표시 [제안].

---

## 4. 이벤트/시그널 흐름 (로직 전용)

> 데이터와 상태 변경만 다룬다. 보이는 모습은 섹션 3. 표시 갱신은 `_refresh_view()` 한 곳에서만.

### 4.1 시그널 / 상수 / 변수

```gdscript
signal exit_requested(result: LobbyExitResult)
const BUBBLE_SECONDS: float = 3.0
const CHAT_MAX_LENGTH: int = 40
const CHAT_MIN_INTERVAL_MSEC: int = 500
const WHEEL_STEP_PX: float = 40.0              # [제안]
var flow: FlowState = FlowState.BROWSING
var active_tab: Tab = Tab.ROOM
var settings_view: SettingsView = SettingsView.ROOM
var modal_kind: ModalKind = ModalKind.NONE
var modal_target_id: int = 0
var menu_target_id: int = 0
var muted_ids: Dictionary = {}                 # int -> bool
var _bubbles: Dictionary = {}                  # int -> { "text": String, "left": float }
var _room_mode: ScreenTypes.RoomMode = ScreenTypes.RoomMode.ONLINE
```

### 4.2 `Session`에 추가할 것

**시그널·변수**: `signal chat_received(peer_id: int, text: String)`, `var room: RoomState`, `var match_setup: MatchSetup`(경기 시작 때 설정, 대기방 복귀 때 `null`), `var catalog: ContentCatalog = preload("res://resources/content_catalog.tres")`.

**공개 함수와 RPC.** 모든 `any_peer` RPC는 첫 줄에서 ① `multiplayer.is_server()` ② 보낸 사람이 `roster`에 있음 ③ 인자 타입·범위 ④ `phase == "lobby"`를 검사한다. 통과하면 호스트가 바꾸고 `_publish_lobby()`로 전원에게 보낸다. 훈련 모드는 RPC 없이 호스트 처리 함수를 직접 부른다(기존 `local_mode` 패턴).

| 공개 함수 | 호스트 쪽 RPC | 검증 / 처리 |
|---|---|---|
| `set_character(pick: StringName) -> void` | `_request_character(pick: StringName)` | 카탈로그 id 또는 (2종 이상일 때) `random`. 보낸 사람이 준비 완료면 거부 |
| `set_ready(value: bool) -> void` (기존) | `_request_ready` (기존) | 기존 그대로 |
| `update_room(patch: Dictionary) -> void` | `_request_room_update(patch: Dictionary)` | 보낸 사람이 1(호스트)일 때만. 키 `name`(String, ≤12자), `max_players`(int 2~4, ≥ 현재 인원), `map`(카탈로그 id 또는 random)만 허용. 그 외 키·타입은 무시 + `push_warning` |
| `set_display_name(value: String) -> void` | `_request_name(value: String)` | `clean_name()` (10자로 자름). `settings.cfg [player] name` 저장은 내 컴퓨터에서 |
| `send_chat(text: String) -> void` | `_request_chat(text: String)` → `_chat(peer_id: int, text: String)` (`authority`, `call_local`, reliable) | strip 후 1~40자, 줄바꿈 제거, 보낸 사람별 500ms 간격 |
| `kick(peer_id: int) -> void` | 대상에게 `_kicked()` RPC 후 `peer_disconnect_later()` | 호스트만, 대상 ≠ 1, `roster`에 있음. 재접속은 막지 않음 |
| `start_game() -> bool` (기존 확장) | `_begin_match` (기존, 인자에 `match_setup` dict 추가) | 훈련 모드는 인원·준비 검사 없이 허용. 시작 전 random을 호스트 RNG로 확정해 `MatchSetup` 생성 |
| `leave_room() -> void` (기존) | `_room_closed` (기존) | 그대로 |

- `_register`의 가득 참 판정: `MAX_PLAYERS`(4) 대신 `room.max_players`.
- 새 참가자 기본값: `character` = 카탈로그 첫 캐릭터, `is_ready = false`, 이름 = 보내 온 `settings.cfg` 이름.
- 채팅은 저장하지 않는다. 늦게 들어온 사람은 이전 채팅을 받지 않는다.

**새 `UiStyle` 문구**: `ROOM_UNNAMED` "이름 없는 방", `TRAINING_ROOM` "훈련장", `KICKED` "방에서 강제 퇴장되었습니다.", `CHAT_HINT` "T 채팅", `TAB_ROOM` "방", `TAB_CHARACTER` "캐릭터", `TAB_SETTINGS` "설정", 3.7·3.8·3.9·3.12의 메뉴·배너·모달 문구.

### 4.3 진입 / 공통

- `func enter(data: LobbyEnterData) -> void`
  - `_room_mode`, `active_tab = data.initial_tab`, `settings_view = ROOM`, `flow = BROWSING`, `muted_ids.clear()`
  - `Session.changed`, `Session.chat_received` 연결 (중복 검사)
  - `_rebuild_content()`, `_refresh_view()`
- `func _set_flow(next: FlowState) -> void` — `flow == LEAVING`이면 무시.
- `func _refresh_view() -> void` — `Session` 값과 4개 상태 축으로 섹션 3 표시를 모두 갱신. 로직 없음.
- `func _exit_to(route: Route, notice: String = "", setup: MatchSetup = null) -> void` — `_set_flow(LEAVING)` → `exit_requested.emit(...)`.

### 4.4 탭

- `func _on_tab_pressed(tab: Tab) -> void`
  - 조건: `flow == BROWSING`
  - 같은 탭이어도 그대로(토글 아님). `tab == SETTINGS and settings_view == MAP` → `settings_view = ROOM`
  - `active_tab = tab` → `_rebuild_content()`
- `func _rebuild_content() -> void` — `ContentHost` 기존 자식 `queue_free()`, 씬 1개 `instantiate()`. 스크롤 위치 초기화.
  - `CHARACTER` → CharacterGrid / `SETTINGS and settings_view == MAP and Session.is_host()` → MapGrid / `SETTINGS` → SettingsPanel (MAP이면 ROOM으로 표시) / 그 외 → PlayerList

### 4.5 준비 / 시작

- `func _on_ready_button_pressed() -> void`
  - 조건: `flow == BROWSING`
  - START → `_set_flow(STARTING)` → `Session.start_game()`이 `false`면 `_set_flow(BROWSING)`
  - IDLE → `Session.set_ready(true)` / READY → `Session.set_ready(false)` / START_DISABLED → 무시
- START_DISABLED tooltip: 인원 1명 `UiStyle.NEED_TWO`, 준비 안 된 사람 있음 `UiStyle.NEED_READY` (기존 문구)
- 캐릭터 그리드 배너의 [준비 해제] → `Session.set_ready(false)`

### 4.6 캐릭터 / 맵 선택

- `func _on_character_tile_selected(pick: StringName) -> void` — 온라인 참가자가 준비 완료면 무시. `Session.set_character(pick)`. 표시는 `Session.changed` 후 갱신(훈련은 즉시 반영됨).
- `func _on_map_button_pressed() -> void` — 호스트만. `settings_view = MAP` → `_rebuild_content()`
- `func _on_map_tile_selected(pick: StringName) -> void` — `Session.update_room({"map": pick})` → `settings_view = ROOM` → `_rebuild_content()`
- 맵 선택 취소: Esc 또는 [설정] 탭 다시 클릭 → `settings_view = ROOM`
- `func _on_grid_input(event: InputEvent) -> void` — `MOUSE_BUTTON_WHEEL_UP/DOWN` 한 칸 = ∓40px, `InputEventPanGesture`는 `delta.y × 40`. `offset`에 그대로 더함(이징 없음).

### 4.7 채팅 (온라인만)

- `func _unhandled_key_input(event: InputEvent) -> void`
  - T(`KEY_T`, `pressed`, `not echo`): `_room_mode == ONLINE`, `flow == BROWSING`이면 `_open_chat()` + `set_input_as_handled()`. 키를 먼저 소비하므로 입력칸에 't'가 들어가지 않는다 (2026-11-09 결정 3. 옛 키는 Enter)
  - Esc: `_on_escape()`
- `func _open_chat() -> void` — `_set_flow(CHAT_INPUT)`, 입력칸 비우고 포커스
- `func _on_chat_submitted(text: String) -> void` (`LineEdit.text_submitted`) — strip 결과가 있으면 `Session.send_chat(text)`. 이후 `_set_flow(BROWSING)`
- 입력칸 `focus_exited` / Esc → `_set_flow(BROWSING)`
- `func _on_chat_received(peer_id: int, text: String) -> void` — `muted_ids.has(peer_id)`면 무시. `_bubbles[peer_id] = {"text": text, "left": 3.0}`(이전 버블 교체)
- `_process(delta)`: 버블 `left -= delta`, 0 이하 삭제. 바뀐 것이 있을 때만 버블 표시 갱신. 버블이 없으면 `set_process(false)`.

### 4.8 플레이어 메뉴 / 모달

- `func _on_player_menu_pressed(peer_id: int) -> void` — 호스트, `flow == BROWSING` → `menu_target_id = peer_id`, `_set_flow(MENU_OPEN)`
- `func _on_player_action(action: PlayerAction, peer_id: int) -> void`
  - MUTE → `muted_ids` 토글, 음소거하면 그 사람 버블 즉시 삭제, `_set_flow(BROWSING)`
  - PROFILE / KICK → `modal_kind`, `modal_target_id = peer_id`, `_set_flow(MODAL_OPEN)`
- `func _on_back_pressed() -> void` — `flow == BROWSING` → `modal_kind = EXIT`, `_set_flow(MODAL_OPEN)`
- `func _on_modal_confirmed() -> void`
  - EXIT → `Session.leave_room()`. `Session.phase == "closing"`이 되면 CLOSING, `"menu"`가 되면 4.10 처리
  - KICK → 대상이 `roster`에 있으면 `Session.kick(modal_target_id)` → `modal_kind = NONE`, `_set_flow(BROWSING)`
- `func _on_modal_cancelled() -> void` — [취소]·[닫기], 배경 클릭, Esc → `modal_kind = NONE`, `_set_flow(BROWSING)`

### 4.9 기타

- `func _on_escape() -> void` — 하나만 처리, 우선순위: CHAT_INPUT 닫기 → MODAL 닫기 → MENU 닫기 → `settings_view == MAP`이면 ROOM → 그 외(`flow == BROWSING`) `_on_back_pressed()`로 나가기 확인 모달 (결정 3)
- 메뉴 바깥 클릭: 열린 상태에서 `get_global_rect().has_point()`가 거짓인 클릭이면 닫음
- `func _on_room_name_committed(text: String) -> void` — 입력칸 `text_submitted` 또는 `focus_exited` 때 `Session.update_room({"name": text})` (글자마다 보내지 않음) [제안]
- `func _on_max_players_pressed(value: int) -> void` — `Session.update_room({"max_players": value})`
- `func _on_nickname_committed(text: String) -> void` — `Session.set_display_name(text)` + `settings.cfg [player] name` 저장
- `func _on_pref_changed(key: StringName, value: int) -> void` — `prefs[key] = value`, `settings.cfg [audio]` 저장(메인 [설정]과 공유)

### 4.10 Session 반응

- `func _on_session_changed() -> void`
  - `Session.phase == "menu"` → `_exit_to(Route.START_GAME, Session.toast)` 후 `Session.toast = ""`. 토스트: 강퇴 `KICKED`, 방 닫힘 `ROOM_CLOSED`, 호스트 끊김 `HOST_LOST`, 직접 나감 `""`
  - `Session.phase == "playing"` → `_exit_to(Route.MATCH, "", Session.match_setup)` (모달·채팅이 열려 있어도 우선)
  - `Session.phase == "closing"` → `_set_flow(CLOSING)`
  - 메뉴·모달 대상이 `roster`에서 사라졌으면 닫고 `_set_flow(BROWSING)`
  - 내가 준비 완료면 캐릭터 그리드 잠금, 아니면 해제
  - `_refresh_view()`

### 4.11 핵심 플로우 요약

```
[준비]   참가자: ReadyButton → Session.set_ready(true) → 호스트 검증 → _publish_lobby → 전원 화면 갱신
[시작]   호스트: ReadyButton(START) → STARTING → Session.start_game() → random 확정·MatchSetup
		 → _begin_match(rpc) → 전원 phase = "playing" → exit(MATCH, match_setup)
[훈련]   ReadyButton(항상 START) → Session.start_game() (검사 생략) → exit(MATCH, room_mode = TRAINING)
[캐릭터] 타일 클릭 → Session.set_character → 호스트 검증(준비 완료면 거부) → 전원 갱신
[맵]     호스트: 설정 > 방 > 맵 그림 → MapGrid → 타일 → Session.update_room({map}) → 설정 > 방
[채팅]   T → 입력 → Enter → Session.send_chat → 호스트 검증 → _chat(rpc, call_local) → 전원 3초 말풍선
[강퇴]   호스트: ⋯ → 강제 퇴장 → 모달 확인 → Session.kick → 대상: _kicked → leave() → 게임하기 + 토스트
[나가기] ← 또는 Esc → 모달 → [나가기] → Session.leave_room() → 게임하기
```

### 4.12 키보드 조작 (2026-11-09 결정 3)

키보드만으로 이 화면의 모든 일을 할 수 있어야 한다. 섹션 3·4의 마우스 조작은 그대로 둔다.

| 키 | 동작 |
|---|---|
| J · Enter | 포커스가 있는 항목 확인(버튼 누름, 타일 선택). 글자 입력칸(방 이름, 닉네임, 채팅) 안에서는 Enter만 확인이고 J는 글자로 들어간다 |
| Esc | 4.9 `_on_escape()` 순서대로 하나만 닫는다. 닫을 것이 없으면 나가기 확인 모달 |
| T | 채팅 열기 (온라인, `flow == BROWSING`, 4.7) |
| 방향키 [제안] | 포커스 이동 |
| Q / E [제안] | 이전 / 다음 탭 |

- [제안] 들어오면 포커스는 ReadyButton. 순서는 ReadyButton → 현재 탭 내용(카드 ⋯ 버튼, 타일, 설정 행) → 탭 3개 → BackButton이며 `focus_neighbor_*`로 지정한다.
- [제안] SlantGrid: ↑/↓는 같은 열의 이전/다음 타일. 포커스 타일이 보이도록 `offset`을 한 칸(`pitch`)씩 즉시 옮긴다(이징 없음). ←/→는 옆 열.
- [제안] 모달: 처음 포커스는 [취소], ←/→로 버튼 이동.
- [제안] 포커스 표시: 4px `MAIN_YELLOW` 테두리. 애니메이션 없음.

---

## 5. 예외 처리 매트릭스

| 상황 | 조건 | UI 처리 | 로직 처리 |
|---|---|---|---|
| 준비 버튼 연타 | 응답 전 재클릭 | 마지막 요청 상태로 표시 | 매번 `set_ready(!현재값)` 전송, 호스트는 마지막 값 적용 |
| 시작 버튼 연타 | STARTING 중 재클릭 | 버튼 `disabled` | `flow != BROWSING`이면 무시, `start_game()`도 `phase != "lobby"`면 `false` |
| 시작 직전 준비 해제 | 호스트 클릭과 해제가 엇갈림 | START_DISABLED로 복귀 | 호스트 `can_start()` 재검사 실패 → `false` → BROWSING |
| 시작 직전 참가자 나감 | 클릭 직후 `peer_disconnected` | 인원 1명이면 START_DISABLED | 같음 |
| 준비 완료 상태 캐릭터 변경 | 잠금 중 / 조작된 RPC | 그리드 잠금 + 배너 | 화면 무시, 호스트도 거부 |
| 참가자의 방 설정 변경 시도 | 조작된 `_request_room_update` | 읽기 전용 표시 | 호스트가 보낸 사람 ≠ 1이면 무시 + `push_warning` |
| 최대 인원 < 현재 인원 | 4명일 때 [2명] | 칩 `disabled` | 호스트도 `max_players >= roster.size()` 검사 |
| 가득 찬 방에 접속 | `roster.size() >= room.max_players` | (접속자) "방이 가득 찼습니다." | `_register`가 FULL 거부 |
| 방 이름 빈 값 | 공백만 | "이름 없는 방" 표시 | `name = ""`, 표시 단계에서 대체 |
| 방 이름 13자 이상 | 붙여넣기 | 12자에서 멈춤 | `max_length = 12`, 호스트도 `left(12)` |
| 닉네임 빈 값 | 공백만 | "Player" | `clean_name()` |
| 채팅 빈 값 | Enter만 | 입력칸 닫힘 | 전송 안 함 |
| 채팅 41자 이상 | 붙여넣기 | 40자에서 멈춤 | `max_length = 40`, 호스트도 `left(40)` |
| 채팅 연타 | 500ms 안에 재전송 | 말풍선 갱신 없음 | 호스트가 보낸 사람별 시각 비교 후 무시 |
| 한글 조합 중 Enter | IME 조합 확정 Enter | 입력칸 유지 | `LineEdit` 기본 동작. **macOS·Windows에서 사람이 확인** |
| 음소거한 사람 채팅 | `muted_ids` 포함 | 말풍선 없음 | 로컬에서만 무시 |
| 플레이어 들어옴 / 나감 | `_lobby_state` 수신 | 카드 높이 재계산, 준비 n/m 갱신 | `_refresh_view()` |
| 메뉴·모달 대상이 나감 | 열린 상태에서 `roster`에서 사라짐 | 닫힘 | `_set_flow(BROWSING)` |
| 강퇴 대상이 이미 나감 | 확인 시 `roster`에 없음 | 모달 닫힘 | `kick()` 호출 안 함 |
| 내가 강퇴당함 | `_kicked` 수신 | 게임하기 + 토스트 "방에서 강제 퇴장되었습니다." | `leave()`, `toast = KICKED`. 재접속 허용 |
| 호스트 끊김 | `server_disconnected` | 게임하기 + 토스트 "호스트와의 연결이 끊어졌습니다." | 기존 `_server_left` |
| 호스트가 방 닫음 | `_room_closed` | 게임하기 + 토스트 "호스트가 방을 닫았습니다." | 기존 |
| 닫는 중 입력 | CLOSING (0.2초) | 모든 버튼 `disabled` | 핸들러 조기 반환 |
| 시작 시 모달·채팅 열림 | `phase == "playing"` 수신 | 닫히고 경기로 이동 | 전환 우선 |
| random 결과 불일치 | 피어마다 다른 무작위 | 해당 없음 | 호스트만 RNG, 결과는 `MatchSetup`으로 전달 |
| 알 수 없는 캐릭터·맵 id | 다른 버전 / 조작된 값 | 카탈로그 첫 항목으로 표시 | `from_dict()`·RPC 검증에서 카탈로그 검사, 실패 시 `push_warning` + 첫 항목 |
| 카탈로그가 비어 있음 | `characters` 또는 `maps`가 0개 | 해당 그리드에 "등록된 항목이 없습니다" [제안] | `push_error`, 시작 버튼 START_DISABLED |
| 휠 값이 매우 큼 | 빠른 연속 스크롤 | 정상 반복 | `fposmod`로 순환 |
| 창 비율이 16:9가 아님 | 와이드 모니터 등 | 1920×1080 스테이지 가운데, 남는 곳 MAIN_INK | `aspect = expand` + 가운데 배치 |
| 훈련 모드 시작 | 혼자 START | 즉시 경기로 | `start_game()`이 훈련 모드면 인원·준비 검사 생략 |
| 설정 파일 저장 실패 | `ConfigFile.save` ≠ OK | 표시 없음 | `push_warning`, 값은 이번 실행 동안만 유지 |

---

## [결정 필요 사항]

없음.

### 결정 기록

| # | 질문 | 결정 |
|---|---|---|
| 1 | 해상도 기준 | 게임 전체 1920×1080 (00·SYS-01도 변경) |
| 2 | 애니메이션 없음 범위 | 대기방에만 적용 |
| 3 | 색 체계 | ~~대기방은 회색 체계, 다른 화면은 기존 그대로~~ → 2026-11-09: 대기방을 포함한 모든 화면이 메인 메뉴 스타일(색·글꼴·9°)을 따른다. 애니메이션 없음(#2)은 유지 |
| 4 | 준비 규칙 | 현재 규칙(호스트는 준비 없음, 시작 버튼이 곧 준비) |
| 5 | 캐릭터 | 능력 없는 임시 캐릭터 1종만. 추가 시 선택칸에 자동 표시되는 틀 유지 |
| 6 | 맵 | 기존 맵 1개, 이름 TestMap. 나머지 삭제, 추가용 틀 유지 |
| 7 | 방장 양도 | 삭제 |
| 8 | 훈련장 | 시작 버튼 항상 활성. 대기방 설정은 일반과 같음. 치트 기능은 경기 화면 |
| 9 | 시작 카운트다운 | 대기방 것 삭제, 경기장 것만 |
| 10 | 공개/비공개 | ~~숨김~~ → 2026-11-09: 만들지 않는다. 모든 방은 공개 방이다 |
| 11 | 닉네임 수정 위치 | 대기방 개인 탭 + 메인 [설정] 둘 다 |
| 12 | 프로필 | 레벨·승리 수 없이 캐릭터·준비 상태만 |
| 13 | 배경음·효과음 | 대기방 개인 탭과 메인 [설정]이 같은 값 공유 |
| 14 | 강퇴 | 문구 "방에서 강제 퇴장되었습니다.", 재입장 막지 않음 |
| 15 | 채팅 연타 제한 | 0.5초 |
| 16 | 디버그 바 | 옮기지 않음 |
| 17 | 탭 위 20px 띠 | 없음, 배경으로 채움 |
| 18 | 닉네임 최대 글자 수 | 10자 (`clean_name()`도 20자 → 10자) |
| 19 | 맵 조건 | 없음 (삭제) |
| 20 | 키보드 조작 (2026-11-09) | 키보드만으로 모든 조작. 확인 J·Enter, 뒤로 Esc, 채팅 T (4.12) |
| 21 | 방 주소 공유 (2026-11-09) | 초대 코드·방 주소 표시·복사 모두 없음. (i) 버튼·주소 팝오버·[복사] 삭제 |
| 22 | 플레이어 표기 (2026-11-09) | 닉네임 우선: "닉네임 · P번호" + 슬롯 색 띠 |
