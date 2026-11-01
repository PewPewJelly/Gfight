class_name UiStyle
extends RefCounted
## Single place for UI colors and copy (Docs/00 §2.1-5). Screen copy follows Docs/01 and
## Docs/02; match HUD and result copy follow Design/ui-ux-scenes-v2.pdf.

const BACKGROUND := Color("101927")
const PANEL := Color("223147")
const PANEL_MUTED := Color("2b3446")
const ACCENT := Color("4f7cff")
const ERROR := Color("ff5a5a")
const READY := Color("4fc98a")
const TEXT := Color("e8eef7")
const TEXT_DIM := Color("8d9bb0")
const DIMMER := Color(0, 0, 0, 0.65)
const BOLD_FONT: FontVariation = preload("res://resources/fonts/bold_font.tres")
const BLACK_FONT: FontVariation = preload("res://resources/fonts/black_font.tres")
## Slot colors are shared by HUD cards, fighters and result columns.
const SLOT_COLORS: Array[Color] = [Color("e05555"), Color("4f7cff"), Color("3aa865"), Color("e3b23c")]
const SLOT_COLOR_NAMES: Array[String] = ["빨강", "파랑", "초록", "노랑"]
## Training dummy fighter (neutral so it never looks like a player slot).
const DUMMY_COLOR := Color("b9b9b9")
## [제안] Danger tint: white at 0%, orange at DANGER_MID, red at DANGER_HIGH.
const DANGER_MID_PERCENT: float = 100.0
const DANGER_HIGH_PERCENT: float = 200.0
const DANGER_MID := Color("ff9a3c")
const DANGER_HIGH := Color("ff4a4a")

# Lobby grey palette (Docs/02 §3.4). Other screens keep the navy palette above.
const LOBBY_BG := Color("a9a9a9")
const LOBBY_OUTSIDE := Color("262626")
const LOBBY_LINE := Color("555555")
const LOBBY_LINE_DARK := Color("2e2e2e")
const LOBBY_PANEL := Color("4a4a4a")
const LOBBY_PANEL_LINE := Color("3a3a3a")
const LOBBY_BAND := Color("7a7a7a")
const LOBBY_CARD := Color("f4f4f4")
const LOBBY_CHIP := Color("4e4e4e")
const LOBBY_GOLD_BG := Color("ffe9a8")
const LOBBY_GOLD := Color("d9a21a")
const LOBBY_GOLD_SHADOW := Color("b98a0a")
const LOBBY_ORANGE := Color("f5a040")
const LOBBY_RED := Color("e8503a")
const LOBBY_RED_BG := Color("fadad4")
const LOBBY_RED_SHADOW := Color("b83a28")
const LOBBY_GREEN := Color("5e9f2e")
const LOBBY_GREEN_BG := Color("d4efc2")
const LOBBY_START := Color("b98a0a")
const LOBBY_START_BG := Color("f7c948")
const LOBBY_START_SHADOW := Color("8a6600")
const LOBBY_READY_BG := Color("dcdcdc")
const LOBBY_TAB_IDLE := Color("f1f1f1")
const LOBBY_READ_ONLY := Color("e2e2e2")
const LOBBY_TEXT := Color("222222")
const LOBBY_TEXT_DIM := Color("7a7a7a")
const LOBBY_NAME_DIM := Color("6b6b6b")
const LOBBY_PICKED_TEXT := Color("e07a1f")
const LOBBY_PICKED_MAP_TEXT := Color("ffc27a")
const LOBBY_BANNER := Color("2b2b2b")
const LOBBY_SLIDER := Color("e0a820")
const LOBBY_DIMMER := Color(0.102, 0.102, 0.102, 0.5)

# Main menu (SYS-00 not written yet: buttons from Docs/01 decision 1).
const TITLE := "Gfight"
const MENU_PLAY := "게임하기"
const MENU_GUIDEBOOK := "가이드북"
const MENU_SETTINGS := "설정"
const QUIT := "게임 종료"
const COMING_SOON := "준비 중입니다."

# SYS-01 게임하기 (Docs/01 §3.1).
const PLAY_TITLE := "게임하기"
const MODE_REAL := "실전"
const MODE_TRAINING := "훈련장"
const JOIN_ROOM := "방 참여"
const CREATE_ROOM := "방 생성"
const JOIN_ADDRESS_TITLE := "방 주소 입력"
const CONFIRM := "확인"
const CANCEL := "취소"
const CREATING := "방을 만드는 중…"
const CONNECTING := "접속 중…"
const CREATE_FAILED := "방을 생성할 수 없습니다."
const HOST_LOST := "호스트와의 연결이 끊어졌습니다."
const ROOM_CLOSED := "호스트가 방을 닫았습니다."
const BAD_ADDRESS := "주소 형식이 올바르지 않습니다."
const NOT_FOUND := "해당 주소의 게임을 찾을 수 없습니다."
const ROOM_FULL := "방이 가득 찼습니다."
const IN_PROGRESS := "이미 경기가 진행 중입니다."
const VERSION_MISMATCH := "게임 버전이 다릅니다."

