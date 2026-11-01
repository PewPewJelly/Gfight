extends SceneTree
## Two-process lobby checks (Docs/02): join notice, nickname and chat over RPC, the chat rate
## limit, host-only room settings, kick and rejoin, the host closing the room and a join refused
## during a match. Run the host first: `-- host`, then `-- client` (port 27848).

const PORT: int = 27848
var session: Node
var role: String = "host"
var failures: int = 0
var began: int = 0
var stage: int = 0
var wait_until: int = 0
var remote_id: int = 0
var notices: Array[String] = []
var chats: Array[String] = []
## The client renames itself; its saved nickname is put back at the end.
var saved_name: String = ""

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
	saved_name = session.local_name
	session.changed.connect(_on_changed)
	session.chat_received.connect(func(peer_id: int, text: String) -> void: chats.append("%d:%s" % [peer_id, text]))
	began = Time.get_ticks_msec()
	if role == "host":
		check(session.host_game("Host", PORT) == OK, "Create room")
	else:
		check(session.join_address("127.0.0.1:%d" % PORT, "Client") == OK, "Join room")
	while Time.get_ticks_msec() - began < 25000:
		await process_frame
		if (host_tick() if role == "host" else client_tick()):
			break
	check(stage >= 6, "Reached final stage (stuck at %d)" % stage)
	print("Lobby %s checks complete: %d failures" % [role, failures])
	session.leave()
	session.save_setting("player", "name", saved_name)
	quit(1 if failures > 0 else 0)

## The host clears room.notice after publishing, so notices are collected as they appear.
func _on_changed() -> void:
	print("%s %d phase=%s players=%s err=%s toast=%s notice=%s" % [role, Time.get_ticks_msec() - began, session.phase,
		session.room.ids(), session.join_error, session.toast, session.room.notice])
	if not session.room.notice.is_empty() and (notices.is_empty() or notices.back() != session.room.notice):
		notices.append(session.room.notice)

func host_tick() -> bool:
	var now := Time.get_ticks_msec()
	if stage == 0 and session.room.players.size() == 2:
		remote_id = session.room.ids()[1]
		check(notices.has(UiStyle.JOINED % 2), "Join notice names P2")
		stage = 1
	elif stage == 1:
		var guest = session.room.player(remote_id)
		if guest != null and guest.display_name == "손님" and chats.has("%d:안녕" % remote_id):
			wait_until = now + 800
			stage = 2
	elif stage == 2 and now >= wait_until:
		check(not chats.has("%d:두번째" % remote_id), "Second chat within 0.5 s is dropped")
		check(session.room.name.is_empty(), "Room update from a participant is ignored")
		session.kick(remote_id)
		stage = 3
	elif stage == 3 and session.room.players.size() == 1:
		check(notices.back() == UiStyle.LEFT % 2, "Leave notice names P2")
		stage = 4
	elif stage == 4 and session.room.players.size() == 2:
		# Kicked players may come back (Docs/02 decision 14). Then the host closes the room.
		wait_until = now + 500
		stage = 5
	elif stage == 5 and now >= wait_until and session.phase == session.Phase.LOBBY:
		session.leave_room()
		check(session.phase == session.Phase.CLOSING, "Host with a guest closes the room in two steps")
		stage = 6
	elif stage == 6 and session.phase == session.Phase.MENU:
		# Reopen and pretend a match is running so the next join is refused.
		check(session.host_game("Host", PORT) == OK, "Reopen room")
		session.phase = session.Phase.PLAYING
		wait_until = now + 4000
		stage = 7
	elif stage == 7 and now >= wait_until:
		check(session.room.players.size() == 1, "Mid-match join never enters the room")
		return true
	return false

func client_tick() -> bool:
	var now := Time.get_ticks_msec()
	if stage == 0 and session.phase == session.Phase.LOBBY:
		var my_id: int = session.multiplayer.get_unique_id()
		check(session.slot_of(my_id) == 2, "Client sees own slot")
		check(session.room.notice == UiStyle.JOINED % 2, "Client receives the join notice")
		check(not session.is_host() and session.room.address == "127.0.0.1:%d" % PORT, "Client keeps the address it joined")
		session.set_display_name("손님")
		session.send_chat("안녕")
		session.send_chat("두번째")
		session._request_room_update.rpc_id(1, {"name": "hack"})
		stage = 1
	elif stage == 1 and session.phase == session.Phase.MENU:
		check(session.toast == UiStyle.KICKED, "Kicked toast (got %s)" % session.toast)
		check(chats.size() == 1 and chats[0].ends_with(":안녕"), "Client saw exactly one accepted chat line (%s)" % [chats])
		session.toast = ""
		wait_until = now + 500
		stage = 2
	elif stage == 2 and now >= wait_until:
		check(session.join_address("127.0.0.1:%d" % PORT, "Client") == OK, "Rejoin after kick")
		stage = 3
	elif stage == 3 and session.phase == session.Phase.LOBBY:
		stage = 4
	elif stage == 4 and session.phase == session.Phase.MENU:
		check(session.toast == UiStyle.ROOM_CLOSED, "Room closed toast")
		wait_until = now + 1000
		stage = 5
	elif stage == 5 and wait_until > 0 and now >= wait_until:
		wait_until = 0
		session.join_address("127.0.0.1:%d" % PORT)
	elif stage == 5 and wait_until == 0 and session.phase == session.Phase.MENU and not session.join_error.is_empty():
		check(session.join_error == UiStyle.IN_PROGRESS, "Mid-match join shows in-progress message (got %s)" % session.join_error)
		stage = 6
		return true
	return false
