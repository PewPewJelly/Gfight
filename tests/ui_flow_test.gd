extends SceneTree
## Screen flow checks for Docs/00–02: main menu → 게임하기 → 방 참여 popup → 대기방 (online and
## training) → 경기 → 결과, including the training dummy. Prints a short text picture of each
## main scene ("[장면] ...") for people reviewing the run.
## Screen scripts use the Session autoload, so they are only touched through untyped variables.

## settings.cfg keys this test changes; restored at the end so a run leaves no trace.
const TOUCHED_SETTINGS: Array[String] = ["player/name", "audio/bgm"]

var failures: int = 0
var session: Node
var router: Control
var saved_settings: Dictionary = {}

func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error(description)

func _initialize() -> void:
	call_deferred("run")

func frames(count: int) -> void:
	for index in range(count):
		await physics_frame
		await process_frame

func describe(title: String, lines: Array[String]) -> void:
	print("\n[장면] %s" % title)
	for line in lines:
		print("  - %s" % line)

func run() -> void:
	session = root.get_node("Session")
	var settings := ConfigFile.new()
	settings.load(session.SETTINGS_PATH)
	for entry in TOUCHED_SETTINGS:
		var parts := entry.split("/")
		saved_settings[entry] = settings.get_value(parts[0], parts[1]) if settings.has_section_key(parts[0], parts[1]) else null
	session.local_name = "Tester"
	router = load("res://main.tscn").instantiate()
	root.add_child(router)
	await frames(1)
	await check_main_menu()
	await check_start_game()
	await check_online_lobby()
	await check_training()
	session.leave()
	restore_settings()
	print("\nUI flow checks complete: %d failures" % failures)
	quit(1 if failures > 0 else 0)

func restore_settings() -> void:
	var settings := ConfigFile.new()
	settings.load(session.SETTINGS_PATH)
	for entry in TOUCHED_SETTINGS:
		var parts := entry.split("/")
		if saved_settings[entry] == null:
			if settings.has_section_key(parts[0], parts[1]):
				settings.erase_section_key(parts[0], parts[1])
		else:
			settings.set_value(parts[0], parts[1], saved_settings[entry])
	settings.save(session.SETTINGS_PATH)

# 메인 메뉴 -------------------------------------------------------------------------

func check_main_menu() -> void:
	var menu: Control = router.current
	check(router.current_id == ScreenTypes.ScreenId.MAIN_MENU, "Game opens on the main menu")
	check(menu.play_button.text == UiStyle.MENU_PLAY and not menu.play_button.disabled, "[게임하기] is available")
	check(menu.guidebook_button.disabled and menu.settings_button.disabled, "가이드북 / 설정 are not built yet")
	describe("메인 메뉴", [
		"제목: %s, 버전 표시: %s" % [menu.title_label.text, menu.version_label.text],
		"버튼: [%s] [%s](비활성, 툴팁 \"%s\") [%s](비활성) [%s]" % [menu.play_button.text, menu.guidebook_button.text,
			menu.guidebook_button.tooltip_text, menu.settings_button.text, menu.quit_button.text],
	])
	menu.play_button.pressed.emit()
	await frames(1)

# 게임하기 / 방 참여 ------------------------------------------------------------------

