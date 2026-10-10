extends SceneTree
## Screen flow checks for Design/ui-ux-scenes-v2.pdf (S1, S1-1, S2, S3, S4).

var failures: int = 0

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

func run() -> void:
	var session = root.get_node("Session")
	var main = load("res://main.tscn").instantiate()
	main.result_delay = 0.0
	root.add_child(main)
	await frames(1)
	# S1: three buttons, version label, first focus on join.
	check(main.menu.visible and not main.join_popup.visible, "S1 opens without popup")
	check(main.join_button.has_focus(), "S1 first focus is 게임 참여")
	# S1-1 address parsing.
	var parsed: Dictionary = session.parse_address("")
	check(parsed.ok and parsed.host == "127.0.0.1" and parsed.port == 27840, "Empty address uses local default")
	parsed = session.parse_address("192.168.0.5:30000")
	check(parsed.ok and parsed.host == "192.168.0.5" and parsed.port == 30000, "IP:port parses")
	parsed = session.parse_address("192.168.0.5")
	check(parsed.ok and parsed.port == 27840, "IP alone uses default port")
	for bad in ["1.2.3.4:abc", "1.2.3.4:70000", "a:b:c", ":27840"]:
		check(not session.parse_address(bad).ok, "Rejects bad address %s" % bad)
	main._open_join()
	check(main.join_popup.visible, "게임 참여 opens popup over S1")
	main.address_field.text = "1.2.3.4:abc"
	main._submit_join()
	check(main.join_popup.visible and main.join_error_label.text == UiStyle.BAD_ADDRESS, "Format error stays in popup with message")
	check(main.address_field.text == "1.2.3.4:abc", "Popup keeps typed address after error")
	main._cancel_join()
	check(not main.join_popup.visible and main.menu.visible, "Cancel closes popup")
	# S2 lobby readiness gating (offline peer acts as host).
	session.roster = {1: "Host", 5: "Guest"}
	session.ready_states = {5: false}
	session.phase = "lobby"
	session.changed.emit()
	check(main.lobby.visible and not session.can_start(), "Host cannot start while a participant is not ready")
	check(main.hint_label.text == UiStyle.NEED_READY and main.start_button.disabled, "Start button explains missing readiness")
	session.ready_states[5] = true
	session.changed.emit()
	check(session.can_start() and not main.start_button.disabled and main.hint_label.text.is_empty(), "All ready enables start")
	session.roster = {1: "Host"}
	session.ready_states = {}
	session.changed.emit()
	check(not session.can_start() and main.hint_label.text == UiStyle.NEED_TWO, "One player cannot start")
	session.leave()
	# S3: countdown blocks input, then the match runs.
	session.local_game()
	check(session.start_game(), "Local match starts")
	var arena: FightArena = session.arena
	check(arena.countdown_left > 0.0 and main.hud.visible, "Match opens with countdown HUD")
	for fighter in arena.fighters:
		check(fighter.tag_emphasis, "Countdown enlarges start tags")
	var start_x: float = arena.fighters[0].position.x
	arena.input_provider = func(_id: int) -> int: return 2
	arena._physics_process(0.5)
	check(is_equal_approx(arena.fighters[0].position.x, start_x), "Input ignored during countdown")
	arena._physics_process(arena.countdown_left + 0.01)
	check(is_zero_approx(arena.countdown_left) and not arena.fighters[0].tag_emphasis, "Countdown ends")
	arena.set_physics_process(false)
	for fighter in arena.fighters:
		fighter.set_physics_process(false)
	arena.input_provider = func(_id: int) -> int: return 0
	# Random starts touch a platform and do not overlap.
	for fighter in arena.fighters:
		var on_surface := false
		for surface in arena.platforms:
			if is_equal_approx(fighter.position.y + Fighter.HALF_SIZE.y, surface.position.y):
				on_surface = true
		check(on_surface, "Random start stands on a platform")
	# Statistics: dealt percent and kill credit to last attacker.
	var p1 := arena.fighters[0]
	var p2 := arena.fighters[1]
	p1.position = Vector2(400, 250)
	p2.position = Vector2(455, 250)
	p1.facing = 1.0
	p1.simulate(1.0 / 60.0, 16)
	arena._resolve_attacks()
	check(is_equal_approx(p1.dealt_percent, 12.0) and p2.last_attacker_id == p1.player_id, "Hit records dealt percent and attacker")
	p2.ring_out()
	check(p1.kills == 1 and p2.last_attacker_id == 0, "Ring-out credits last attacker once")
	p1.ring_out()
	check(p2.kills == 0, "Self ring-out without attacker gives no kill")
	# S4 ranks: winner 1st, later eliminations rank higher, simultaneous share.
	var entries: Array[Dictionary] = [{"id": 1, "out": 50}, {"id": 2, "out": -1}, {"id": 3, "out": 80}, {"id": 4, "out": 50}]
	var ranks := FightArena.compute_ranks(entries)
	check(ranks[2] == 1 and ranks[3] == 2 and ranks[1] == 3 and ranks[4] == 3, "Ranks follow elimination order with ties")
	entries = [{"id": 1, "out": 90}, {"id": 2, "out": 90}]
	ranks = FightArena.compute_ranks(entries)
	check(ranks[1] == 1 and ranks[2] == 1, "Draw shares first place")
	p2.stocks = 0
	p2.eliminated_frame = arena.frame
	arena._resolve_result()
	await frames(2)
	check(session.phase == "result" and main.result_panel.visible, "Result screen opens")
	check(main.result_panel._title.text == UiStyle.WINS % 1, "Winner line names P1")
	main._unhandled_key_input(_enter())
	check(session.phase == "lobby" and main.lobby.visible, "Enter confirms and returns to lobby")
	session.leave()
	print("UI flow checks complete: %d failures" % failures)
	quit(1 if failures > 0 else 0)

func _enter() -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_ENTER
	event.pressed = true
	return event
