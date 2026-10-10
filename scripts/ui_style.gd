class_name UiStyle
extends RefCounted
## Single place for UI colors and copy. Text follows Design/match-flow-scene-ux.md §7
## and Design/ui-ux-scenes-v2.pdf; edit both together.

const BACKGROUND := Color("101927")
const PANEL := Color("223147")
const PANEL_MUTED := Color("2b3446")
const ACCENT := Color("4f7cff")
const ERROR := Color("ff5a5a")
const READY := Color("4fc98a")
const TEXT := Color("e8eef7")
const TEXT_DIM := Color("8d9bb0")
const DIMMER := Color(0, 0, 0, 0.65)
## Slot colors are shared by lobby slots, HUD cards, fighters and result columns.
const SLOT_COLORS: Array[Color] = [Color("e05555"), Color("4f7cff"), Color("3aa865"), Color("e3b23c")]
const SLOT_COLOR_NAMES: Array[String] = ["빨강", "파랑", "초록", "노랑"]
## [제안] Danger tint: white at 0%, orange at DANGER_MID, red at DANGER_HIGH.
const DANGER_MID_PERCENT: float = 100.0
const DANGER_HIGH_PERCENT: float = 200.0
const DANGER_MID := Color("ff9a3c")
const DANGER_HIGH := Color("ff4a4a")

const TITLE := "Gfight"
const JOIN := "게임 참여"
const CREATE := "게임 생성"
const QUIT := "게임 종료"
const CREATING := "방을 만드는 중…"
const CREATE_FAILED := "방을 생성할 수 없습니다."
const HOST_LOST := "호스트와의 연결이 끊어졌습니다."
const ROOM_CLOSED := "호스트가 방을 닫았습니다."
const ADDRESS := "주소"
const JOIN_CONFIRM := "참여"
const CANCEL := "취소"
const CONNECTING := "접속 중…"
const BAD_ADDRESS := "주소 형식이 올바르지 않습니다."
const NOT_FOUND := "해당 주소의 게임을 찾을 수 없습니다."
const ROOM_FULL := "방이 가득 찼습니다."
const IN_PROGRESS := "이미 경기가 진행 중입니다."
const VERSION_MISMATCH := "게임 버전이 다릅니다."
const LOBBY := "대기실"
const ROOM_ADDRESS := "방 주소 %s"
const COPY := "복사"
const HOST_TAG := "(호스트)"
const ME_TAG := "(나)"
const EMPTY_SLOT := "빈 자리"
const STATE_HOST := "호스트"
const STATE_READY := "✔ 준비 완료"
const STATE_WAITING := "대기 중"
const PLAYER_COUNT := "참가 인원 %d / %d"
const READY_COUNT := "준비 %d / %d"
const STOCK_RULE := "스톡 %d"
const LEAVE := "나가기"
const READY_BUTTON := "준비 완료"
const START := "경기 시작"
const STARTING := "시작하는 중…"
const NEED_TWO := "2명 이상이 모여야 시작할 수 있습니다."
const NEED_READY := "모든 참가자가 준비를 마쳐야 시작할 수 있습니다."
const PRESS_READY := "준비가 되면 [준비 완료]를 눌러 주세요."
const WAIT_OTHERS := "다른 참가자를 기다리는 중…"
const WAIT_HOST := "호스트가 시작하기를 기다리는 중…"
const CLOSE_ROOM_CONFIRM := "방을 닫으면 모두 나가게 됩니다."
const JOINED := "P%d 님이 들어왔습니다."
const LEFT := "P%d 님이 나갔습니다."
const GO := "시작!"
const ME_MARK := "▼나"
const RESPAWNING := "재등장 %d"
const ELIMINATED := "탈락"
const DISCONNECTED := "연결 끊김"
const SPECTATING := "탈락했습니다. 관전 중"
const WINS := "P%d 승리!"
const DRAW := "무승부"
const RANK := "%d위"
const CROWN := "♛ "
const KILLS := "킬"
const DEALT := "준 배율"
const CONFIRMED := "✔ 확인 완료"
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