func check_start_game() -> void:
	var start: Control = router.current
	check(router.current_id == ScreenTypes.ScreenId.START_GAME, "[게임하기] opens 게임하기")
	check(start.state == start.ScreenState.IDLE and not start.real_sub_menu.visible, "게임하기 opens with 실전 collapsed")
	describe("게임하기 (처음)", [
		"왼쪽 위: (←) 뒤로가기, 위치 표시 \"%s\"" % start.location_label.text,
		"큰 버튼 2개: [%s](칼 아이콘) [%s](과녁 아이콘)" % [start.real_label.text, start.training_label.text],
		"실전 하위 버튼은 숨김 상태",
	])
	start._on_real_button_pressed()
	check(start.state == start.ScreenState.REAL_EXPANDED and start.real_sub_menu.visible, "실전 shows 방 참여 / 방 생성")
	describe("게임하기 (실전 펼침)", [
		"실전 아이콘이 강조색으로 바뀌고 아래에 [%s] [%s]이 나타남" % [start.join_room_button.text, start.create_room_button.text],
	])
	# Address parsing (Docs/01 §5).
	var parsed: Dictionary = session.parse_address("")
	check(parsed.ok and parsed.host == "127.0.0.1" and parsed.port == 27840, "Empty address uses local default")
	parsed = session.parse_address("192.168.0.5:30000")
	check(parsed.ok and parsed.host == "192.168.0.5" and parsed.port == 30000, "IP:port parses")
	parsed = session.parse_address("192.168.0.5")
	check(parsed.ok and parsed.port == 27840, "IP alone uses default port")
	for bad in ["1.2.3.4:abc", "1.2.3.4:70000", "a:b:c", ":27840"]:
		check(not session.parse_address(bad).ok, "Rejects bad address %s" % bad)
	session.last_address = ""
	start._on_join_room_pressed()
	check(start.join_popup.visible and start.state == start.ScreenState.JOIN_EDITING, "방 참여 opens the address popup")
	check(start.address_field.text == "%s:27840" % session.local_ipv4(), "Without a saved address the popup starts with this computer's IP:port")
	var first_address: String = start.address_field.text
	start.address_field.text = "1.2.3.4:abc"
	start._on_join_confirm_pressed()
	check(start.state == start.ScreenState.JOIN_INVALID and start.join_error_label.text == UiStyle.BAD_ADDRESS, "Bad address shows the format error")
	check(start.address_field.text == "1.2.3.4:abc", "Popup keeps the typed address after an error")
	describe("방 참여 팝업", [
		"제목 \"%s\", 주소 칸 처음 값 \"%s\" (전체 선택)" % [start.join_title.text, first_address],
		"버튼: [%s] [%s]" % [start.join_cancel_button.text, start.join_confirm_button.text],
		"\"1.2.3.4:abc\" 입력 후 확인 → 글자 빨강, 아래 오류 \"%s\" (네트워크 요청 없음)" % start.join_error_label.text,
	])
	start.address_field.text = "1.2.3.5"
	start.address_field.text_changed.emit("1.2.3.5")
	check(start.state == start.ScreenState.JOIN_EDITING and start.join_error_label.text.is_empty(), "Typing clears the error")
	start._on_join_cancel_pressed()
	check(not start.join_popup.visible, "취소 closes the popup")
	start._on_back_pressed()
	await frames(1)
	check(router.current_id == ScreenTypes.ScreenId.MAIN_MENU, "← returns to the main menu")
	router.current.play_button.pressed.emit()
	await frames(1)

# 대기방 (온라인) ----------------------------------------------------------------------

