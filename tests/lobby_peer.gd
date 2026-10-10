extends SceneTree
## Two-process lobby checks: host closing the room and rejecting a join during a match.
## Run the host first: `-- host`, then `-- client` (port 27848).

const PORT: int = 27848
var session: Node
var role: String = "host"
var failures: int = 0
var began: int = 0
var stage: int = 0
var rejoin_at: int = 0

func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error("%s: %s" % [role, description])

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument == "client":
			role = "client"
	call_deferred("run")

func run() -> void:
	session = root.get_node("Session")
	session.changed.connect(func(): print("%s %d phase=%s err=%s toast=%s" % [role, Time.get_ticks_msec() - began, session.phase, session.join_error, session.toast]))
	began = Time.get_ticks_msec()
	if role == "host":
		check(session.host_game("Host", PORT) == OK, "Create room")
	else:
		check(session.join_address("127.0.0.1:%d" % PORT) == OK, "Join room")
	while Time.get_ticks_msec() - began < 20000:
		await process_frame
		if (host_tick() if role == "host" else client_tick()):
			break
	check(stage >= 3, "Reached final stage (stuck at %d)" % stage)
	print("Lobby %s checks complete: %d failures" % [role, failures])
	session.leave()
	quit(1 if failures > 0 else 0)

func host_tick() -> bool:
	if stage == 0 and session.roster.size() == 2:
		check(session.message == UiStyle.JOINED % 2, "Join notice names P2")
		# Give the client a moment in the lobby before closing it.
		rejoin_at = Time.get_ticks_msec() + 500
		stage = 4
	elif stage == 4 and Time.get_ticks_msec() >= rejoin_at:
		session.leave_room()
		stage = 1
	elif stage == 1 and session.phase == "menu":
		# Reopen and pretend a match is running so the next join is refused.
		check(session.host_game("Host", PORT) == OK, "Reopen room")
		session.phase = "playing"
		stage = 2
	elif stage == 2 and Time.get_ticks_msec() - began > 6000:
		check(session.roster.size() == 1, "Mid-match join never enters roster")
		stage = 3
		return true
	return false

func client_tick() -> bool:
	if stage == 0 and session.phase == "lobby":
		check(session.slot_of(session.multiplayer.get_unique_id()) == 2, "Client sees own slot")
		stage = 1
	elif stage == 1 and session.phase == "menu":
		check(session.toast == UiStyle.ROOM_CLOSED, "Room closed toast")
		stage = 2
		rejoin_at = Time.get_ticks_msec() + 1000
	elif stage == 2 and rejoin_at > 0 and Time.get_ticks_msec() >= rejoin_at:
		rejoin_at = 0
		session.join_address("127.0.0.1:%d" % PORT)
	elif stage == 2 and rejoin_at == 0 and session.phase == "menu" and not session.join_error.is_empty():
		check(session.join_error == UiStyle.IN_PROGRESS, "Mid-match join shows in-progress message (got %s)" % session.join_error)
		stage = 3
		return true
	return false