# SYS-02 대기방 (Docs/02 §3, §4.2).
const ROOM_UNNAMED := "이름 없는 방"
const TRAINING_ROOM := "훈련장"
const COPY := "복사"
const COPIED := "복사됨"
const KICKED := "방에서 강제 퇴장되었습니다."
const CHAT_HINT := "Enter 채팅"
const TAB_ROOM := "방"
const TAB_CHARACTER := "캐릭터"
const TAB_SETTINGS := "설정"
const MAP_CHIP_LABEL := "맵 "
const READY_CHIP_LABEL := "준비 "
const READY_CHIP_VALUE := "%d/%d"
const TIP_READY := "준비하기"
const TIP_UNREADY := "준비 해제"
const TIP_START := "게임 시작"
const NEED_TWO := "2명 이상이 모여야 시작할 수 있습니다."
const NEED_READY := "모든 참가자가 준비를 마쳐야 시작할 수 있습니다."
const HOST_LABEL := "방장"
const HOST_ONLY := "방장만 사용할 수 있어요"
const MENU_PROFILE := "프로필 보기"
const MENU_MUTE := "음소거"
const MENU_UNMUTE := "음소거 해제"
const MENU_KICK := "강제 퇴장"
const INVITE_WAITING := "초대 대기 중…"
const INVITE_HINT := "ⓘ 버튼으로 방 주소를 공유해 보세요"
const TRAINING_ALONE := "훈련 모드 · 혼자 연습합니다"
const READY_LOCKED := "준비 완료 상태에서는 캐릭터를 바꿀 수 없어요"
const UNREADY := "준비 해제"
const EMPTY_CATALOG := "등록된 항목이 없습니다"
const RANDOM_NAME := "랜덤"
const SUB_TAB_ROOM := "방"
const SUB_TAB_PERSONAL := "개인"
const READ_ONLY := "읽기 전용 · 방장만 수정할 수 있어요"
const ROW_ROOM_NAME := "방 이름"
const ROW_ROOM_NAME_DESC := "참가자에게 보이는 이름입니다."
const ROW_MAP := "맵 설정"
const ROW_MAP_DESC := "그림을 눌러 맵을 고릅니다."
const ROW_MAX_PLAYERS := "최대 인원"
const ROW_MAX_PLAYERS_DESC := "현재 인원 미만 선택 불가"
const PLAYER_COUNT_CHIP := "%d명"
const ROW_BGM := "배경음"
const ROW_SFX := "효과음"
const ROW_VOLUME_DESC := "0~100"
const ROW_NICKNAME := "닉네임"
const ROW_NICKNAME_DESC := "최대 10자"
const LENGTH_COUNTER := "%d/%d"
const EXIT_TITLE := "방에서 나가시겠습니까?"
const CLOSE_ROOM_CONFIRM := "방을 닫으면 모두 나가게 됩니다."
const LEAVE := "나가기"
const KICK_TITLE := "%s님을 강제 퇴장할까요?"
const CLOSE := "닫기"
const STATE_READY := "준비 완료"
const STATE_NOT_READY := "준비 안 함"
const JOINED := "P%d 님이 들어왔습니다."
const LEFT := "P%d 님이 나갔습니다."

# Match HUD and result (Design/ui-ux-scenes-v2.pdf; no Docs spec yet).
const DUMMY := "허수아비"
const GO := "시작!"
const ME_TAG := "(나)"
const ME_MARK := "▼나"
const RESPAWNING := "재등장 %d"
const ELIMINATED := "탈락"
const DISCONNECTED := "연결 끊김"
const SPECTATING := "탈락했습니다. 관전 중"
const WINS := "P%d 승리!"
const DUMMY_WINS := "허수아비 승리!"
const DRAW := "무승부"
const RANK := "%d위"
const CROWN := "♛ "
const KILLS := "킬"
const DEALT := "준 배율"
const CONFIRMED := "✔ 확인 완료"
const STATE_WAITING := "대기 중"
const LEFT_RESULT := "나감"
const CONFIRM_HINT := "Enter를 눌러 확인   (확인 완료 %d / %d)"



static func slot_color(slot: int) -> Color:
	return SLOT_COLORS[(slot - 1) % SLOT_COLORS.size()]


static func slot_title(slot: int) -> String:
	return "P%d %s" % [slot, SLOT_COLOR_NAMES[(slot - 1) % SLOT_COLOR_NAMES.size()]]


static func danger_color(percent: float) -> Color:
	if percent <= DANGER_MID_PERCENT:
		return TEXT.lerp(DANGER_MID, clampf(percent / DANGER_MID_PERCENT, 0.0, 1.0))
	return DANGER_MID.lerp(DANGER_HIGH, clampf((percent - DANGER_MID_PERCENT) / (DANGER_HIGH_PERCENT - DANGER_MID_PERCENT), 0.0, 1.0))


static func box(color: Color, border: Color = Color.TRANSPARENT, border_width: int = 0, radius: int = 10) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style


## Bold (0.6) or black (1.0) weight of the default font; the default font has one weight.
## Kept as resources: a static cache here kept this script alive at exit (leak report).
static func bold_font(strength: float = 0.6) -> Font:
	return BLACK_FONT if strength >= 1.0 else BOLD_FONT