func check_online_lobby() -> void:
	var start: Control = router.current
	start._on_real_button_pressed()
	start._on_create_room_pressed()
	check(start.create_room_button.text == UiStyle.CREATING and start.create_room_button.disabled, "방 생성 shows 방을 만드는 중…")
	await frames(2)
	check(router.current_id == ScreenTypes.ScreenId.LOBBY, "방 생성 opens the lobby")
	var lobby: Control = router.current
	check(session.room.mode == ScreenTypes.RoomMode.ONLINE and session.is_host(), "Host owns an online room")
	check(lobby.room_name_label.text == UiStyle.ROOM_UNNAMED and lobby.info_button.visible, "Unnamed room shows 이름 없는 방 with (i)")
	check(lobby.ready_button_state() == lobby.ReadyButtonState.START_DISABLED and lobby.ready_button.tooltip_text == UiStyle.NEED_TWO, "Alone: start disabled, needs two")
	check(lobby.ready_chip.visible and lobby.my_host_star.visible and lobby.ready_arrow.visible, "Online host sees ready chip, star and arrow")
	check(lobby.my_nickname.text == "Tester" and lobby.chat_hint_button.visible, "My card shows my nickname; chat hint visible")
	lobby._on_info_pressed()
	check(lobby.info_popover.visible and lobby.address_label.text == session.room.address, "(i) shows the room address")
	describe("대기방 (온라인 방장, 혼자)", [
		"왼쪽 위: (←) + 방 이름 상자 \"%s\" (i), 칩 [맵 %s] [준비 0/0]" % [lobby.room_name_label.text, session.catalog.map_name(session.room.map)],
		"가운데 왼쪽: 내 캐릭터 그림(%s), 아래 카드: 캐릭터 이름 \"%s\", 닉네임 \"%s\" ★" % [session.room.player(1).character, lobby.my_character_name.text, lobby.my_nickname.text],
		"시작 버튼(▶ 금색, 40%% 흐림, 툴팁 \"%s\"), 왼쪽에 [%s] 알약" % [lobby.ready_button.tooltip_text, lobby.chat_hint_button.text],
		"오른쪽 기울어진 선택창: 점선 상자 \"%s\" / \"%s\"" % [UiStyle.INVITE_WAITING, UiStyle.INVITE_HINT],
		"오른쪽 띠: 탭 [방](활성) [캐릭터] [설정], 빨간 준비 화살표",
		"(i) 누름 → 주소 팝오버 \"%s\" + [%s]" % [lobby.address_label.text, lobby.copy_button.text],
	])
	lobby._on_info_pressed()
	check(not lobby.info_popover.visible, "(i) again closes the popover")
	# A participant joins (stand-in for a real peer: the host's room changes directly).
	var guest: Variant = PlayerData.create(5, "Guest", session.catalog.default_character())
	session.room.add_player(guest)
	session.room.notice = UiStyle.JOINED % session.room.slot_of(5)
	session._publish_lobby()
	check(lobby.toast.visible and lobby.toast_label.text == UiStyle.JOINED % 2, "Join notice shows as a toast")
	check(lobby.ready_button.tooltip_text == UiStyle.NEED_READY and lobby.ready_chip._value.text == "0/1", "Unready participant blocks start")
	check(lobby._content.card_layer.get_child_count() == 1, "Player list shows one card for the other player")
	guest.is_ready = true
	session._publish_lobby()
	check(lobby.ready_button_state() == lobby.ReadyButtonState.START and not lobby.ready_button.disabled, "All ready enables start")
	check(is_equal_approx(lobby._ready_ratio(), 1.0) and lobby.ready_chip._value.text == "1/1", "Ready arrow and chip reach 1/1")
	describe("대기방 (온라인 방장, 참가자 1명 준비 완료)", [
		"토스트(아래 가운데, 3초): \"%s\"" % UiStyle.JOINED % 2,
		"선택창: 흰 카드 1장 — 닉네임 \"Guest\", 캐릭터 이름, 오른쪽 아래 초록 O, 오른쪽 위 ⋯",
		"칩 [준비 1/1], 준비 화살표 초록, 시작 버튼 ▶ 진하게(툴팁 \"%s\")" % lobby.ready_button.tooltip_text,
	])
	# Chat: Enter opens my bubble input; the guest's line shows on the guest card.
	lobby._chat_closed_msec = -1000
	lobby._unhandled_key_input(_key(KEY_ENTER))
	check(lobby.flow == lobby.FlowState.CHAT_INPUT and lobby.chat_input.visible, "Enter opens the chat bubble input")
	lobby._on_chat_submitted("안녕하세요")
	check(lobby.flow == lobby.FlowState.BROWSING and lobby.my_bubble.visible, "Sent line shows above my character")
	lobby._unhandled_key_input(_key(KEY_ENTER))
	check(lobby.flow == lobby.FlowState.BROWSING, "Enter right after sending does not reopen the input")
	session._chat(5, "반가워요")
	check(lobby._bubbles.has(5), "Guest line shows on the guest card")
	lobby._on_player_menu_pressed(5)
	check(lobby.flow == lobby.FlowState.MENU_OPEN, "⋯ opens the player menu")
	lobby._on_player_action(lobby.PlayerAction.MUTE, 5)
	check(lobby.muted_ids.has(5) and not lobby._bubbles.has(5), "음소거 hides the guest's bubble")
	session._chat(5, "들리나요")
	check(not lobby._bubbles.has(5), "Muted guest's chat is not shown")
	lobby._on_player_menu_pressed(5)
	lobby._on_player_action(lobby.PlayerAction.PROFILE, 5)
	check(lobby.modal_layer.visible and lobby.modal_title.text == "Guest" and lobby._profile_state_label.text == UiStyle.STATE_READY, "프로필 보기 shows character and ready state")
	describe("대기방 (말풍선·메뉴·프로필)", [
		"Enter → 내 캐릭터 위 말풍선 입력칸(0/40), 보내면 3초 말풍선 \"안녕하세요\"",
		"Guest 말풍선은 Guest 카드 그림 오른쪽 위에 표시",
		"⋯ 메뉴: [%s] [%s] — [%s](빨강). 음소거하면 그 사람 말풍선 숨김, 카드에 음소거 아이콘" % [UiStyle.MENU_PROFILE, UiStyle.MENU_MUTE, UiStyle.MENU_KICK],
		"프로필 모달: 제목 \"Guest\", 캐릭터 그림 240px, \"%s\", \"%s\", [%s]" % [session.catalog.character_name(guest.character), lobby._profile_state_label.text, UiStyle.CLOSE],
	])
	lobby._unhandled_key_input(_key(KEY_ESCAPE))
	check(not lobby.modal_layer.visible and lobby.flow == lobby.FlowState.BROWSING, "Esc closes the modal")
	lobby._on_player_menu_pressed(5)
	lobby._on_player_action(lobby.PlayerAction.KICK, 5)
	check(lobby.modal_title.text == UiStyle.KICK_TITLE % "Guest", "강제 퇴장 asks for confirmation")
	lobby._on_modal_cancelled()
	# Tabs: character grid, settings, map picker.
	lobby._on_tab_pressed(lobby.Tab.CHARACTER)
	var grid: Control = lobby._content
	check(grid.kind == SelectTile.Kind.CHARACTER and grid._columns.size() == 1, "캐릭터 tab shows a one-column grid for one character")
	check(grid._tiles[0][0].selected == (grid._tiles[0][0].pick == session.room.player(1).character), "My character tile is marked")
	var before_offset: float = grid.offset
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	lobby._on_grid_input(wheel, grid)
	check(is_equal_approx(grid.offset, before_offset + lobby.WHEEL_STEP_PX), "Wheel scrolls the grid by 40px")
	lobby._on_tab_pressed(lobby.Tab.SETTINGS)
	check(lobby._content.has_method("refresh") and lobby._content._room_name_input != null, "설정 tab shows the room rows")
	lobby._on_room_name_committed("우리 방")
	check(session.room.name == "우리 방" and lobby.room_name_label.text == "우리 방", "Room name change shows in the header")
	lobby._on_max_players_pressed(3)
	check(session.room.max_players == 3, "Max players can be lowered to 3")
	lobby._on_map_button_pressed()
	check(lobby.settings_view == lobby.SettingsView.MAP and lobby._content.kind == SelectTile.Kind.MAP, "Map picture opens the map grid")
	lobby._content.tile_picked.emit(session.catalog.default_map())
	check(lobby.settings_view == lobby.SettingsView.ROOM and session.room.map == session.catalog.default_map(), "Picking a map returns to room settings")
	lobby._on_sub_tab_selected(1)
	lobby._on_nickname_committed("새닉네임입니다길어요오")
	check(session.room.player(1).display_name == "새닉네임입니다길어요" and lobby.my_nickname.text == "새닉네임입니다길어요", "Nickname is cut to 10 characters")
	lobby._on_pref_changed(&"bgm", 40)
	check(int(session.load_setting("audio", "bgm", 0)) == 40, "BGM volume is saved to settings.cfg")
	describe("대기방 (탭)", [
		"[캐릭터]: 기울어진 1열 그리드, \"%s\" 타일 반복, 선택 타일은 주황 점선 테두리, 휠 한 칸 40px" % session.catalog.character_name(session.catalog.default_character()),
		"[설정]>[방]: 방 이름 입력칸(n/12), 맵 그림 버튼, 최대 인원 칩 [2명][3명][4명] (현재 인원 미만은 비활성)",
		"맵 그림 누름 → 맵 1열 그리드(\"%s\" / TestMap), 고르면 [방] 설정으로 복귀" % session.catalog.map_name(session.catalog.default_map()),
		"[설정]>[개인]: 배경음·효과음 슬라이더(0~100), 닉네임 입력칸(n/10)",
	])
	lobby._on_tab_pressed(lobby.Tab.ROOM)
	lobby._on_back_pressed()
	check(lobby.modal_title.text == UiStyle.EXIT_TITLE and lobby.modal_body.get_child_count() == 1, "Host with a guest is warned the room closes")
	lobby._on_modal_cancelled()
	# Start → match → result → lobby.
	lobby._on_ready_button_pressed()
	await frames(1)
	check(session.phase == session.Phase.PLAYING and router.current_id == ScreenTypes.ScreenId.MATCH, "Start opens the match screen")
	var match_screen: Control = router.current
	match_screen.result_delay = 0.0
	var arena: FightArena = session.arena
	check(arena.fighters.size() == 2 and not arena.fighters[1].is_dummy, "Online match has the two players and no dummy")
	check(arena.countdown_left > 0.0 and match_screen.hud.visible, "Match opens with the countdown HUD")
	describe("경기 (온라인)", [
		"화면 아래 카드 띠: [P1 빨강 (나)] [P2 파랑], 각 0%, 목숨 3",
		"가운데 떠 있는 카운트다운 %d → 시작!" % ceili(arena.countdown_left),
	])
	await check_match_rules(arena)
	arena.fighters[1].stocks = 0
	arena.fighters[1].eliminated_frame = arena.frame
	arena._resolve_result()
	await frames(2)
	check(session.phase == session.Phase.RESULT and match_screen.result_panel.visible, "Result screen opens")
	check(match_screen.result_panel._title.text == UiStyle.WINS % 1, "Winner line names P1")
	describe("결과 (온라인)", [
		"제목 \"%s\" (P1 색)" % match_screen.result_panel._title.text,
		"슬롯별 열: 순위, 킬, 준 배율, 확인 상태 / 아래 \"%s\"" % match_screen.result_panel._hint.text,
	])
	match_screen._unhandled_key_input(_key(KEY_ENTER))
	check(session.phase == session.Phase.RESULT and session.confirmed.get(1, false), "Host confirmed; waits for the guest")
	session._record_confirm(5)
	await frames(1)
	check(session.phase == session.Phase.LOBBY and router.current_id == ScreenTypes.ScreenId.LOBBY, "Everyone confirmed: back to the lobby")
	lobby = router.current
	check(not session.room.player(5).is_ready and lobby.ready_button.tooltip_text == UiStyle.NEED_READY, "Readiness is cleared after the match")
	lobby._on_back_pressed()
	lobby._on_modal_confirmed()
	await frames(1)
	check(session.phase == session.Phase.MENU and router.current_id == ScreenTypes.ScreenId.START_GAME, "나가기 returns to 게임하기")

func check_match_rules(arena: FightArena) -> void:
	for fighter in arena.fighters:
		check(fighter.tag_emphasis, "Countdown enlarges start tags")
	var start_x: float = arena.fighters[0].position.x
	var provider := arena.input_provider
	arena.input_provider = func(_id: int) -> int: return 2
	arena._physics_process(0.5)
	check(is_equal_approx(arena.fighters[0].position.x, start_x), "Input ignored during countdown")
	arena._physics_process(arena.countdown_left + 0.01)
	check(is_zero_approx(arena.countdown_left) and not arena.fighters[0].tag_emphasis, "Countdown ends")
	arena.set_physics_process(false)
	for fighter in arena.fighters:
		fighter.set_physics_process(false)
	arena.input_provider = provider
	for fighter in arena.fighters:
		var on_surface := false
		for surface in arena.platforms:
			if is_equal_approx(fighter.position.y + Fighter.HALF_SIZE.y, surface.position.y):
				on_surface = true
		check(on_surface, "Random start stands on a platform")
	var entries: Array[Dictionary] = [{"id": 1, "out": 50}, {"id": 2, "out": -1}, {"id": 3, "out": 80}, {"id": 4, "out": 50}]
	var ranks := FightArena.compute_ranks(entries)
	check(ranks[2] == 1 and ranks[3] == 2 and ranks[1] == 3 and ranks[4] == 3, "Ranks follow elimination order with ties")

# 훈련장 ------------------------------------------------------------------------------

func check_training() -> void:
	var start: Control = router.current
	start._on_training_pressed()
	await frames(1)
	check(router.current_id == ScreenTypes.ScreenId.LOBBY and session.training_mode, "훈련장 opens a training lobby")
	var lobby: Control = router.current
	check(lobby.room_name_label.text == UiStyle.TRAINING_ROOM and not lobby.info_button.visible, "Training room name is fixed, no (i)")
	check(not lobby.ready_chip.visible and not lobby.ready_arrow.visible and not lobby.my_host_star.visible, "Training hides ready chip, arrow and star")
	check(lobby.ready_button_state() == lobby.ReadyButtonState.START and not lobby.ready_button.disabled, "Training start is always enabled")
	check(not lobby.chat_hint_button.visible, "No chat in training")
	lobby._unhandled_key_input(_key(KEY_ENTER))
	check(lobby.flow == lobby.FlowState.BROWSING, "Enter does not open chat in training")
	lobby._on_tab_pressed(lobby.Tab.SETTINGS)
	check(lobby._content._room_name_input == null and lobby._content._player_chips.is_empty(), "Training settings hide room name and max players")
	lobby._on_tab_pressed(lobby.Tab.ROOM)
	describe("대기방 (훈련장)", [
		"방 이름 상자 \"%s\" 고정, (i)·준비 칩·준비 화살표·방장 별·채팅 힌트 없음" % lobby.room_name_label.text,
		"선택창: 점선 상자 \"%s\"" % UiStyle.TRAINING_ALONE,
		"시작 버튼 ▶ 항상 활성(툴팁 \"%s\"). [설정]>[방]에는 맵 행만" % lobby.ready_button.tooltip_text,
	])
	lobby._on_ready_button_pressed()
	await frames(1)
	check(router.current_id == ScreenTypes.ScreenId.MATCH, "Training start opens the match like an online room")
	var match_screen: Control = router.current
	match_screen.result_delay = 0.0
	var arena: FightArena = session.arena
	var player: Fighter = arena.fighters[0]
	var dummy: Fighter = arena.fighters[1]
	check(arena.fighters.size() == 2 and dummy.is_dummy and not player.is_dummy, "Training match adds one dummy")
	check(dummy.tint == UiStyle.DUMMY_COLOR and dummy.stocks == 3, "Dummy is grey with 3 stocks")
	check(session.input_for(dummy.player_id) == 0, "Dummy receives no input")
	check(session.match_setup.dummy_ids.has(dummy.player_id), "MatchSetup lists the dummy")
	describe("경기 (훈련장)", [
		"내 캐릭터(P1 빨강)와 회색 허수아비가 발판 위 빈 자리에 무작위로 등장(서로 겹치지 않음), 허수아비 머리 위 표시 \"%s\"" % UiStyle.DUMMY,
		"아래 카드 띠: [P1 빨강 (나)] [%s], 카운트다운 후 시작" % UiStyle.DUMMY,
		"허수아비는 움직이지 않지만 맞으면 배율이 오르고 날아가며, 장외되면 다시 등장",
	])
	arena._physics_process(arena.countdown_left + 0.01)
	arena.set_physics_process(false)
	for fighter in arena.fighters:
		fighter.set_physics_process(false)
	player.reset_round(Vector2(400, 250))
	dummy.reset_round(Vector2(455, 250))
	player.facing = 1.0
	player.simulate(1.0 / 60.0, 16)
	arena._resolve_attacks()
	check(dummy.percent > 0.0 and dummy.last_attacker_id == player.player_id and dummy.velocity.x > 0.0, "Hitting the dummy raises its percent and knocks it back")
	check(is_equal_approx(player.dealt_percent, dummy.percent), "Damage dealt to the dummy is recorded")
	dummy.ring_out()
	check(player.kills == 1 and dummy.stocks == 2 and dummy.life_state == Fighter.LifeState.WAITING, "Dummy ring-out gives a kill and costs a stock")
	check(dummy.respawn(Vector2(640, 200)) and dummy.life_state == Fighter.LifeState.ACTIVE, "Dummy respawns")
	dummy.ring_out()
	dummy.respawn(Vector2(640, 200))
	dummy.ring_out()
	check(dummy.life_state == Fighter.LifeState.ELIMINATED, "Dummy is out after three ring-outs")
	dummy.eliminated_frame = arena.frame
	arena._resolve_result()
	await frames(2)
	check(session.phase == session.Phase.RESULT and match_screen.result_panel.visible, "Training result opens")
	check(match_screen.result_panel._title.text == UiStyle.WINS % 1, "Player wins against the dummy")
	describe("결과 (훈련장)", [
		"제목 \"%s\", 열 2개(P1 1위 킬 3 / 허수아비 2위)" % match_screen.result_panel._title.text,
		"Enter → 바로 훈련장 대기방으로 복귀 (혼자라 기다리지 않음)",
	])
	match_screen._unhandled_key_input(_key(KEY_ENTER))
	await frames(1)
	check(session.phase == session.Phase.LOBBY and router.current_id == ScreenTypes.ScreenId.LOBBY and session.training_mode, "Enter returns to the training lobby")
	lobby = router.current
	lobby._on_back_pressed()
	check(lobby.modal_body.get_child_count() == 0, "Training exit has no close-room warning")
	lobby._on_modal_confirmed()
	await frames(1)
	check(router.current_id == ScreenTypes.ScreenId.START_GAME and session.phase == session.Phase.MENU, "Leaving training returns to 게임하기")

func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = true
	return event
